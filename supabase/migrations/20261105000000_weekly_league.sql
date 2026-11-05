-- Weekly League: one ranking used by the League screen and by the weekly prizes.
--
-- WHAT CHANGED
-- The League tab read the `leaderboard` view: all-time realised P&L in rupees,
-- so the board was won by whoever had traded longest with the most cash, never
-- reset, and had no notion of "this week". award_weekly_podium() ranked a week
-- by rupees too, ran at Sunday 00:30 IST (missing Sunday's crypto closes), and
-- paid only the top 3.
--
-- NOW
--   * league_board(scope) ranks by realised RETURN %: sum(realised P&L) divided by
--     the cost basis of the positions those trades closed. Rupees reward the
--     biggest wallet; return rewards skill, so a new account can win week one.
--   * A player needs at least 2 closing trades in the window to be ranked, so
--     one lucky trade cannot top the table.
--   * Scopes: 'week' (Mon 00:00 to Mon 00:00 IST), 'all' (all time) and
--     'friends' (week, limited to you, who you referred and who referred you).
--   * The caller's own row is always returned, ranked or not, so "Your position"
--     never goes blank.
--   * award_weekly_podium() uses the same ranking, pays ranks 1-10 (podium
--     rewards plus a new league_top10 reward for 4-10), and runs Monday 00:05
--     IST for the week that just closed.
--
-- Admin and owner accounts stay excluded, the same list as the leaderboard view
-- (grep 'pawan.2u2@gmail.com' for every copy).

-- ── Ranking ─────────────────────────────────────────────────────────────────

create or replace function public.league_week_start(p_at timestamptz default now())
returns timestamptz
language sql
immutable
as $$
  -- Monday 00:00 IST of the ISO week containing p_at.
  select (date_trunc('week', p_at at time zone 'Asia/Kolkata')) at time zone 'Asia/Kolkata';
$$;

create or replace function public.league_board(p_scope text default 'week', p_limit integer default 50)
returns table (
  rank integer,
  user_id uuid,
  name text,
  plan text,
  pnl numeric,
  pnl_pct numeric,
  trades integer,
  qualified boolean,
  is_me boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (
    select auth.uid() as id
  ),
  window_bounds as (
    select case when p_scope = 'all' then '-infinity'::timestamptz else public.league_week_start() end as from_at,
           case when p_scope = 'all' then 'infinity'::timestamptz else public.league_week_start() + interval '7 days' end as to_at
  ),
  players as (
    select p.id, p.name, p.plan
      from public.profiles p
     where coalesce(p.is_admin, false) = false
       and coalesce(p.email, '') not in ('pawan.2u2@gmail.com', 'triloks34@gmail.com',
                                         'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com')
       and (p_scope <> 'friends'
            or p.id = (select id from me)
            or p.referred_by = (select id from me)
            or p.id = (select referred_by from public.profiles where id = (select id from me)))
  ),
  closes as (
    -- A closing fill carries realised P&L. Its cost basis is proceeds minus P&L
    -- for a sell (closing a long) and cost plus P&L for a buy (covering a short).
    select o.user_id,
           sum(o.realized_pnl) as pnl,
           sum(case when o.side = 'sell' then o.total - o.realized_pnl else o.total + o.realized_pnl end) as basis,
           count(*) as trades
      from public.orders o, window_bounds w
     where o.status = 'executed'
       and o.realized_pnl <> 0
       and coalesce(o.executed_at, o.created_at) >= w.from_at
       and coalesce(o.executed_at, o.created_at) < w.to_at
     group by o.user_id
  ),
  scored as (
    select pl.id as user_id, pl.name, pl.plan,
           coalesce(c.pnl, 0) as pnl,
           case when coalesce(c.basis, 0) > 0 then round(c.pnl / c.basis * 100, 2) else 0 end as pnl_pct,
           coalesce(c.trades, 0)::integer as trades,
           coalesce(c.trades, 0) >= 2 as qualified
      from players pl
      left join closes c on c.user_id = pl.id
     where c.user_id is not null or pl.id = (select id from me)
  ),
  ranked as (
    select s.*,
           case when s.qualified
                then (row_number() over (partition by s.qualified order by s.pnl_pct desc, s.pnl desc, s.user_id))::integer
           end as rank
      from scored s
  )
  select r.rank, r.user_id, r.name, r.plan, r.pnl, r.pnl_pct, r.trades, r.qualified,
         r.user_id = (select id from me) as is_me
    from ranked r
   where (r.qualified and r.rank <= greatest(p_limit, 1)) or r.user_id = (select id from me)
   order by r.rank nulls last;
$$;

comment on function public.league_board(text, integer) is
  'Weekly League ranking: realised return % over closing trades, min 2 closes to rank. '
  'p_scope: week | all | friends. Always includes the caller''s own row. Used by the '
  'League screen and award_weekly_podium(); keep the owner exclusion in step with the '
  'leaderboard view.';

revoke all on function public.league_board(text, integer) from public;
grant execute on function public.league_board(text, integer) to authenticated;

-- ── Prizes ──────────────────────────────────────────────────────────────────

insert into public.challenges (key, title, description, category, reward_amount, xp, repeat_limit, sort_order, is_active)
values ('league_top10', 'Weekly Top 10', 'Finished the Weekly League in the top 10', 'social', 500, 100, null,
        (select coalesce(max(sort_order), 0) + 1 from public.challenges), true)
on conflict (key) do nothing;

create or replace function public.award_weekly_podium(p_week text default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  -- Runs Monday 00:05 IST, so "yesterday" is the week that just closed.
  v_ref     timestamptz := case
                             when p_week is null then now() - interval '1 day'
                             else to_date(p_week, 'IYYY-"W"IW')::timestamp at time zone 'Asia/Kolkata' + interval '12 hours'
                           end;
  v_week    text := to_char(v_ref at time zone 'Asia/Kolkata', 'IYYY-"W"IW');
  v_from    timestamptz := public.league_week_start(v_ref);
  v_granted integer := 0;
  v_row     record;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'award_weekly_podium is admin/service-role only';
  end if;

  for v_row in
    with closes as (
      select o.user_id,
             sum(o.realized_pnl) as pnl,
             sum(case when o.side = 'sell' then o.total - o.realized_pnl else o.total + o.realized_pnl end) as basis,
             count(*) as trades
        from public.orders o
        join public.profiles p on p.id = o.user_id
       where o.status = 'executed'
         and o.realized_pnl <> 0
         and coalesce(o.executed_at, o.created_at) >= v_from
         and coalesce(o.executed_at, o.created_at) < v_from + interval '7 days'
         and coalesce(p.is_admin, false) = false
         and coalesce(p.email, '') not in ('pawan.2u2@gmail.com', 'triloks34@gmail.com',
                                           'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com')
       group by o.user_id
      having count(*) >= 2 and sum(o.realized_pnl) > 0
    )
    select user_id,
           row_number() over (order by pnl / nullif(basis, 0) desc nulls last, pnl desc, user_id) as rank
      from closes
     order by rank
     limit 10
  loop
    if public.grant_challenge(v_row.user_id,
                              case when v_row.rank <= 3 then 'podium_' || v_row.rank else 'league_top10' end,
                              v_week) then
      v_granted := v_granted + 1;
    end if;
  end loop;

  return v_granted;
end;
$$;
revoke all on function public.award_weekly_podium(text) from public;

-- Monday 00:05 IST = Sunday 18:35 UTC.
select cron.unschedule('award-weekly-podium')
 where exists (select 1 from cron.job where jobname = 'award-weekly-podium');
select cron.schedule('award-weekly-podium', '35 18 * * 0', $cron$ select public.award_weekly_podium(); $cron$);
