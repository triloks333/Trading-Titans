-- Community win rate per symbol (aggregate only) and honest inactivity win-back.

-- ── 1. Today's community win rate per symbol ────────────────────────────────
-- Counts only; a symbol appears once 5+ trades closed on it today (IST), so no
-- single user's result can be read back.
create or replace function public.intel_community_win_rates()
returns jsonb
language sql security definer set search_path = public, pg_temp stable
as $$
  select coalesce(jsonb_object_agg(sym, jsonb_build_object('wins', wins, 'total', total)), '{}'::jsonb)
  from (
    select props->>'sym' as sym,
           count(*) filter (where (props->>'pnl')::numeric >= 0) as wins,
           count(*) as total
    from public.intel_events
    where name = 'trade_closed'
      and props ? 'sym'
      and created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
    group by 1
    having count(*) >= 5
  ) t;
$$;
revoke all on function public.intel_community_win_rates() from public, anon;
grant execute on function public.intel_community_win_rates() to authenticated;

-- ── 2. Win-back after 3 and 7 days without opening the app ──────────────────
-- One in-app notification per lapse per tier (the notifications trigger also
-- pushes it, honouring notification preferences). Wording is literally true.
-- Every send is logged to intel_reaction_firings.
create or replace function public.intel_send_winback()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  sent integer := 0;
  r record;
begin
  for r in
    with last_seen as (
      select user_id, max(created_at) as at from public.intel_events group by user_id
    )
    select l.user_id, l.at,
           case when l.at < now() - interval '7 days' then 'winback_7d' else 'winback_3d' end as tier
    from last_seen l
    where l.at < now() - interval '3 days'
      and l.at > now() - interval '30 days'
  loop
    -- Already sent this tier since they were last active.
    if exists (select 1 from public.intel_reaction_firings f
               where f.user_id = r.user_id and f.reaction = r.tier and f.created_at > r.at) then
      continue;
    end if;
    insert into public.notifications (user_id, title, body, action_type)
    values (
      r.user_id,
      case r.tier when 'winback_7d' then 'Your demo account is still here'
                  else 'It''s been 3 days' end,
      case r.tier when 'winback_7d' then 'It''s been a week. Your demo cash, holdings and trade history are where you left them.'
                  else 'Markets have moved since you last opened Trading Titans. Your demo account is where you left it.' end,
      'general'
    );
    insert into public.intel_reaction_firings (user_id, reaction, delivered, reason, props)
    values (r.user_id, r.tier, true, 'inactive', jsonb_build_object('last_seen', r.at));
    sent := sent + 1;
  end loop;
  return sent;
end $$;
revoke all on function public.intel_send_winback() from public, anon, authenticated;

-- Daily at 18:00 IST.
select cron.unschedule('intel-winback-daily') where exists (select 1 from cron.job where jobname = 'intel-winback-daily');
select cron.schedule('intel-winback-daily', '30 12 * * *', $$select public.intel_send_winback()$$);
