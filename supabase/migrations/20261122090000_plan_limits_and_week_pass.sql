-- Plan limits (free / pro / titan) and the 7-day Pro pass (₹1 first week, then ₹29).
--
-- ── WHAT THIS ADDS ─────────────────────────────────────────────────────────
-- 1. plan_limit(tier, feature): the one table of numbers. Change a limit here and
--    the app, place-order, trade-autopsy and the triggers below all follow.
-- 2. feature_usage: a log of metered uses (F&O opening trades, autopsies, what-ifs).
-- 3. consume_feature(): the only writer of feature_usage. Atomic per user+feature.
-- 4. my_plan_usage(): what the app reads to show "2 of 3 used" and lock screens.
-- 5. Triggers that cap price alerts, watchlists and watchlist symbols for free users.
-- 6. Weekly prepaid passes: pro_trial_week (₹1, once per account) and pro_week (₹29).
--
-- ── WHEN LIMITS APPLY ──────────────────────────────────────────────────────
-- Only while app_flags.monetization_enabled is true. With it off the app tells
-- users "everything is free", so the limits must be off too or they would hit a
-- wall with no way to pay past it.
--
-- ── WHAT COUNTS AS AN F&O TRADE ────────────────────────────────────────────
-- An order that OPENS or adds to a futures/options position, counted when
-- place-order accepts it. Exit orders are never counted and never blocked, so a
-- user who runs out can always close what they hold. An order the engine rejects
-- is refunded by place-order. A pending limit order the user cancels later is not.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
-- drop trigger trg_price_alert_limit on public.price_alerts;
-- drop trigger trg_watchlists_limit on public.watchlists;
-- drop trigger trg_watchlist_symbol_limit on public.watchlist;
-- drop function public.my_plan_usage(), public.use_feature(text,text),
--   public.consume_feature(uuid,text,text), public.refund_feature(bigint),
--   public.autopsy_unlock(uuid,uuid[]), public.pro_trial_eligible(uuid),
--   public.feature_used(uuid,text), public.feature_window_start(text),
--   public.limits_enforced(), public.user_limit(uuid,text), public.plan_limit(text,text),
--   public.enforce_price_alert_limit(), public.enforce_watchlists_limit(),
--   public.enforce_watchlist_symbol_limit();
-- drop table public.feature_usage;
-- update public.plan_catalogue set is_active = false where sku in ('pro_trial_week','pro_week');

-- ── 1. The numbers ──────────────────────────────────────────────────────────
-- null = unlimited.
create or replace function public.plan_limit(p_tier text, p_feature text)
returns integer
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select case p_feature
    when 'fo_trades_month'   then case p_tier when 'free' then 3 when 'pro' then 25 else null end
    when 'autopsy_month'     then case p_tier when 'free' then 3  else null end
    when 'whatif_day'        then case p_tier when 'free' then 1  else null end
    when 'price_alerts'      then case p_tier when 'free' then 3  else null end
    when 'watchlists'        then case p_tier when 'free' then 1  else null end
    when 'watchlist_symbols' then case p_tier when 'free' then 10 else null end
    when 'history_days'      then case p_tier when 'free' then 7  else null end
    when 'chart_days'        then case p_tier when 'free' then 31 else null end
    else null
  end;
$$;

create or replace function public.limits_enforced()
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce((select enabled from public.app_flags where key = 'monetization_enabled'), false);
$$;

-- Effective limit for a user: null when limits are off or the tier is unlimited.
create or replace function public.user_limit(p_user uuid, p_feature text)
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select case when public.limits_enforced()
              then public.plan_limit(public.current_tier(p_user), p_feature)
              else null end;
$$;

-- ── 2. Usage log ────────────────────────────────────────────────────────────
create table if not exists public.feature_usage (
  id       bigserial primary key,
  user_id  uuid not null references auth.users(id) on delete cascade,
  feature  text not null,
  -- Optional idempotency key, e.g. the order id an autopsy was unlocked for.
  ref      text,
  used_at  timestamptz not null default now()
);
create index if not exists feature_usage_user_feature_time
  on public.feature_usage (user_id, feature, used_at desc);
create unique index if not exists feature_usage_user_feature_ref
  on public.feature_usage (user_id, feature, ref) where ref is not null;

alter table public.feature_usage enable row level security;
drop policy if exists feature_usage_own_read on public.feature_usage;
create policy feature_usage_own_read on public.feature_usage
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on public.feature_usage from anon, authenticated;

-- Window start in IST: calendar month for *_month features, day for *_day.
create or replace function public.feature_window_start(p_feature text)
returns timestamptz
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select case
    when p_feature like '%\_day' then date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
    else date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
  end;
$$;

create or replace function public.feature_used(p_user uuid, p_feature text)
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select count(*)::int from public.feature_usage
   where user_id = p_user and feature = p_feature
     and used_at >= public.feature_window_start(p_feature);
$$;

-- ── 3. Consume ──────────────────────────────────────────────────────────────
-- Returns {allowed, used, limit, tier, usage_id}. With p_ref, a ref already
-- consumed (in any window) is allowed again without counting twice.
create or replace function public.consume_feature(p_user uuid, p_feature text, p_ref text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_tier  text := public.current_tier(p_user);
  v_limit int  := public.user_limit(p_user, p_feature);
  v_used  int;
  v_id    bigint;
begin
  -- Serialise this user's consumption of this feature so two parallel orders
  -- cannot both take the last slot.
  perform pg_advisory_xact_lock(hashtext(p_user::text || ':' || p_feature));

  if p_ref is not null and exists (
    select 1 from public.feature_usage where user_id = p_user and feature = p_feature and ref = p_ref
  ) then
    return jsonb_build_object('allowed', true, 'used', public.feature_used(p_user, p_feature),
                              'limit', v_limit, 'tier', v_tier, 'usage_id', null);
  end if;

  v_used := public.feature_used(p_user, p_feature);
  if v_limit is not null and v_used >= v_limit then
    return jsonb_build_object('allowed', false, 'used', v_used, 'limit', v_limit, 'tier', v_tier, 'usage_id', null);
  end if;

  insert into public.feature_usage (user_id, feature, ref) values (p_user, p_feature, p_ref)
  returning id into v_id;
  return jsonb_build_object('allowed', true, 'used', v_used + 1, 'limit', v_limit, 'tier', v_tier, 'usage_id', v_id);
end;
$$;
revoke execute on function public.consume_feature(uuid, text, text) from public, anon, authenticated;
grant execute on function public.consume_feature(uuid, text, text) to service_role;

create or replace function public.refund_feature(p_usage_id bigint)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  delete from public.feature_usage where id = p_usage_id;
$$;
revoke execute on function public.refund_feature(bigint) from public, anon, authenticated;
grant execute on function public.refund_feature(bigint) to service_role;

-- Client-callable, but only for features metered on the client (what-if).
create or replace function public.use_feature(p_feature text, p_ref text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_feature not in ('whatif_day') then raise exception 'feature % is not client-metered', p_feature; end if;
  return public.consume_feature(auth.uid(), p_feature, p_ref);
end;
$$;
revoke execute on function public.use_feature(text, text) from public, anon;
grant execute on function public.use_feature(text, text) to authenticated;

-- Autopsy: given order ids newest first, returns those whose advice the user may
-- see, unlocking new ones while this month's allowance lasts. Unlocked stays unlocked.
create or replace function public.autopsy_unlock(p_user uuid, p_order_ids uuid[])
returns uuid[]
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_out uuid[] := '{}';
  v_id  uuid;
  v_res jsonb;
begin
  if public.user_limit(p_user, 'autopsy_month') is null then
    return p_order_ids;
  end if;
  foreach v_id in array p_order_ids loop
    v_res := public.consume_feature(p_user, 'autopsy_month', v_id::text);
    if (v_res->>'allowed')::boolean then v_out := v_out || v_id; end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function public.autopsy_unlock(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.autopsy_unlock(uuid, uuid[]) to service_role;

-- ── 4. Trial eligibility and the app's usage summary ────────────────────────
-- The ₹1 week is for accounts that have never paid for a plan or a pass.
create or replace function public.pro_trial_eligible(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select p_user is not null
     and not exists (select 1 from public.subscriptions s
                      where s.user_id = p_user and s.status <> 'created')
     and not exists (select 1 from public.payment_orders o
                      where o.user_id = p_user and o.sku = 'pro_trial_week' and o.status = 'paid');
$$;
revoke execute on function public.pro_trial_eligible(uuid) from public, anon;
grant execute on function public.pro_trial_eligible(uuid) to authenticated, service_role;

create or replace function public.my_plan_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_user uuid := auth.uid();
  v_out  jsonb := '{}'::jsonb;
  f      text;
begin
  if v_user is null then return null; end if;
  foreach f in array array['fo_trades_month','autopsy_month','whatif_day','price_alerts',
                           'watchlists','watchlist_symbols','history_days','chart_days'] loop
    v_out := v_out || jsonb_build_object(f, jsonb_build_object(
      'limit', public.user_limit(v_user, f),
      'used', case f
        when 'price_alerts' then (select count(*) from public.price_alerts where user_id = v_user and status = 'active')
        when 'watchlists' then (select count(*) from public.watchlists where user_id = v_user)
        when 'watchlist_symbols' then (select count(*) from public.watchlist where user_id = v_user)
        when 'history_days' then 0
        when 'chart_days' then 0
        else public.feature_used(v_user, f) end));
  end loop;
  return jsonb_build_object(
    'tier', public.current_tier(v_user),
    'enforced', public.limits_enforced(),
    'trial_eligible', public.pro_trial_eligible(v_user),
    'pass_ends_at', (select max(current_period_end) from public.subscriptions
                      where user_id = v_user and sku in ('pro_trial_week','pro_week')
                        and status = 'active' and current_period_end > now()),
    'limits', v_out);
end;
$$;
revoke execute on function public.my_plan_usage() from public, anon;
grant execute on function public.my_plan_usage() to authenticated;

-- ── 5. Caps on stored things ────────────────────────────────────────────────
-- The error text starts with PLAN_LIMIT: so the app can show an upgrade sheet.
create or replace function public.enforce_price_alert_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_limit int := public.user_limit(new.user_id, 'price_alerts');
begin
  if v_limit is not null and coalesce(new.status, 'active') = 'active' and
     (select count(*) from public.price_alerts where user_id = new.user_id and status = 'active') >= v_limit then
    raise exception 'PLAN_LIMIT:price_alerts:%', v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_price_alert_limit on public.price_alerts;
create trigger trg_price_alert_limit before insert on public.price_alerts
  for each row execute function public.enforce_price_alert_limit();

create or replace function public.enforce_watchlists_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_limit int := public.user_limit(new.user_id, 'watchlists');
begin
  if v_limit is not null and
     (select count(*) from public.watchlists where user_id = new.user_id) >= v_limit then
    raise exception 'PLAN_LIMIT:watchlists:%', v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_watchlists_limit on public.watchlists;
create trigger trg_watchlists_limit before insert on public.watchlists
  for each row execute function public.enforce_watchlists_limit();

-- The app adds symbols with an upsert on (user_id, symbol, market). BEFORE INSERT
-- fires for an upsert that will only update, so an already-watched symbol is let
-- through or a full list could never be re-saved.
create or replace function public.enforce_watchlist_symbol_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_limit int := public.user_limit(new.user_id, 'watchlist_symbols');
begin
  if v_limit is not null
     and not exists (select 1 from public.watchlist
                      where user_id = new.user_id and symbol = new.symbol and market = new.market)
     and (select count(*) from public.watchlist where user_id = new.user_id) >= v_limit then
    raise exception 'PLAN_LIMIT:watchlist_symbols:%', v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_watchlist_symbol_limit on public.watchlist;
create trigger trg_watchlist_symbol_limit before insert on public.watchlist
  for each row execute function public.enforce_watchlist_symbol_limit();

-- ── 6. Weekly passes ────────────────────────────────────────────────────────
alter table public.plan_catalogue drop constraint if exists plan_catalogue_billing_interval_check;
alter table public.plan_catalogue add constraint plan_catalogue_billing_interval_check
  check (billing_interval = any (array['weekly'::text, 'monthly'::text, 'annual'::text]));

-- Prepaid, not recurring: create-payment-order sells subscriptions as one order
-- and razorpay-webhook grants 7 days for a weekly SKU. No stipend, no cash.
-- INR only (no USD price), so accounts billed in dollars are refused cleanly.
insert into public.plan_catalogue
  (sku, tier, kind, title, price_paise, price_usd_cents, billing_interval, cash_grant, monthly_stipend, sort_order, is_active)
values
  ('pro_trial_week', 'pro', 'subscription', 'Pro 7-day trial', 100,  null, 'weekly', 0, 0, 1, true),
  ('pro_week',       'pro', 'subscription', 'Pro 7-day pass',  2900, null, 'weekly', 0, 0, 2, true)
on conflict (sku) do update
  set title = excluded.title, price_paise = excluded.price_paise, billing_interval = excluded.billing_interval,
      tier = excluded.tier, kind = excluded.kind, cash_grant = 0, monthly_stipend = 0, is_active = true;
