-- Schedules price-feed and tidies cron history.
--
-- price-feed       every minute; each run loops ~58s fetching every 3s and
--                  pushing changed prices every 5s (tick_ms / broadcast_ms in the
--                  URL are the knobs). Uses pg_net (async) so the cron worker is
--                  not held while the function runs. The key is copied from the
--                  existing refresh-quotes job, so no key lives in this repo.
-- refresh-quotes   unchanged schedule; the function now only refreshes rows the
--                  fast feed left older than 30s (safety net).
-- cron-history-cleanup  daily; pg_cron never prunes cron.job_run_details, and a
--                  per-minute job adds 1,440 rows a day.
--
-- Reversible: select cron.unschedule('price-feed');
--             select cron.unschedule('cron-history-cleanup');

do $$
declare
  v_key text;
begin
  select substring(command from 'Bearer ([A-Za-z0-9_\-\.]+)')
    into v_key
    from cron.job where jobname = 'refresh-quotes';
  if v_key is null then
    raise exception 'refresh-quotes job (source of the API key) not found; schedule price-feed by hand';
  end if;

  perform cron.schedule(
    'price-feed',
    '* * * * *',
    format($cmd$
      select net.http_post(
        url := 'https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/price-feed?tick_ms=3000&broadcast_ms=5000',
        headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'apikey', %L, 'Content-Type', 'application/json'),
        body := '{}'::jsonb,
        timeout_milliseconds := 5000
      );
    $cmd$, v_key, v_key)
  );
end $$;

select cron.schedule(
  'cron-history-cleanup',
  '15 21 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '3 days' $$
);
