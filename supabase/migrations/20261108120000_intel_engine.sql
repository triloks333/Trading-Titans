-- Product analytics event stream for the live admin Intelligence dashboard,
-- plus the crash-apology credit (fixed ₹2,500 DEMO cash, once per 7 days).
-- Nothing here touches orders, holdings, prices or the execution engine.

-- ── 1. Raw event stream ─────────────────────────────────────────────────────
create table if not exists public.intel_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  session_id  text not null,
  name        text not null,
  props       jsonb not null default '{}'::jsonb,
  client_ts   timestamptz not null,
  created_at  timestamptz not null default now()
);
create index if not exists intel_events_created_idx on public.intel_events (created_at desc);
create index if not exists intel_events_user_idx on public.intel_events (user_id, created_at desc);
create index if not exists intel_events_name_idx on public.intel_events (name, created_at desc);

alter table public.intel_events enable row level security;
drop policy if exists "intel_events insert own" on public.intel_events;
create policy "intel_events insert own" on public.intel_events
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "intel_events read own or admin" on public.intel_events;
create policy "intel_events read own or admin" on public.intel_events
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
grant select, insert on public.intel_events to authenticated;

-- ── 2. Crash apology: fixed ₹2,500 demo cash, once per 7 days ────────────────
create table if not exists public.intel_apology_credits (
  user_id     uuid not null references auth.users(id) on delete cascade,
  amount      numeric not null,
  created_at  timestamptz not null default now()
);
create index if not exists intel_apology_credits_user_idx on public.intel_apology_credits (user_id, created_at desc);
alter table public.intel_apology_credits enable row level security;
drop policy if exists "intel_apology_credits read own or admin" on public.intel_apology_credits;
create policy "intel_apology_credits read own or admin" on public.intel_apology_credits
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
grant select on public.intel_apology_credits to authenticated;

-- Returns the new wallet balance, or null when nothing was credited
-- (guest, or already credited in the last 7 days).
create or replace function public.intel_claim_crash_apology()
returns numeric
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  new_balance numeric;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then return null; end if;
  if exists (select 1 from public.intel_apology_credits
             where user_id = uid and created_at > now() - interval '7 days') then
    return null;
  end if;
  perform set_config('app.wallet_reason', 'crash_apology', true);
  update public.profiles set wallet_balance = wallet_balance + 2500
    where id = uid returning wallet_balance into new_balance;
  if new_balance is null then return null; end if;
  insert into public.intel_apology_credits (user_id, amount) values (uid, 2500);
  return new_balance;
end $$;
revoke all on function public.intel_claim_crash_apology() from public, anon;
grant execute on function public.intel_claim_crash_apology() to authenticated;

-- ── 3. Admin overview (counts only) ─────────────────────────────────────────
create or replace function public.intel_admin_overview()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp stable
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return jsonb_build_object(
    'users_active_5m',  (select count(distinct user_id) from public.intel_events where created_at > now() - interval '5 minutes'),
    'users_active_24h', (select count(distinct user_id) from public.intel_events where created_at > now() - interval '24 hours'),
    'events_1h',  (select count(*) from public.intel_events where created_at > now() - interval '1 hour'),
    'events_24h', (select count(*) from public.intel_events where created_at > now() - interval '24 hours'),
    'apologies_7d', (select count(*) from public.intel_apology_credits where created_at > now() - interval '7 days'),
    'events_by_name_24h', (select coalesce(jsonb_object_agg(name, n), '{}') from (
        select name, count(*) n from public.intel_events
        where created_at > now() - interval '24 hours' group by name order by n desc limit 40) e),
    'events_per_minute_60m', (select coalesce(jsonb_agg(jsonb_build_array(m, n) order by m), '[]') from (
        select date_trunc('minute', created_at) m, count(*) n from public.intel_events
        where created_at > now() - interval '60 minutes' group by 1) t)
  );
end $$;
revoke all on function public.intel_admin_overview() from public, anon;
grant execute on function public.intel_admin_overview() to authenticated;

-- ── 4. Realtime for the live dashboard ──────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.intel_events; exception when duplicate_object then null; end;
  end if;
end $$;

-- Keep the event stream bounded (90 days).
create or replace function public.intel_prune_events() returns void
language sql security definer set search_path = public, pg_temp
as $$ delete from public.intel_events where created_at < now() - interval '90 days'; $$;
revoke all on function public.intel_prune_events() from public, anon, authenticated;
