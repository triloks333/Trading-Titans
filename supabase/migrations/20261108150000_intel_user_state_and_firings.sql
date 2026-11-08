-- Per-user computed analytics (intel_user_state) and the audit log of every
-- in-app reaction (intel_reaction_firings), both admin-readable and live.
-- Plus: serialise the crash-apology credit so two concurrent calls can't both credit.

-- ── 1. Computed metrics, one row per user (upserted by the app) ──────────────
create table if not exists public.intel_user_state (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  metrics     jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
create index if not exists intel_user_state_updated_idx on public.intel_user_state (updated_at desc);
alter table public.intel_user_state enable row level security;
drop policy if exists "intel_user_state insert own" on public.intel_user_state;
create policy "intel_user_state insert own" on public.intel_user_state
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "intel_user_state update own" on public.intel_user_state;
create policy "intel_user_state update own" on public.intel_user_state
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "intel_user_state read own or admin" on public.intel_user_state;
create policy "intel_user_state read own or admin" on public.intel_user_state
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke all on public.intel_user_state from anon;
grant select, insert, update on public.intel_user_state to authenticated;

-- ── 2. Reaction firings (delivered or suppressed, with the reason) ───────────
create table if not exists public.intel_reaction_firings (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  reaction    text not null,
  delivered   boolean not null,
  reason      text not null,
  props       jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists intel_reaction_firings_created_idx on public.intel_reaction_firings (created_at desc);
create index if not exists intel_reaction_firings_user_idx on public.intel_reaction_firings (user_id, created_at desc);
alter table public.intel_reaction_firings enable row level security;
drop policy if exists "intel_reaction_firings insert own" on public.intel_reaction_firings;
create policy "intel_reaction_firings insert own" on public.intel_reaction_firings
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "intel_reaction_firings read own or admin" on public.intel_reaction_firings;
create policy "intel_reaction_firings read own or admin" on public.intel_reaction_firings
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke all on public.intel_reaction_firings from anon;
grant select, insert on public.intel_reaction_firings to authenticated;

-- ── 3. Realtime for the live dashboard ──────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.intel_user_state; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.intel_reaction_firings; exception when duplicate_object then null; end;
  end if;
end $$;

-- ── 4. Crash apology: one credit per 7 days even under concurrent calls ──────
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
  perform pg_advisory_xact_lock(hashtext('intel_crash_apology:' || uid::text));
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

-- ── 5. Overview: add reaction counts ────────────────────────────────────────
create or replace function public.intel_admin_overview()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp stable
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return jsonb_build_object(
    'users_active_5m',  (select count(distinct user_id) from public.intel_events where created_at > now() - interval '5 minutes'),
    'users_active_24h', (select count(distinct user_id) from public.intel_events where created_at > now() - interval '24 hours'),
    'users_with_state', (select count(*) from public.intel_user_state),
    'events_1h',  (select count(*) from public.intel_events where created_at > now() - interval '1 hour'),
    'events_24h', (select count(*) from public.intel_events where created_at > now() - interval '24 hours'),
    'apologies_7d', (select count(*) from public.intel_apology_credits where created_at > now() - interval '7 days'),
    'reactions_delivered_24h', (select count(*) from public.intel_reaction_firings where delivered and created_at > now() - interval '24 hours'),
    'reactions_suppressed_24h', (select count(*) from public.intel_reaction_firings where not delivered and created_at > now() - interval '24 hours'),
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
