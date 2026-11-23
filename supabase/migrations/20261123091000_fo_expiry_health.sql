-- Daily guard that F&O expiries keep matching the exchange.
--
-- Expiry dates are only as good as the daily contract-list sync. It failing
-- silently (Fyers down, a CSV format change, BSE file missing) is how the app
-- ends up on fallback dates again, so every sync run is now logged and a check
-- after the morning sync alerts admins in-app (notifications -> push) when:
--   * no successful sync-instruments run in the last 30 hours (weekdays),
--   * NIFTY or SENSEX has no weekly option expiring in the next 8 days,
--   * an offered index has no live futures/options in the next 40 days,
--   * the sync's cross-check found exchange dates that differ from the
--     fallback calendar (holiday list or exchange rule changed),
--   * an expired position is still unsettled a day after expiry.

create table if not exists public.fo_sync_runs (
  id          bigserial primary key,
  source      text not null,
  run_at      timestamptz not null default now(),
  ok          boolean not null,
  nse_fo_rows integer,
  bse_fo_rows integer,
  warnings    jsonb not null default '[]'::jsonb,
  error       text
);

alter table public.fo_sync_runs enable row level security;
-- No policies: written by the service role (edge function), read by admins via
-- the SECURITY DEFINER check below.

create index if not exists fo_sync_runs_source_run_at_idx
  on public.fo_sync_runs (source, run_at desc);

create or replace function public.check_fo_expiry_health(p_notify boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_problems text[] := '{}';
  v_last     public.fo_sync_runs%rowtype;
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

  if v_ist_dow between 1 and 5 and (v_last.id is null or v_last.run_at < now() - interval '30 hours') then
    v_problems := v_problems || format('No successful contract-list sync since %s',
      coalesce(to_char(v_last.run_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI IST'), 'ever'));
  end if;

  if v_last.id is not null and jsonb_array_length(v_last.warnings) > 0 then
    v_problems := v_problems || ('Sync cross-check: ' ||
      (select string_agg(w, '; ') from jsonb_array_elements_text(v_last.warnings) w));
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

-- 04:15 UTC = 09:45 IST, after the 03:20 UTC sync and before most users trade.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fo-expiry-health') then
    perform cron.unschedule('fo-expiry-health');
  end if;
  perform cron.schedule('fo-expiry-health', '15 4 * * 1-5', 'select public.check_fo_expiry_health();');
end $$;
