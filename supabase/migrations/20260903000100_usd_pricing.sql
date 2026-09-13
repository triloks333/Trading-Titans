-- Dual-currency pricing for plan_catalogue
-- ============================================================================
-- WHY
-- Prices were INR-only: `price_paise` plus one `razorpay_plan_id`, and
-- create-payment-order hardcoded `currency: "INR"`. 23 accounts are outside India
-- and had no way to be billed in their own currency, and both clients rendered
-- rupees at them.
--
-- SHAPE: TWO PRICES PER ROW, NOT TWO ROWS PER PRODUCT
-- One row per product with a second price beside the first, rather than duplicate
-- `pro_monthly_usd` SKUs. A SKU is what the clients pass to create-payment-order
-- and what payment_orders/subscriptions reference, so splitting it would mean
-- every caller learning about currency variants, and `subscriptions.sku` would
-- stop identifying "which plan" on its own. Currency is a property of the
-- purchase, not of the product.
--
-- WHY USD PRICES ARE NOT CONVERSIONS
-- These are native price points set in the Razorpay dashboard, not `price_paise`
-- divided by an FX rate. A Razorpay Plan's amount and currency are fixed at
-- creation, so the number here MUST equal the number on the plan or the customer
-- is shown one price and charged another. $2 against ₹149 is a deliberate ~18%
-- premium at today's rate; the annual tiers round the other way.
--
-- NOTE ON THE ANNUAL PLANS
-- The first attempt at these was created with `period: monthly`, so "Pro Annual
-- $13" would have billed $13 every month — $156/year for a $13 product. A plan's
-- period is immutable, so those two were recreated as yearly and the ids below are
-- the corrected ones. Anything that creates a Razorpay Plan in future must have
-- its billing cycle checked against the plan name before it is sold.
--
-- EXPECTED AFFECTED OBJECTS
--   plan_catalogue: + price_usd_cents, + razorpay_plan_id_usd, + a CHECK
--   payment_orders: + provider_payment_link_id (for the app's hosted-link flow)
--   7 plan_catalogue rows updated with USD prices; 4 with USD plan ids
--   No policy, grant or function is touched.
--
-- CLIENT COMPATIBILITY IMPACT
-- Additive. Existing clients select the columns they already know and keep
-- charging INR; nothing breaks while 1.2.0 is rolling out. USD only becomes
-- reachable once create-payment-order is redeployed to choose a currency.
--
-- ROLLBACK
--   alter table public.plan_catalogue
--     drop constraint if exists usd_price_and_plan_together,
--     drop column if exists price_usd_cents,
--     drop column if exists razorpay_plan_id_usd;
--   alter table public.payment_orders drop column if exists provider_payment_link_id;

alter table public.plan_catalogue
  add column if not exists price_usd_cents integer,
  add column if not exists razorpay_plan_id_usd text;

comment on column public.plan_catalogue.price_usd_cents is
  'Native USD price in cents, NOT a conversion of price_paise. Must equal the '
  'amount on the matching Razorpay plan (razorpay_plan_id_usd) or the customer is '
  'quoted one price and charged another.';

comment on column public.plan_catalogue.razorpay_plan_id_usd is
  'The USD Razorpay Plan. A plan''s amount, currency and billing period are all '
  'immutable, so changing any of them means creating a new plan and updating this '
  'column. Verify the billing cycle matches the plan name before selling it.';

comment on column public.plan_catalogue.price_paise is
  'Native INR price in paise. See price_usd_cents for the USD equivalent; the two '
  'are independent price points, not conversions of each other.';

-- ── USD price points ────────────────────────────────────────────────────────
-- Subscriptions: exactly the amounts on the Razorpay plans below.
update public.plan_catalogue set price_usd_cents =  200, razorpay_plan_id_usd = 'plan_TXaIO2FZqjiKBu' where sku = 'pro_monthly';
update public.plan_catalogue set price_usd_cents = 1300, razorpay_plan_id_usd = 'plan_TXaPEToH4q5C8A' where sku = 'pro_annual';
update public.plan_catalogue set price_usd_cents =  900, razorpay_plan_id_usd = 'plan_TXaKcdrKTycqfa' where sku = 'titan_monthly';
update public.plan_catalogue set price_usd_cents = 6400, razorpay_plan_id_usd = 'plan_TXaPYQF2kTN1Fi' where sku = 'titan_annual';

-- Top-ups are one-time Orders, not Plans, so they need an amount and no plan id.
-- Set just above the FX conversion of the rupee price, and kept above Pro Monthly
-- ($2) because a one-time top-up costs more than a month of Pro in INR too — the
-- ordering has to survive the currency change.
update public.plan_catalogue set price_usd_cents =  249 where sku = 'topup_boost';  -- ₹199
update public.plan_catalogue set price_usd_cents =  699 where sku = 'topup_plus';   -- ₹599
update public.plan_catalogue set price_usd_cents = 1199 where sku = 'topup_max';    -- ₹999

-- A subscription priced in USD with no USD plan is unsellable, and a USD plan with
-- no price would be sold at whatever the client guessed. Neither half is useful
-- alone.
alter table public.plan_catalogue
  drop constraint if exists usd_price_and_plan_together;
alter table public.plan_catalogue
  add constraint usd_price_and_plan_together check (
    kind <> 'subscription'
    or (price_usd_cents is null) = (razorpay_plan_id_usd is null)
  );

-- ── Hosted payment links ────────────────────────────────────────────────────
-- The app hands checkout to a Razorpay-hosted page rather than the web app, so
-- there is a third provider id to reconcile a webhook against.
alter table public.payment_orders
  add column if not exists provider_payment_link_id text;

create index if not exists payment_orders_payment_link_idx
  on public.payment_orders (provider_payment_link_id)
  where provider_payment_link_id is not null;

comment on column public.payment_orders.amount_paise is
  'Amount charged in the MINOR unit of payment_orders.currency: paise for INR, '
  'cents for USD. The name predates multi-currency. razorpay-webhook compares the '
  'provider''s amount against this, so both must be the same currency and unit.';
