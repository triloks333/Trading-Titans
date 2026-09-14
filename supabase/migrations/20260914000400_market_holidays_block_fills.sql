-- Close a market for a whole day, without an app release or an edge deploy.
--
-- Applied to production as version 20260914042919
-- (name `market_holidays_block_fills`).
--
-- Requested: shut the Indian stock market for Ganesh Chaturthi, leaving crypto and
-- US stocks trading, with the explicit constraint that nothing may require users to
-- update the app.
--
-- ── WHY THIS IS IN POSTGRES AND NOT IN THE EDGE FUNCTION ───────────────────
-- The session gate lives in `_shared/market_hours.ts`, and four comments across the
-- codebase propose exactly this table as its upgrade path. But changing that helper
-- means redeploying `execute-pending-orders` — a 482-line money path importing five
-- shared modules — and the repo has already been caught drifting from what was
-- actually deployed (push-notification, v4). Redeploying all of that mid-session to
-- add a holiday is a bad trade.
--
-- So the interception happens at the engine's OWN claim step instead:
--
--   update orders set status='executing' where id=? and status='pending'
--
-- `claim()` returns false when that affects zero rows, and the engine then reports
-- `skipped: "claim_lost"` and moves on. That is a path it already handles, and it
-- runs BEFORE any wallet, holding or margin is touched. A BEFORE UPDATE trigger
-- returning NULL cancels the update silently, which is precisely a zero-row result.
--
-- Deliberately NOT `raise exception`: place-order calls the engine synchronously, so
-- an exception would reach the user as a failed order instead of a pending one.
-- Declining the claim leaves the order pending and it fills when the market genuinely
-- reopens, which is what a holiday should do.
--
-- The hardcoded holiday set that was briefly added to `_shared/market_hours.ts` was
-- REVERTED on purpose. Two holiday lists would drift the moment a date was added to
-- one of them, and this codebase already carries that scar twice with the owner email
-- list. This table is the single source of truth.
--
-- ── WHAT USERS ON THE SHIPPED APP SEE ──────────────────────────────────────
-- The badge still reads "Market Open", because that is computed on-device by
-- core/market_hours.dart and cannot change without a release. Orders placed today are
-- accepted and sit as "Order Pending" — the same experience as ordering after 15:30.
-- Nothing fills and no money moves. Making the badge honest needs a client release
-- and is deliberately out of scope, since the constraint was no forced update.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.market_holidays                  new
--   public.block_fills_on_market_holiday    new (trigger function)
--   trg_block_fills_on_market_holiday       new, BEFORE UPDATE on public.orders
--
-- Scoped to market = 'stock', which covers Indian equities AND Indian F&O. Crypto is
-- 'crypto' and US equities are 'us_stock', so neither is affected — confirmed against
-- place-order's own validation, which accepts exactly those three values.
--
-- Only the pending -> executing transition is intercepted, so cancelling, failing and
-- the post-fill write all still work and a user can still cancel a resting order.
--
-- ── VERIFIED ───────────────────────────────────────────────────────────────
-- By reproducing claim() for all three markets on the holiday, then rolling back:
--   stock_claim_rows=0  crypto_claim_rows=1  us_claim_rows=1  stock_cancel_rows=1
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   drop trigger if exists trg_block_fills_on_market_holiday on public.orders;
--   drop function if exists public.block_fills_on_market_holiday();
--   drop table if exists public.market_holidays;
-- Or, to reopen a single day without removing the mechanism:
--   delete from public.market_holidays where holiday_date = '2026-09-14';

create table if not exists public.market_holidays (
    -- Matches orders.market / holdings.market: 'stock' | 'crypto' | 'us_stock'.
    market       text not null check (market in ('stock', 'crypto', 'us_stock')),
    -- The exchange's local calendar day. For 'stock' that is IST.
    holiday_date date not null,
    name         text,
    created_at   timestamptz not null default now(),
    primary key (market, holiday_date)
);

comment on table public.market_holidays is
    'Days an exchange does not trade. Read by the orders BEFORE UPDATE trigger, which '
    'declines the execution engine''s claim so pending orders stay pending instead of '
    'filling at a stale price. This is the `market_holidays` table the market_hours '
    'helpers have been proposing; adding a date needs no deploy and no app release.';

alter table public.market_holidays enable row level security;

-- Readable by signed-in clients so a future app build can grey out the market
-- honestly. No client writes: this decides whether trades fill.
drop policy if exists market_holidays_read on public.market_holidays;
create policy market_holidays_read on public.market_holidays
    for select to authenticated using (true);

grant select on public.market_holidays to authenticated;
revoke insert, update, delete on public.market_holidays from anon, authenticated;

create or replace function public.block_fills_on_market_holiday()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
    -- Only the execution engine's claim step. Everything else — cancelling,
    -- failing, the post-fill write — passes through untouched.
    if OLD.status <> 'pending' or NEW.status <> 'executing' then
        return NEW;
    end if;
    -- Indian equities and F&O only.
    if NEW.market <> 'stock' then
        return NEW;
    end if;

    if exists (
        select 1 from public.market_holidays h
         where h.market = 'stock'
           and h.holiday_date = (now() at time zone 'Asia/Kolkata')::date
    ) then
        -- NULL cancels the UPDATE silently. The engine's claim() sees zero rows,
        -- reports skipped: "claim_lost", and continues — before any money moves.
        return null;
    end if;

    return NEW;
end;
$$;

drop trigger if exists trg_block_fills_on_market_holiday on public.orders;
create trigger trg_block_fills_on_market_holiday
    before update on public.orders
    for each row execute function public.block_fills_on_market_holiday();

insert into public.market_holidays (market, holiday_date, name)
values ('stock', '2026-09-14', 'Ganesh Chaturthi')
on conflict (market, holiday_date) do nothing;

do $$
begin
    if not exists (select 1 from public.market_holidays
                    where market='stock' and holiday_date='2026-09-14') then
        raise exception 'the holiday row was not inserted';
    end if;
    if not exists (select 1 from pg_trigger
                    where tgname='trg_block_fills_on_market_holiday'
                      and not tgisinternal) then
        raise exception 'the fill-blocking trigger is missing';
    end if;
    -- Crypto and US must not have been closed by accident.
    if exists (select 1 from public.market_holidays
                where market in ('crypto','us_stock')) then
        raise exception 'a holiday was added for crypto or US stocks';
    end if;
end $$;
