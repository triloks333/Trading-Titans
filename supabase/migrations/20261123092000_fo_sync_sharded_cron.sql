-- Daily contract-list sync, split into parts that each fit an edge worker.
--
-- The old cron made one `http()` call with a 5 s client timeout, and the one
-- function run tried to parse and upsert all ~110k rows; it was killed for CPU
-- time ("CPU Time exceeded", 546 WORKER_RESOURCE_LIMIT), so the contract list,
-- which is the source of truth for F&O expiries, could silently go stale.
--
-- Now: one part per minute from 03:10 to 03:19 UTC (equity, BSE F&O, then 8
-- NSE F&O shards) via pg_net (async, no client timeout, no key needed:
-- verify_jwt is off for this function). They must not run at the same time:
-- concurrent requests share one worker and its CPU budget, and fired together
-- most of them were killed. At 03:25 UTC `part=check` confirms every part
-- logged success, cross-checks expiries and writes the `sync-instruments` row
-- that check_fo_expiry_health() (04:15 UTC) reads.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'fyers-instrument-sync') then
    perform cron.unschedule('fyers-instrument-sync');
  end if;
  if exists (select 1 from cron.job where jobname = 'fyers-instrument-sync-check') then
    perform cron.unschedule('fyers-instrument-sync-check');
  end if;

  perform cron.schedule('fyers-instrument-sync', '10-19 3 * * 1-5', $job$
    select net.http_post(
      url := 'https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/sync-instruments?' ||
        (array['part=equity', 'part=bse',
          'part=nse&shard=0', 'part=nse&shard=1', 'part=nse&shard=2', 'part=nse&shard=3',
          'part=nse&shard=4', 'part=nse&shard=5', 'part=nse&shard=6', 'part=nse&shard=7']
        )[extract(minute from now() at time zone 'UTC')::int - 9],
      body := '{}'::jsonb,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      timeout_milliseconds := 300000);
  $job$);

  perform cron.schedule('fyers-instrument-sync-check', '25 3 * * 1-5', $job$
    select net.http_post(
      url := 'https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/sync-instruments?part=check',
      body := '{}'::jsonb,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      timeout_milliseconds := 120000);
  $job$);
end $$;

-- The health check also alerts when the latest check run itself failed (a part
-- did not finish), instead of waiting 30 hours for "no successful sync".
create or replace function public.check_fo_expiry_health(p_notify boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_problems text[] := '{}';
  v_last     public.fo_sync_runs%rowtype;
  v_latest   public.fo_sync_runs%rowtype;
  v_und      text;
  v_ist_dow  int := extract(isodow from (now() at time zone 'Asia/Kolkata'));
  v_stuck    int;
  v_title    text := 'F&O expiry health check failed';
  v_body     text;
begin
  select * into v_last
    from public.fo_sync_runs
   where source = 'sync-instruments' and ok
   order by run_at desc limit 1;

  select * into v_latest
    from public.fo_sync_runs
   where source = 'sync-instruments'
   order by run_at desc limit 1;

  if v_ist_dow between 1 and 5 and (v_last.id is null or v_last.run_at < now() - interval '30 hours') then
    v_problems := v_problems || format('No successful contract-list sync since %s',
      coalesce(to_char(v_last.run_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI IST'), 'ever'));
  end if;

  if v_latest.id is not null and not v_latest.ok then
    v_problems := v_problems || format('Latest contract-list sync failed: %s', coalesce(v_latest.error, 'unknown'));
  end if;

  if v_latest.id is not null and jsonb_array_length(v_latest.warnings) > 0 then
    v_problems := v_problems || ('Sync check: ' ||
      (select string_agg(w, '; ') from jsonb_array_elements_text(v_latest.warnings) w));
  end if;

  foreach v_und in array array['NSE:NIFTY', 'BSE:SENSEX'] loop
    if not exists (
      select 1 from public.instruments i
       where i.instrument_type = 'OPTION'
         and i.symbol ~ ('^' || v_und || '[0-9]')
         and i.expiry_date::date between current_date and current_date + 8
    ) then
      v_problems := v_problems || format('%s has no option expiry in the next 8 days', v_und);
    end if;
  end loop;

  foreach v_und in array array['NSE:NIFTY', 'NSE:BANKNIFTY', 'NSE:FINNIFTY', 'NSE:MIDCPNIFTY', 'BSE:SENSEX'] loop
    if not exists (
      select 1 from public.instruments i
       where i.instrument_type in ('OPTION', 'FUTURE')
         and i.symbol ~ ('^' || v_und || '[0-9]')
         and i.expiry_date::date between current_date and current_date + 40
    ) then
      v_problems := v_problems || format('%s has no contract expiring in the next 40 days', v_und);
    end if;
  end loop;

  select count(*) into v_stuck
    from public.fo_positions
   where not is_settled
     and expiry_date < current_date - 1;
  if v_stuck > 0 then
    v_problems := v_problems || format('%s expired position(s) still unsettled', v_stuck);
  end if;

  if p_notify and cardinality(v_problems) > 0 then
    v_body := array_to_string(v_problems, E'\n');
    -- One alert per admin per IST day.
    insert into public.notifications (user_id, title, body, action_type, action_data)
    select p.id, v_title, left(v_body, 1000), 'ops_alert',
           jsonb_build_object('problems', to_jsonb(v_problems))
      from public.profiles p
     where coalesce(p.is_admin, false)
       and not exists (
         select 1 from public.notifications n
          where n.user_id = p.id
            and n.title = v_title
            and (n.created_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
       );
  end if;

  return jsonb_build_object('ok', cardinality(v_problems) = 0, 'problems', to_jsonb(v_problems),
                            'last_sync', v_last.run_at);
end;
$$;

revoke all on function public.check_fo_expiry_health(boolean) from public, anon, authenticated;
