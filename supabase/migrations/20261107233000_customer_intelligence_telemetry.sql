-- Session telemetry table read by the admin intelligence screen.
-- Applied to production 2026-11-08 (as customer_intelligence_telemetry_table_and_admin_read).
--
-- An earlier draft also created v_trader_intelligence_metrics (a view over
-- public.orders) and get_trader_psychology_summary(). Both were dropped before
-- applying: a public view runs with its owner's rights and would have exposed
-- every user's order aggregates to any signed-in user, and nothing used them.

create table if not exists public.user_session_telemetry (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  session_id text not null,
  device_tier text,
  device_model text,
  os_version text,
  network_hash text,
  circadian_window text,
  screen_dwells jsonb default '{}'::jsonb,
  button_clicks jsonb default '{}'::jsonb,
  rage_taps jsonb default '{}'::jsonb,
  symbol_views jsonb default '{}'::jsonb,
  margin_shortfalls jsonb default '{}'::jsonb,
  paywall_stage int default 0,
  downshift_999_599 boolean default false,
  created_at timestamptz not null default now()
);
create index if not exists user_session_telemetry_created_idx on public.user_session_telemetry (created_at desc);

alter table public.user_session_telemetry enable row level security;

drop policy if exists "Own telemetry insert" on public.user_session_telemetry;
create policy "Own telemetry insert" on public.user_session_telemetry
  for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists "Own telemetry read" on public.user_session_telemetry;
create policy "Own telemetry read" on public.user_session_telemetry
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Admin telemetry read" on public.user_session_telemetry;
create policy "Admin telemetry read" on public.user_session_telemetry
  for select to authenticated using (public.is_admin());

revoke all on public.user_session_telemetry from anon;
grant select, insert on public.user_session_telemetry to authenticated;
