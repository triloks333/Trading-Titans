-- Expired F&O contracts stayed visible and orderable in the app forever.
--
-- `instruments` is append-mostly: `sync-instruments` upserts whatever the Fyers
-- CSV lists each morning and never removes anything, so every contract that has
-- ever existed is still in the table. All 117,247 already-expired FUTURE/OPTION
-- rows were still flagged `tradeable = true` (641 futures + 116,606 options,
-- oldest expiry 2026-06-09), and `market-search` filters on exactly that column,
-- so users could search up and place orders on contracts that settled months ago.
--
-- Flag, do not delete. `getLotSize()` in BOTH the engine
-- (supabase/functions/execute-pending-orders) and the Flutter client
-- (app/lib/services/fo_instruments_service.dart) resolves a contract by symbol
-- WITHOUT consulting `tradeable`. Deleting the rows would strand any open
-- position on an expired contract with the fallback lot size of 1 and settle it
-- at a fraction of its real value. Deactivating hides them from the read paths
-- that matter while leaving settlement able to price what it already holds.

create or replace function public.deactivate_expired_instruments()
returns integer
language plpgsql
set search_path = public
as $$
declare
  affected integer;
begin
  update public.instruments
     set tradeable = false
   where instrument_type in ('FUTURE', 'OPTION')
     and expiry_date is not null
     and expiry_date::date < current_date
     and tradeable is true;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

comment on function public.deactivate_expired_instruments() is
  'Marks FUTURE/OPTION rows whose expiry has passed as not tradeable. Idempotent: safe to run any number of times per day.';

-- Maintenance only; nothing in the app calls this.
revoke all on function public.deactivate_expired_instruments() from anon, authenticated;

-- Clear the whole existing backlog in one shot.
select public.deactivate_expired_instruments();

-- Daily sweep at 18:30 UTC (00:00 IST). Deliberately after the 14:30 UTC
-- `expire_fo_positions_post_market` settlement run, so a contract expiring today
-- is settled before it is hidden.
--
-- Contracts stay tradeable THROUGH their expiry day: the predicate is
-- `< current_date`, not `<=`. An expiry-day contract is a real, tradeable
-- contract right up to the close, and hiding it early would break the most
-- actively traded series on the board.
select cron.unschedule('deactivate-expired-instruments')
where exists (select 1 from cron.job where jobname = 'deactivate-expired-instruments');

select cron.schedule(
  'deactivate-expired-instruments',
  '30 18 * * *',
  $$select public.deactivate_expired_instruments();$$
);
