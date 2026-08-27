-- Widen the quote-refresh and pending-order execution windows to 24/7.
--
-- Both jobs were scheduled '* 3-10 * * 1-5' — the IST equity session only. Two
-- consequences, both observed in production:
--
--   1. `quotes_cache` froze outside that window. Every `us_stock` row was
--      129-217 hours stale, because nothing refreshes quotes during the US
--      session (13-21 UTC). `execute-pending-orders` evaluates limit triggers
--      against that table, so US limit orders were being priced off multi-day-old
--      quotes. Crypto has the same hole: it trades 24/7 but its quotes were only
--      refreshed during Indian market hours.
--
--   2. Crypto pending orders had a ~6 hour execution blackout each day (21-03
--      UTC), where neither this job nor 'execute-pending-us-orders' (*/5 13-21)
--      was running to fill them.
--
-- Widening is safe and cheap because BOTH functions already gate per-market
-- internally and skip closed markets:
--   - refresh-quotes: `refreshOnce()` returns early per symbol via
--     `isMarketOpen(u.market, stockOpen, usOpen)`, so outside equity hours it
--     only fetches the handful of crypto symbols. Upstream API calls scale with
--     the number of OPEN markets, not with the cron frequency.
--   - execute-pending-orders: the per-order loop skips with
--     `skipped: "market_closed"` unless `isMarketOpen(market)`.
-- So the extra ticks are near-no-ops rather than added quote-fetch load.
--
-- This MUST land before the engine's stale-price guard. Adding a freshness check
-- while the cache is only refreshed 3-10 UTC would block every US and crypto
-- limit order outright.
--
-- Uses cron.alter_job (pg_cron >= 1.4; this project runs 1.6.4) to change ONLY
-- the schedule. The jobs were created by hand and their commands embed the anon
-- key inline, so rebuilding the command here would mean committing a credential
-- to the repo. alter_job leaves the command, database and username untouched.
--
-- Idempotent: re-running sets the same schedule. Reversible by calling
-- cron.alter_job with the original '* 3-10 * * 1-5'.
do $$
declare
  v_job record;
  v_target text := '* * * * *';
begin
  for v_job in
    select jobid, jobname, schedule
    from cron.job
    where jobname in ('refresh-quotes', 'execute-pending-orders')
  loop
    if v_job.schedule = v_target then
      raise notice 'cron job % already on %, leaving alone', v_job.jobname, v_target;
    else
      perform cron.alter_job(job_id := v_job.jobid, schedule := v_target);
      raise notice 'cron job % rescheduled from % to %', v_job.jobname, v_job.schedule, v_target;
    end if;
  end loop;

  -- Fail loudly rather than silently leaving the cache frozen: if neither job
  -- exists the staleness guard that follows would have nothing keeping it fed.
  if not exists (
    select 1 from cron.job
    where jobname in ('refresh-quotes', 'execute-pending-orders')
  ) then
    raise exception
      'Neither refresh-quotes nor execute-pending-orders is scheduled; cannot widen windows.';
  end if;
end $$;
