-- Per-type push switches for Settings → Notifications.
--
-- One row per user, created on first save; no row means everything is on. The
-- switches only stop the PHONE push: the notifications row is still written, so
-- the in-app inbox keeps every message. push-notification reads this table with
-- the service role and skips the push when the type's switch is off.
--
-- Groups (keep in step with prefKeyFor() in functions/push-notification):
--   price  : price_alert
--   orders : order, order_executed, order_pending, order_failed, trade, expiry, risk_alert
--   league : reward, league
--   news   : news
-- Chat has its own mute, and account/broadcast messages always send.

create table if not exists public.notification_preferences (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  price      boolean not null default true,
  orders     boolean not null default true,
  league     boolean not null default true,
  news       boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "Own notification preferences: read" on public.notification_preferences;
create policy "Own notification preferences: read" on public.notification_preferences
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "Own notification preferences: insert" on public.notification_preferences;
create policy "Own notification preferences: insert" on public.notification_preferences
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Own notification preferences: update" on public.notification_preferences;
create policy "Own notification preferences: update" on public.notification_preferences
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.notification_preferences from anon;
grant select, insert, update on public.notification_preferences to authenticated;
