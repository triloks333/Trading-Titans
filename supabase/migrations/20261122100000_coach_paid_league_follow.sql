-- Paid features, part 2: weekly coach report, Pro League, paid-only challenges and
-- following top traders.
--
-- Depends on 20261122090000_plan_limits_and_week_pass.sql (limits_enforced()).
-- Every "paid only" check below goes through limits_enforced(): while
-- app_flags.monetization_enabled is off, nothing is locked.
--
-- WHAT IT ADDS
--   * Weekly coach report (Pro and Titan): coach_report_data() turns a user's
--     executed orders into stats and up to four plain-English tips using fixed
--     rules (no AI, no paid service). A Sunday 18:00 IST cron stores one report
--     per paid user who traded that week and sends a push through the existing
--     notifications trigger. my_coach_report() serves it to the app; free users
--     get the stats and the tip titles only, so they can see what they're missing.
--   * Pro League: league_board('paid') ranks only Pro and Titan members. The top 3
--     win demo cash and XP each Monday. No real-money prizes.
--   * Paid-only challenges: challenges.min_tier. grant_challenge() refuses a paid
--     challenge to a free account. Two weekly ones: trade on 5 days, and close a
--     green week with at least 5 closing trades.
--   * Follow top traders (Pro): a trader opts in with set_share_trades(true); Pro
--     members can follow up to 20 of them, see their recent trades (no quantities)
--     and get at most one push per trader per hour. Learning only, not advice.
--
-- Rollback (reverse order):
--   select cron.unschedule('weekly-coach-reports'); select cron.unschedule('award-paid-weekly');
--   drop trigger if exists trg_notify_followers on public.orders;
--   drop function if exists public.notify_followers_on_trade(), public.followed_feed(int),
--     public.followed_traders(), public.trader_profile(uuid), public.follow_trader(uuid),
--     public.unfollow_trader(uuid), public.set_share_trades(boolean),
--     public.award_paid_weekly(text), public.send_weekly_coach_reports(),
--     public.my_coach_report(), public.coach_report_data(uuid, timestamptz, timestamptz),
--     public.tier_rank(text);
--   drop table if exists public.trader_follows, public.coach_reports;
--   alter table public.profiles drop column if exists share_trades;
--   then restore league_board, grant_challenge and get_my_challenges from
--   20261105000000_weekly_league.sql / prod and drop challenges.min_tier.

-- ── Helpers ─────────────────────────────────────────────────────────────────

create or replace function public.tier_rank(p_tier text)
returns integer
language sql
immutable
as $$
  select case p_tier when 'titan' then 2 when 'pro' then 1 else 0 end;
$$;

-- ── Weekly coach report ─────────────────────────────────────────────────────

create table if not exists public.coach_reports (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  week       text not null,               -- ISO week in IST, e.g. 2026-W47
  data       jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, week)
);
alter table public.coach_reports enable row level security;
drop policy if exists coach_reports_own_read on public.coach_reports;
create policy coach_reports_own_read on public.coach_reports
  for select to authenticated using (user_id = auth.uid());

create or replace function public.coach_report_data(p_user uuid, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  s          record;
  v_best     record;
  v_worst    record;
  v_top      record;
  v_max_day  integer := 0;
  v_revenge  integer := 0;
  v_bell     integer := 0;
  v_tips     jsonb := '[]'::jsonb;
  v_win_rate numeric := 0;
begin
  select count(*)                                                     as orders,
         count(*) filter (where o.realized_pnl <> 0)                  as closes,
         count(*) filter (where o.realized_pnl > 0)                   as wins,
         count(*) filter (where o.realized_pnl < 0)                   as losses,
         coalesce(sum(o.realized_pnl), 0)                             as pnl,
         coalesce(avg(o.realized_pnl) filter (where o.realized_pnl > 0), 0)  as avg_win,
         coalesce(avg(-o.realized_pnl) filter (where o.realized_pnl < 0), 0) as avg_loss,
         coalesce(sum(o.total_charges), 0)                            as charges,
         count(*) filter (where o.instrument_type in ('OPTION', 'FUTURE')) as fo_orders,
         coalesce(sum(o.realized_pnl) filter (where o.instrument_type in ('OPTION', 'FUTURE')), 0) as fo_pnl,
         count(distinct (coalesce(o.executed_at, o.created_at) at time zone 'Asia/Kolkata')::date) as days
    into s
    from public.orders o
   where o.user_id = p_user
     and o.status = 'executed'
     and coalesce(o.executed_at, o.created_at) >= p_from
     and coalesce(o.executed_at, o.created_at) < p_to;

  if s.closes > 0 then
    v_win_rate := round(s.wins::numeric / s.closes * 100, 0);
  end if;

  select o.symbol, o.realized_pnl as pnl into v_best
    from public.orders o
   where o.user_id = p_user and o.status = 'executed' and o.realized_pnl > 0
     and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
   order by o.realized_pnl desc limit 1;

  select o.symbol, o.realized_pnl as pnl into v_worst
    from public.orders o
   where o.user_id = p_user and o.status = 'executed' and o.realized_pnl < 0
     and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
   order by o.realized_pnl asc limit 1;

  select o.symbol, count(*) as n into v_top
    from public.orders o
   where o.user_id = p_user and o.status = 'executed'
     and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
   group by o.symbol order by count(*) desc limit 1;

  select coalesce(max(n), 0) into v_max_day from (
    select count(*) as n
      from public.orders o
     where o.user_id = p_user and o.status = 'executed'
       and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
     group by (coalesce(o.executed_at, o.created_at) at time zone 'Asia/Kolkata')::date
  ) d;

  -- New positions opened within 10 minutes of a losing close.
  select count(*) into v_revenge
    from public.orders o
   where o.user_id = p_user and o.status = 'executed' and not coalesce(o.is_exit, false)
     and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
     and exists (
       select 1 from public.orders l
        where l.user_id = p_user and l.status = 'executed' and l.realized_pnl < 0
          and coalesce(l.executed_at, l.created_at) <  coalesce(o.executed_at, o.created_at)
          and coalesce(l.executed_at, l.created_at) >= coalesce(o.executed_at, o.created_at) - interval '10 minutes');

  -- Losing closes in the first 15 minutes of the Indian session.
  select count(*) into v_bell
    from public.orders o
   where o.user_id = p_user and o.status = 'executed' and o.realized_pnl < 0
     and o.market in ('stock', 'fo', 'index')
     and coalesce(o.executed_at, o.created_at) >= p_from and coalesce(o.executed_at, o.created_at) < p_to
     and (coalesce(o.executed_at, o.created_at) at time zone 'Asia/Kolkata')::time between time '09:15' and time '09:30';

  -- Rules, most important first. Severity: warn (fix this), tip (try this), good.
  if s.losses >= 2 and s.wins > 0 and s.avg_loss > 1.5 * s.avg_win then
    v_tips := v_tips || jsonb_build_object('key', 'big_losses', 'severity', 'warn',
      'title', 'Your losses are bigger than your wins',
      'body', format('Your average loss was ₹%s but your average win only ₹%s. Decide your exit before you enter and place a stop-loss, so one bad trade can''t wipe out several good ones.',
                     to_char(round(s.avg_loss), 'FM99,99,99,990'), to_char(round(s.avg_win), 'FM99,99,99,990')));
  end if;

  if s.fo_orders > 0 and s.fo_pnl < 0 and s.fo_pnl < s.pnl then
    v_tips := v_tips || jsonb_build_object('key', 'fo_drag', 'severity', 'warn',
      'title', 'F&O pulled your week down',
      'body', format('Futures and options lost ₹%s this week. Try smaller size, or a defined-risk spread in the strategy builder, until you have a few green weeks in a row.',
                     to_char(round(-s.fo_pnl), 'FM99,99,99,990')));
  end if;

  if v_revenge >= 2 then
    v_tips := v_tips || jsonb_build_object('key', 'revenge', 'severity', 'warn',
      'title', 'You jumped back in right after losses',
      'body', format('%s times you opened a new trade within 10 minutes of a loss. Take a short break after a losing trade; quick comeback trades are usually the worst ones.', v_revenge));
  end if;

  if v_max_day >= 15 or s.orders >= 60 then
    v_tips := v_tips || jsonb_build_object('key', 'overtrading', 'severity', 'tip',
      'title', 'You traded a lot',
      'body', format('%s orders this week, up to %s in a single day. Fewer, better-planned trades usually beat many small ones, and charges add up.', s.orders, v_max_day));
  end if;

  if s.pnl > 0 and s.charges > 0.3 * s.pnl then
    v_tips := v_tips || jsonb_build_object('key', 'charges', 'severity', 'tip',
      'title', 'Charges ate into your profit',
      'body', format('You paid ₹%s in charges against ₹%s of profit. Holding winners a little longer or trading less often keeps more of it.',
                     to_char(round(s.charges), 'FM99,99,99,990'), to_char(round(s.pnl), 'FM99,99,99,990')));
  end if;

  if v_bell >= 2 and s.losses > 0 and v_bell * 2 >= s.losses then
    v_tips := v_tips || jsonb_build_object('key', 'opening_bell', 'severity', 'tip',
      'title', 'The first 15 minutes hurt you',
      'body', format('%s of your %s losing trades closed between 9:15 and 9:30. Prices swing hardest at the open; waiting 15 minutes for things to settle can help.', v_bell, s.losses));
  end if;

  if v_top.n is not null and s.orders >= 6 and v_top.n * 2 >= s.orders then
    v_tips := v_tips || jsonb_build_object('key', 'concentration', 'severity', 'tip',
      'title', format('Most of your trades were in %s', v_top.symbol),
      'body', format('%s of %s orders were in %s. Knowing one stock well is fine, but spreading across a few lowers the damage from a single bad move.', v_top.n, s.orders, v_top.symbol));
  end if;

  if s.closes >= 3 and v_win_rate >= 60 and s.pnl > 0 then
    v_tips := v_tips || jsonb_build_object('key', 'good_week', 'severity', 'good',
      'title', 'Good week, keep the same process',
      'body', format('You won %s%% of your closing trades and finished ₹%s up. Note what you did differently this week and repeat it.',
                     v_win_rate, to_char(round(s.pnl), 'FM99,99,99,990')));
  end if;

  if jsonb_array_length(v_tips) = 0 then
    v_tips := jsonb_build_array(jsonb_build_object('key', 'not_enough', 'severity', 'tip',
      'title', case when s.closes < 2 then 'Close a few more trades for a full report' else 'Steady week' end,
      'body', case when s.closes < 2
                   then 'The coach needs at least two closed trades to spot patterns. Trade as you normally would and next week''s report will have more to say.'
                   else 'Nothing stood out as a problem this week. Keep sizing sensibly and sticking to your plan.' end));
  end if;

  return jsonb_build_object(
    'from', p_from, 'to', p_to,
    'orders', s.orders, 'closes', s.closes, 'wins', s.wins, 'losses', s.losses,
    'win_rate', v_win_rate, 'pnl', round(s.pnl, 2),
    'avg_win', round(s.avg_win, 2), 'avg_loss', round(s.avg_loss, 2),
    'charges', round(s.charges, 2), 'fo_pnl', round(s.fo_pnl, 2), 'days', s.days,
    'best', case when v_best.symbol is null then null else jsonb_build_object('symbol', v_best.symbol, 'pnl', round(v_best.pnl, 2)) end,
    'worst', case when v_worst.symbol is null then null else jsonb_build_object('symbol', v_worst.symbol, 'pnl', round(v_worst.pnl, 2)) end,
    'tips', (select jsonb_agg(t) from (select t from jsonb_array_elements(v_tips) t limit 4) x)
  );
end;
$$;
revoke all on function public.coach_report_data(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- The app's view: the latest stored report for paid users (or a live one for the
-- last 7 days if none yet); for free users a live one with the tip text removed.
create or replace function public.my_coach_report()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid  uuid := auth.uid();
  v_tier text;
  v_full boolean;
  v_rep  jsonb;
  v_week text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  v_tier := public.current_tier(v_uid);
  v_full := not public.limits_enforced() or v_tier in ('pro', 'titan');

  if v_full then
    select r.data, r.week into v_rep, v_week from public.coach_reports r
     where r.user_id = v_uid and r.created_at > now() - interval '8 days'
     order by r.created_at desc limit 1;
  end if;
  if v_rep is null then
    v_rep := public.coach_report_data(v_uid, now() - interval '7 days', now());
  end if;

  if not v_full then
    v_rep := (v_rep - 'tips') || jsonb_build_object(
      'tips', (select jsonb_agg(jsonb_build_object('key', t->>'key', 'severity', t->>'severity', 'title', t->>'title', 'body', ''))
                 from jsonb_array_elements(v_rep->'tips') t));
  end if;

  return jsonb_build_object('locked', not v_full, 'tier', v_tier, 'week', v_week, 'report', v_rep);
end;
$$;
revoke all on function public.my_coach_report() from public, anon;
grant execute on function public.my_coach_report() to authenticated;

create or replace function public.send_weekly_coach_reports()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_from timestamptz := public.league_week_start();
  v_to   timestamptz := now();
  v_week text := to_char(now() at time zone 'Asia/Kolkata', 'IYYY-"W"IW');
  v_sent integer := 0;
  v_rep  jsonb;
  v_n    integer;
  r      record;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'send_weekly_coach_reports is admin/service-role only';
  end if;

  for r in
    select distinct o.user_id
      from public.orders o
     where o.status = 'executed'
       and coalesce(o.executed_at, o.created_at) >= v_from
       and coalesce(o.executed_at, o.created_at) < v_to
  loop
    -- Paid members only, even with limits off, so this never pushes to everyone.
    continue when public.current_tier(r.user_id) not in ('pro', 'titan');
    v_rep := public.coach_report_data(r.user_id, v_from, v_to);
    insert into public.coach_reports (user_id, week, data) values (r.user_id, v_week, v_rep)
    on conflict (user_id, week) do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      insert into public.notifications (user_id, title, body, is_read, action_type, action_data)
      values (r.user_id, 'Your weekly coach report is ready 📋',
              coalesce(v_rep->'tips'->0->>'title', 'See what went well and what to fix next week.'),
              false, 'coach_report', jsonb_build_object('week', v_week, 'cta_route', 'coach', 'cta_label', 'Open report'));
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;
revoke all on function public.send_weekly_coach_reports() from public, anon, authenticated;

-- Sunday 18:00 IST = 12:30 UTC.
select cron.unschedule('weekly-coach-reports')
 where exists (select 1 from cron.job where jobname = 'weekly-coach-reports');
select cron.schedule('weekly-coach-reports', '30 12 * * 0', $cron$ select public.send_weekly_coach_reports(); $cron$);

-- ── Paid-only challenges ────────────────────────────────────────────────────

alter table public.challenges add column if not exists min_tier text
  check (min_tier is null or min_tier in ('pro', 'titan'));

insert into public.challenges (key, title, description, category, reward_amount, xp, repeat_limit, sort_order, is_active, min_tier)
values
  ('paid_league_1', 'Pro League champion', 'Finished 1st in the weekly Pro League', 'social', 25000, 300, null,
   (select coalesce(max(sort_order), 0) + 1 from public.challenges), true, 'pro'),
  ('paid_league_2', 'Pro League runner-up', 'Finished 2nd in the weekly Pro League', 'social', 15000, 200, null,
   (select coalesce(max(sort_order), 0) + 2 from public.challenges), true, 'pro'),
  ('paid_league_3', 'Pro League third place', 'Finished 3rd in the weekly Pro League', 'social', 10000, 150, null,
   (select coalesce(max(sort_order), 0) + 3 from public.challenges), true, 'pro'),
  ('pro_week_5_days', 'Five-day trader', 'Traded on 5 different days in one week', 'habit', 5000, 75, null,
   (select coalesce(max(sort_order), 0) + 4 from public.challenges), true, 'pro'),
  ('pro_week_green', 'Green week', 'Closed a week in profit with at least 5 closing trades', 'performance', 7500, 100, null,
   (select coalesce(max(sort_order), 0) + 5 from public.challenges), true, 'pro')
on conflict (key) do update set min_tier = excluded.min_tier;

-- Same as prod, plus the min_tier check.
create or replace function public.grant_challenge(p_user_id uuid, p_key text, p_cycle text default 'once')
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_monthly_cap   constant numeric := 75000;
    v_challenge     public.challenges;
    v_already       integer;
    v_granted_month numeric;
    v_inserted      integer;
begin
    select * into v_challenge from public.challenges
     where key = p_key and is_active;
    if not found then
        return false;
    end if;

    -- Paid-only challenge: refuse a free account while plans are enforced.
    if v_challenge.min_tier is not null and public.limits_enforced()
       and public.tier_rank(public.current_tier(p_user_id)) < public.tier_rank(v_challenge.min_tier) then
        return false;
    end if;

    if v_challenge.repeat_limit is not null then
        select count(*) into v_already from public.user_challenges
         where user_id = p_user_id and challenge_key = p_key;
        if v_already >= v_challenge.repeat_limit then
            return false;
        end if;
    end if;

    select coalesce(sum(reward_amount), 0) into v_granted_month
      from public.user_challenges
     where user_id = p_user_id
       and granted_at >= date_trunc('month', now());
    if v_granted_month + v_challenge.reward_amount > v_monthly_cap then
        return false;
    end if;

    insert into public.user_challenges (user_id, challenge_key, cycle, reward_amount, xp)
    values (p_user_id, p_key, p_cycle, v_challenge.reward_amount, v_challenge.xp)
    on conflict (user_id, challenge_key, cycle) do nothing;

    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then
        return false;
    end if;

    insert into public.rewards (user_id, amount, message, is_claimed)
    values (p_user_id, v_challenge.reward_amount,
            v_challenge.title || ' — ' || v_challenge.description, false);

    insert into public.notifications (user_id, title, body, is_read, action_type)
    values (p_user_id,
            'Challenge complete: ' || v_challenge.title || ' 🏆',
            'You earned ₹' || to_char(v_challenge.reward_amount, 'FM999999999')
              || ' demo cash. Open the app to claim it.',
            false, 'reward');

    update public.profiles
       set total_xp = total_xp + v_challenge.xp
     where id = p_user_id;

    return true;
end;
$$;

-- get_my_challenges gains min_tier and locked, and progress for the weekly paid
-- challenges. The return type changes, so it is dropped and recreated.
drop function if exists public.get_my_challenges();
create function public.get_my_challenges()
returns table (key text, title text, description text, category text, reward_amount numeric, xp integer,
               repeat_limit integer, sort_order integer, times_earned integer, total_earned numeric,
               last_earned_at timestamptz, progress numeric, target numeric, min_tier text, locked boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (
    select p.* from public.profiles p where p.id = auth.uid()
  ),
  tier as (
    select public.tier_rank(public.current_tier(auth.uid())) as r, public.limits_enforced() as enforced
  ),
  stats as (
    select
      (select count(*) from public.orders where user_id = (select id from me) and status = 'executed') as executed,
      (select count(distinct (created_at at time zone 'Asia/Kolkata')::date) from public.orders
        where user_id = (select id from me) and status = 'executed' and created_at >= now() - interval '7 days') as days_7,
      (select count(distinct (created_at at time zone 'Asia/Kolkata')::date) from public.orders
        where user_id = (select id from me) and status = 'executed'
          and (created_at at time zone 'Asia/Kolkata')::time between time '09:15' and time '09:30') as bell_days,
      (select count(distinct market) from public.holdings
        where user_id = (select id from me) and quantity > 0 and market in ('stock', 'us_stock', 'crypto')) as markets,
      (select count(distinct symbol) from public.holdings where user_id = (select id from me) and quantity > 0) as symbols,
      (select count(*) from public.orders
        where user_id = (select id from me) and status = 'executed' and instrument_type in ('OPTION', 'FUTURE')) as fo_orders,
      (select count(*) from public.trade_autopsies where user_id = (select id from me) and pnl < 0) as loss_autopsies,
      (select count(*) from public.price_alerts where user_id = (select id from me) and status = 'triggered') as alerts,
      (select count(*) from public.profiles where referred_by = (select id from me)) as referrals,
      (select count(distinct (coalesce(executed_at, created_at) at time zone 'Asia/Kolkata')::date) from public.orders
        where user_id = (select id from me) and status = 'executed'
          and coalesce(executed_at, created_at) >= public.league_week_start()) as week_days,
      (select count(*) from public.orders
        where user_id = (select id from me) and status = 'executed' and realized_pnl <> 0
          and coalesce(executed_at, created_at) >= public.league_week_start()) as week_closes
  ),
  measures as (
    select k.key, k.progress, k.target
      from me, stats s,
      lateral (values
        ('first_blood',       least(s.executed, 1)::numeric,                 1::numeric),
        ('titan_20',          greatest(me.total_realized_pnl, 0),            0.20 * me.challenge_baseline_capital),
        ('century_club_1l',   greatest(me.total_realized_pnl, 0),            100000::numeric),
        ('century_club_5l',   greatest(me.total_realized_pnl, 0),            500000::numeric),
        ('century_club_10l',  greatest(me.total_realized_pnl, 0),            1000000::numeric),
        ('login_streak_3',    me.longest_login_streak::numeric,              3::numeric),
        ('login_streak_7',    me.longest_login_streak::numeric,              7::numeric),
        ('login_streak_14',   me.longest_login_streak::numeric,              14::numeric),
        ('login_streak_30',   me.longest_login_streak::numeric,              30::numeric),
        ('trader_streak',     s.days_7::numeric,                             5::numeric),
        ('morning_bell',      s.bell_days::numeric,                          3::numeric),
        ('globetrotter',      s.markets::numeric,                            3::numeric),
        ('diversifier',       s.symbols::numeric,                            5::numeric),
        ('derivatives_debut', least(s.fo_orders, 1)::numeric,                1::numeric),
        ('autopsy_analyst',   s.loss_autopsies::numeric,                     5::numeric),
        ('alert_watcher',     s.alerts::numeric,                             3::numeric),
        ('referral_1',        s.referrals::numeric,                          1::numeric),
        ('referral_5',        s.referrals::numeric,                          5::numeric),
        ('referral_10',       s.referrals::numeric,                          10::numeric),
        ('pro_week_5_days',   s.week_days::numeric,                          5::numeric),
        ('pro_week_green',    s.week_closes::numeric,                        5::numeric)
      ) as k(key, progress, target)
  )
  select c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
         c.repeat_limit, c.sort_order,
         coalesce(count(uc.id), 0)::integer as times_earned,
         coalesce(sum(uc.reward_amount), 0)  as total_earned,
         max(uc.granted_at)                  as last_earned_at,
         least(m.progress, m.target)         as progress,
         m.target,
         c.min_tier,
         (c.min_tier is not null and (select enforced from tier)
            and (select r from tier) < public.tier_rank(c.min_tier)) as locked
    from public.challenges c
    left join public.user_challenges uc on uc.challenge_key = c.key and uc.user_id = auth.uid()
    left join measures m on m.key = c.key
   where c.is_active
   group by c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
            c.repeat_limit, c.sort_order, m.progress, m.target, c.min_tier
   order by c.sort_order;
$$;
revoke all on function public.get_my_challenges() from public, anon;
grant execute on function public.get_my_challenges() to authenticated;

-- ── Pro League ──────────────────────────────────────────────────────────────

-- Same as 20261105000000_weekly_league.sql plus scope 'paid' (this week, Pro and
-- Titan members only). Any scope other than 'all' uses the current week.
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
       and (p_scope <> 'paid' or public.current_tier(p.id) in ('pro', 'titan'))
  ),
  closes as (
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

-- Monday: Pro League podium plus the two weekly paid challenges, for the week
-- that just closed. grant_challenge() re-checks the tier at payout time.
create or replace function public.award_paid_weekly(p_week text default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
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
    raise exception 'award_paid_weekly is admin/service-role only';
  end if;

  for v_row in
    with closes as (
      select o.user_id,
             sum(o.realized_pnl) as pnl,
             sum(case when o.side = 'sell' then o.total - o.realized_pnl else o.total + o.realized_pnl end) as basis
        from public.orders o
        join public.profiles p on p.id = o.user_id
       where o.status = 'executed'
         and o.realized_pnl <> 0
         and coalesce(o.executed_at, o.created_at) >= v_from
         and coalesce(o.executed_at, o.created_at) < v_from + interval '7 days'
         and coalesce(p.is_admin, false) = false
         and coalesce(p.email, '') not in ('pawan.2u2@gmail.com', 'triloks34@gmail.com',
                                           'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com')
         and public.current_tier(o.user_id) in ('pro', 'titan')
       group by o.user_id
      having count(*) >= 2 and sum(o.realized_pnl) > 0
    )
    select user_id,
           row_number() over (order by pnl / nullif(basis, 0) desc nulls last, pnl desc, user_id) as rank
      from closes
     order by rank
     limit 3
  loop
    if public.grant_challenge(v_row.user_id, 'paid_league_' || v_row.rank, v_week) then
      v_granted := v_granted + 1;
    end if;
  end loop;

  for v_row in
    select o.user_id,
           count(distinct (coalesce(o.executed_at, o.created_at) at time zone 'Asia/Kolkata')::date) as days,
           count(*) filter (where o.realized_pnl <> 0) as closes,
           coalesce(sum(o.realized_pnl), 0) as pnl
      from public.orders o
     where o.status = 'executed'
       and coalesce(o.executed_at, o.created_at) >= v_from
       and coalesce(o.executed_at, o.created_at) < v_from + interval '7 days'
     group by o.user_id
  loop
    if v_row.days >= 5 and public.grant_challenge(v_row.user_id, 'pro_week_5_days', v_week) then
      v_granted := v_granted + 1;
    end if;
    if v_row.closes >= 5 and v_row.pnl > 0 and public.grant_challenge(v_row.user_id, 'pro_week_green', v_week) then
      v_granted := v_granted + 1;
    end if;
  end loop;

  return v_granted;
end;
$$;
revoke all on function public.award_paid_weekly(text) from public, anon, authenticated;

-- Monday 00:10 IST = Sunday 18:40 UTC (five minutes after the main podium).
select cron.unschedule('award-paid-weekly')
 where exists (select 1 from cron.job where jobname = 'award-paid-weekly');
select cron.schedule('award-paid-weekly', '40 18 * * 0', $cron$ select public.award_paid_weekly(); $cron$);

-- ── Follow top traders ──────────────────────────────────────────────────────

alter table public.profiles add column if not exists share_trades boolean not null default false;

create table if not exists public.trader_follows (
  follower_id uuid not null references auth.users (id) on delete cascade,
  trader_id   uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, trader_id),
  check (follower_id <> trader_id)
);
create index if not exists trader_follows_trader_idx on public.trader_follows (trader_id);
alter table public.trader_follows enable row level security;
drop policy if exists trader_follows_own_read on public.trader_follows;
create policy trader_follows_own_read on public.trader_follows
  for select to authenticated using (follower_id = auth.uid());

create or replace function public.set_share_trades(p_on boolean)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  update public.profiles set share_trades = coalesce(p_on, false) where id = auth.uid();
  return coalesce(p_on, false);
end;
$$;
revoke all on function public.set_share_trades(boolean) from public, anon;
grant execute on function public.set_share_trades(boolean) to authenticated;

-- What the trader sheet shows when you tap someone on the league.
create or replace function public.trader_profile(p_trader uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'tier', public.current_tier(p.id),
    'shares_trades', p.share_trades,
    'is_me', p.id = auth.uid(),
    'following', exists (select 1 from public.trader_follows f where f.follower_id = auth.uid() and f.trader_id = p.id),
    'followers', (select count(*) from public.trader_follows f where f.trader_id = p.id),
    'trades_30d', (select count(*) from public.orders o where o.user_id = p.id and o.status = 'executed'
                     and o.realized_pnl <> 0 and coalesce(o.executed_at, o.created_at) > now() - interval '30 days'),
    'win_rate_30d', (select round(100.0 * count(*) filter (where o.realized_pnl > 0) / nullif(count(*), 0))
                       from public.orders o where o.user_id = p.id and o.status = 'executed'
                        and o.realized_pnl <> 0 and coalesce(o.executed_at, o.created_at) > now() - interval '30 days'))
    from public.profiles p
   where p.id = p_trader;
$$;
revoke all on function public.trader_profile(uuid) from public, anon;
grant execute on function public.trader_profile(uuid) to authenticated;

create or replace function public.follow_trader(p_trader uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if p_trader = v_uid then
    raise exception 'You can''t follow yourself';
  end if;
  if public.limits_enforced() and public.current_tier(v_uid) not in ('pro', 'titan') then
    raise exception 'PLAN_LIMIT:follow_traders:0';
  end if;
  if not exists (select 1 from public.profiles where id = p_trader and share_trades) then
    raise exception 'This trader doesn''t share their trades';
  end if;
  if (select count(*) from public.trader_follows where follower_id = v_uid) >= 20
     and not exists (select 1 from public.trader_follows where follower_id = v_uid and trader_id = p_trader) then
    raise exception 'You can follow up to 20 traders. Unfollow someone first.';
  end if;
  insert into public.trader_follows (follower_id, trader_id) values (v_uid, p_trader)
  on conflict do nothing;
  return true;
end;
$$;
revoke all on function public.follow_trader(uuid) from public, anon;
grant execute on function public.follow_trader(uuid) to authenticated;

create or replace function public.unfollow_trader(p_trader uuid)
returns boolean
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  delete from public.trader_follows where follower_id = auth.uid() and trader_id = p_trader;
  select true;
$$;
revoke all on function public.unfollow_trader(uuid) from public, anon;
grant execute on function public.unfollow_trader(uuid) to authenticated;

create or replace function public.followed_traders()
returns table (trader_id uuid, name text, tier text, shares_trades boolean, followed_at timestamptz, trades_7d integer, pnl_7d numeric)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select p.id, p.name, public.current_tier(p.id), p.share_trades, f.created_at,
         (select count(*)::integer from public.orders o where o.user_id = p.id and o.status = 'executed'
            and coalesce(o.executed_at, o.created_at) > now() - interval '7 days'),
         (select coalesce(sum(o.realized_pnl), 0) from public.orders o where o.user_id = p.id and o.status = 'executed'
            and coalesce(o.executed_at, o.created_at) > now() - interval '7 days')
    from public.trader_follows f
    join public.profiles p on p.id = f.trader_id
   where f.follower_id = auth.uid()
   order by f.created_at desc;
$$;
revoke all on function public.followed_traders() from public, anon;
grant execute on function public.followed_traders() to authenticated;

-- Recent executed trades of the people you follow. No quantities or wallet
-- figures: what they traded and how it went, nothing that sizes their account.
create or replace function public.followed_feed(p_limit integer default 50)
returns table (trader_id uuid, trader_name text, symbol text, name text, market text, side text,
               instrument_type text, option_type text, strike_price numeric, expiry_date text,
               price numeric, pnl_pct numeric, is_exit boolean, executed_at timestamptz)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if public.limits_enforced() and public.current_tier(auth.uid()) not in ('pro', 'titan') then
    raise exception 'PLAN_LIMIT:follow_traders:0';
  end if;
  return query
    select o.user_id, p.name, o.symbol, o.name, o.market, o.side,
           o.instrument_type, o.option_type, o.strike_price, o.expiry_date,
           o.price,
           case when o.realized_pnl <> 0 then
             round(o.realized_pnl / nullif(case when o.side = 'sell' then o.total - o.realized_pnl
                                                 else o.total + o.realized_pnl end, 0) * 100, 2)
           end,
           coalesce(o.is_exit, false),
           coalesce(o.executed_at, o.created_at)
      from public.trader_follows f
      join public.profiles p on p.id = f.trader_id and p.share_trades
      join public.orders o on o.user_id = f.trader_id and o.status = 'executed'
     where f.follower_id = auth.uid()
       and coalesce(o.executed_at, o.created_at) > now() - interval '14 days'
     order by coalesce(o.executed_at, o.created_at) desc
     limit least(greatest(p_limit, 1), 200);
end;
$$;
revoke all on function public.followed_feed(integer) from public, anon;
grant execute on function public.followed_feed(integer) to authenticated;

-- Push followers when a shared trade executes: at most one push per trader per
-- follower per hour. Never blocks or fails the order.
create or replace function public.notify_followers_on_trade()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_name text;
begin
  if new.status <> 'executed' or (tg_op = 'UPDATE' and old.status = 'executed') then
    return new;
  end if;
  begin
    select name into v_name from public.profiles where id = new.user_id and share_trades;
    if not found then
      return new;
    end if;
    insert into public.notifications (user_id, title, body, is_read, action_type, action_data)
    select f.follower_id,
           coalesce(nullif(trim(v_name), ''), 'A trader you follow') || ' just traded',
           initcap(new.side) || ' ' || new.symbol || '. Tap to see their recent trades. Learning only, not advice.',
           false, 'followed_trade', jsonb_build_object('trader', new.user_id, 'cta_route', 'following', 'cta_label', 'See trades')
      from public.trader_follows f
     where f.trader_id = new.user_id
       and (not public.limits_enforced() or public.current_tier(f.follower_id) in ('pro', 'titan'))
       and not exists (
         select 1 from public.notifications n
          where n.user_id = f.follower_id and n.action_type = 'followed_trade'
            and n.action_data->>'trader' = new.user_id::text
            and n.created_at > now() - interval '1 hour');
  exception when others then
    raise warning 'notify_followers_on_trade: %', sqlerrm;
  end;
  return new;
end;
$$;
revoke all on function public.notify_followers_on_trade() from public, anon, authenticated;

drop trigger if exists trg_notify_followers on public.orders;
create trigger trg_notify_followers
  after insert or update of status on public.orders
  for each row execute function public.notify_followers_on_trade();
