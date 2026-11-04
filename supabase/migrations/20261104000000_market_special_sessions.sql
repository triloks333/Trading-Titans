-- One-off exchange sessions outside the normal week, e.g. Diwali Muhurat trading.
--
-- The twin of market_holidays: that table closes a normal day, this one opens an
-- abnormal window. The app reads it on every foreground (MarketHours.specialSessions)
-- to show the Muhurat countdown and treat the market as open for the window, so the
-- exchange's announced timing needs no app release.
--
-- Edge functions gate fills with _shared/market_hours.ts SPECIAL_SESSIONS. Add the
-- same window there and redeploy place-order, execute-pending-orders,
-- refresh-quotes, evaluate-price-alerts and market-status.
--
-- Add a session once NSE publishes the time (example, times are IST):
--   insert into public.market_special_sessions (market, name, opens_at, closes_at)
--   values ('stock', 'Muhurat Trading', '2026-11-08 18:00+05:30', '2026-11-08 19:00+05:30');
--
-- Rollback: drop table if exists public.market_special_sessions;

create table if not exists public.market_special_sessions (
    id         bigint generated always as identity primary key,
    market     text not null default 'stock' check (market in ('stock')),
    name       text not null default 'Muhurat Trading',
    opens_at   timestamptz not null,
    closes_at  timestamptz not null check (closes_at > opens_at),
    created_at timestamptz not null default now()
);

alter table public.market_special_sessions enable row level security;

drop policy if exists market_special_sessions_read on public.market_special_sessions;
create policy market_special_sessions_read on public.market_special_sessions
    for select to anon, authenticated using (true);

grant select on public.market_special_sessions to anon, authenticated;
revoke insert, update, delete on public.market_special_sessions from anon, authenticated;
