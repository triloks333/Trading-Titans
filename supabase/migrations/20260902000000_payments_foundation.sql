-- Payments foundation: catalogue, orders, webhook events, subscriptions.
-- ============================================================================
-- STATUS: NOT APPLIED. For review.
--
-- Decisions this encodes (from docs/monetisation-pricing.md §7):
--   D1  stipends ₹50,000/mo Pro, ₹5,00,000/mo Titan, non-cumulative
--   D2  purchased cash is floored and survives any wallet reset
--   D3  Titan annual ₹5,999
--   D4  no free trial
--   D7  no ads, ever
--   D8  web checkout via Razorpay, in-app handoff
--   D9  Pro and Titan both live at launch
--   D10 no grandfathering — every account starts free and upgrades itself
--   Auto-renewing subscriptions via Razorpay Subscriptions
--   Prices are GST-INCLUSIVE: the displayed number is what the user pays, and
--   never changes when GST registration lands. Only our net moves.
--
-- Replaces the revoked credit_demo_cash / activate_subscription, which credited
-- wallets with no payment check at all. Nothing here can move money without a
-- `payment_orders` row that a signature-verified webhook marked paid.

-- ── 1. Catalogue ────────────────────────────────────────────────────────────
-- Prices live in a table, not in Dart/TS. The old hard-coded plan map in
-- supabase_service.dart is exactly why three clients could disagree about what a
-- pack cost. Changing a price is now one UPDATE, no release.
create table if not exists public.plan_catalogue (
  sku               text primary key,
  tier              text not null check (tier in ('topup','pro','titan')),
  kind              text not null check (kind in ('one_time','subscription')),
  title             text not null,
  -- GST-inclusive, in paise. Integer on purpose: money in a float is a bug
  -- waiting for a rounding edge case.
  price_paise       integer not null check (price_paise > 0),
  billing_interval  text check (billing_interval in ('monthly','annual')),
  -- One-time packs only: virtual cash credited on payment.
  cash_grant        numeric not null default 0 check (cash_grant >= 0),
  -- Subscriptions only: monthly non-cumulative stipend.
  monthly_stipend   numeric not null default 0 check (monthly_stipend >= 0),
  -- Razorpay Plan id, e.g. plan_XXXXXXXX. Required before a subscription SKU can
  -- be sold; NULL is how we know it is not sellable yet.
  razorpay_plan_id  text,
  is_active         boolean not null default true,
  sort_order        integer not null default 0,
  constraint interval_matches_kind check (
    (kind = 'subscription' and billing_interval is not null)
    or (kind = 'one_time' and billing_interval is null)
  )
);

alter table public.plan_catalogue enable row level security;

-- The catalogue is public reading: the web pricing page and the app both need it.
-- No write policy, so only the service role can change prices.
create policy "plan_catalogue readable by anyone"
  on public.plan_catalogue for select using (true);

insert into public.plan_catalogue
  (sku, tier, kind, title, price_paise, billing_interval, cash_grant, monthly_stipend, sort_order)
values
  ('topup_boost',  'topup', 'one_time',     'Boost',        19900, null,  100000, 0, 10),
  ('topup_plus',   'topup', 'one_time',     'Plus',         59900, null,  500000, 0, 20),
  ('topup_max',    'topup', 'one_time',     'Max',          99900, null, 1000000, 0, 30),
  ('pro_monthly',  'pro',   'subscription', 'Pro Monthly',  14900, 'monthly', 0,  50000, 40),
  ('pro_annual',   'pro',   'subscription', 'Pro Annual',  119900, 'annual',  0,  50000, 50),
  ('titan_monthly','titan', 'subscription', 'Titan Monthly',79900, 'monthly', 0, 500000, 60),
  ('titan_annual', 'titan', 'subscription', 'Titan Annual',599900, 'annual',  0, 500000, 70)
on conflict (sku) do nothing;

-- ── 2. Payment orders ───────────────────────────────────────────────────────
create table if not exists public.payment_orders (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references public.profiles(id) on delete cascade,
  sku                       text not null references public.plan_catalogue(sku),
  kind                      text not null check (kind in ('one_time','subscription')),
  provider                  text not null default 'razorpay',
  provider_order_id         text unique,
  provider_subscription_id  text,
  amount_paise              integer not null check (amount_paise > 0),
  currency                  text not null default 'INR',
  status                    text not null default 'created'
                              check (status in ('created','paid','failed','refunded')),
  created_at                timestamptz not null default now(),
  paid_at                   timestamptz
);

create index if not exists payment_orders_user_idx on public.payment_orders (user_id, created_at desc);
create index if not exists payment_orders_sub_idx  on public.payment_orders (provider_subscription_id);

alter table public.payment_orders enable row level security;
create policy "payment_orders select own"
  on public.payment_orders for select
  using ((select auth.uid()) = user_id);
-- No client write policy: created by create-payment-order, settled by the webhook.

-- ── 3. Webhook events — the idempotency ledger ──────────────────────────────
-- `provider_event_id` UNIQUE is the whole point. Razorpay retries webhooks, and
-- without this a single renewal would credit a stipend more than once. The
-- handler inserts here FIRST and treats a unique violation as "already handled".
create table if not exists public.payment_events (
  id                 uuid primary key default gen_random_uuid(),
  provider           text not null default 'razorpay',
  provider_event_id  text not null unique,
  event_type         text not null,
  payload            jsonb not null,
  order_id           uuid references public.payment_orders(id) on delete set null,
  received_at        timestamptz not null default now(),
  handled_at         timestamptz,
  handler_error      text
);

create index if not exists payment_events_type_idx on public.payment_events (event_type, received_at desc);

alter table public.payment_events enable row level security;
-- No policy at all: raw gateway payloads are nobody's business but the server's.

-- ── 4. Subscriptions ────────────────────────────────────────────────────────
-- Statuses mirror Razorpay's own so there is no translation layer to get wrong:
--   created   checkout started, first charge not yet confirmed
--   active    paid and inside the current period
--   pending   a renewal failed and Razorpay is retrying
--   halted    retries exhausted — access lapses
--   cancelled user or we cancelled
--   expired   ran to its natural end
create table if not exists public.subscriptions (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references public.profiles(id) on delete cascade,
  sku                       text not null references public.plan_catalogue(sku),
  tier                      text not null check (tier in ('pro','titan')),
  provider                  text not null default 'razorpay',
  provider_subscription_id  text unique,
  status                    text not null default 'created'
                              check (status in ('created','active','pending','halted','cancelled','expired')),
  current_period_start      timestamptz,
  current_period_end        timestamptz,
  cancel_at_period_end      boolean not null default false,
  last_charged_at           timestamptz,
  -- Non-cumulative stipend: this records the month last paid out so a second
  -- webhook for the same period cannot double-credit, and an unused month
  -- simply lapses rather than accruing.
  stipend_last_paid_period  date,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index if not exists subscriptions_user_idx on public.subscriptions (user_id, status);

alter table public.subscriptions enable row level security;
create policy "subscriptions select own"
  on public.subscriptions for select
  using ((select auth.uid()) = user_id);
-- No client write policy: the webhook owns every status transition.

-- ── 5. Purchased cash floor (D2) ────────────────────────────────────────────
-- Virtual cash somebody PAID for must survive a seasonal wallet reset. Wiping it
-- is a refund conversation and a chargeback, so the floor is recorded at the
-- moment of purchase rather than reconstructed from order history later.
alter table public.profiles
  add column if not exists purchased_cash_floor numeric not null default 0;

comment on column public.profiles.purchased_cash_floor is
  'Sum of virtual cash the user has PAID for. Any wallet reset must clamp '
  'wallet_balance to at least this value. Increased only by a verified top-up.';

-- ── 6. The single tier read path ────────────────────────────────────────────
-- ponytail: tier is DERIVED from `subscriptions` rather than kept in a separate
-- entitlements table. One source of truth means no sync bug, and with exactly two
-- paid tiers and no promos, grandfathering or per-user overrides (D10: same for
-- everyone) a second table would only be something to keep in step. The ceiling
-- is per-feature overrides — a promo, a comped account, an enterprise seat; the
-- upgrade path is an `entitlements (user_id, feature)` table that this function
-- consults first and falls back to here.
create or replace function public.current_tier(p_user_id uuid default auth.uid())
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(
    (select s.tier
       from public.subscriptions s
      where s.user_id = p_user_id
        and s.status in ('active','pending')   -- pending = retrying, keep access
        and (s.current_period_end is null or s.current_period_end > now())
      -- Titan outranks Pro if both somehow exist.
      order by case s.tier when 'titan' then 2 when 'pro' then 1 else 0 end desc
      limit 1),
    'free'
  );
$$;

comment on function public.current_tier(uuid) is
  'The single source of truth for a user''s paid tier: free | pro | titan. '
  'Derived from subscriptions; never stored on profiles. Clients and '
  'place-order both read this rather than computing access from plan strings.';

revoke execute on function public.current_tier(uuid) from public;
grant execute on function public.current_tier(uuid) to authenticated, service_role;

-- ── 7. Plan badge beside the username ───────────────────────────────────────
-- Requested: the tier must be visible on the profile AND the leaderboard. Exposed
-- as a view so the badge cannot leak anything else about another account —
-- `profiles` itself stays own-row-only.
create or replace view public.user_tiers as
  select p.id as user_id, public.current_tier(p.id) as tier
    from public.profiles p;

comment on view public.user_tiers is
  'user_id -> free|pro|titan, for the plan badge on profiles and the leaderboard. '
  'Deliberately exposes ONLY the tier: it is public-by-design social proof, and '
  'nothing else about another user becomes readable through it.';

grant select on public.user_tiers to authenticated;
