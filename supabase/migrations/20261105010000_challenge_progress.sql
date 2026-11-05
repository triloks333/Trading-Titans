-- Challenge progress bars: get_my_challenges() now also returns `progress` and
-- `target` for every challenge that has a measurable condition, so the
-- Challenges screen can show "2 of 3" instead of only earned/not earned.
--
-- Each measure mirrors the condition in evaluate_challenges() exactly; when you
-- change a condition there, change its line here too. Challenges with no single
-- running measure (Sniper, Green Day, Glossary Graduate, podium and top-10
-- placings) return NULL for both and show no bar.
--
-- The return type grows two columns, so the function is dropped and recreated.
-- Shipped builds read rows by column name and ignore the extras.

drop function if exists public.get_my_challenges();

create function public.get_my_challenges()
returns table (
  key text,
  title text,
  description text,
  category text,
  reward_amount numeric,
  xp integer,
  repeat_limit integer,
  sort_order integer,
  times_earned integer,
  total_earned numeric,
  last_earned_at timestamptz,
  progress numeric,
  target numeric
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (
    select p.* from public.profiles p where p.id = auth.uid()
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
      (select count(*) from public.profiles where referred_by = (select id from me)) as referrals
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
        ('referral_10',       s.referrals::numeric,                          10::numeric)
      ) as k(key, progress, target)
  )
  select c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
         c.repeat_limit, c.sort_order,
         coalesce(count(uc.id), 0)::integer as times_earned,
         coalesce(sum(uc.reward_amount), 0)  as total_earned,
         max(uc.granted_at)                  as last_earned_at,
         least(m.progress, m.target)         as progress,
         m.target
    from public.challenges c
    left join public.user_challenges uc on uc.challenge_key = c.key and uc.user_id = auth.uid()
    left join measures m on m.key = c.key
   where c.is_active
   group by c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
            c.repeat_limit, c.sort_order, m.progress, m.target
   order by c.sort_order;
$$;

revoke all on function public.get_my_challenges() from public;
grant execute on function public.get_my_challenges() to authenticated;
