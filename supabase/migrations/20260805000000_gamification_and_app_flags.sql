-- Gamification (challenges -> demo-cash rewards) + DB-backed feature flags.
--
-- Design notes
-- ------------
-- * Payout reuses the EXISTING `rewards` table and `claim_reward` RPC, so the
--   confetti dialog, the notification and the atomic wallet credit all already
--   work. Granting a challenge is just an insert into `rewards`.
-- * Every grant is keyed (user_id, challenge_key, cycle) with a UNIQUE index.
--   That makes double-granting impossible rather than merely unlikely, and it
--   is what lets the evaluator be re-run as often as we like.
--   - once-only challenges use cycle = 'once'
--   - daily ones use the IST date, e.g. '2026-08-05'
--   - weekly ones use the ISO week, e.g. '2026-W32'
--   - tiered ones use the tier name, e.g. 'tier_1l'
--   - per-trade ones use 'order:<uuid>' so each qualifying trade pays once
-- * Evaluation is server-side only. The client can call evaluate_challenges()
--   but cannot choose what it earns.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Feature flags
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_flags (
    key         TEXT PRIMARY KEY,
    enabled     BOOLEAN NOT NULL DEFAULT false,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.app_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone signed in can read flags" ON public.app_flags;
CREATE POLICY "Anyone signed in can read flags"
    ON public.app_flags FOR SELECT
    USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Only admins can modify flags" ON public.app_flags;
CREATE POLICY "Only admins can modify flags"
    ON public.app_flags FOR ALL
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

INSERT INTO public.app_flags (key, enabled, description) VALUES
    ('monetization_enabled', false,
     'When true the wallet top-up card, the Subscribe screen and the plan badges are shown. False = app is completely free and those surfaces stay hidden.'),
    ('us_stocks_enabled', false,
     'When true the US Stocks market tab loads real data. False = tab shows a Coming soon state.')
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Profile columns the challenges need
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS login_streak         INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS longest_login_streak INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_login_date      DATE,
    ADD COLUMN IF NOT EXISTS total_xp             INTEGER NOT NULL DEFAULT 0,
    -- Baseline used for percentage-return challenges. Frozen at signup so that
    -- later top-ups or reward credits cannot move the goalposts.
    ADD COLUMN IF NOT EXISTS challenge_baseline_capital NUMERIC NOT NULL DEFAULT 11000;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Challenge catalogue
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.challenges (
    key           TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    description   TEXT NOT NULL,
    category      TEXT NOT NULL,          -- performance | habit | breadth | learning | social
    reward_amount NUMERIC NOT NULL,
    xp            INTEGER NOT NULL DEFAULT 0,
    repeat_limit  INTEGER,                -- NULL = unlimited
    sort_order    INTEGER NOT NULL DEFAULT 0,
    is_active     BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone signed in can read challenges" ON public.challenges;
CREATE POLICY "Anyone signed in can read challenges"
    ON public.challenges FOR SELECT
    USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Only admins can modify challenges" ON public.challenges;
CREATE POLICY "Only admins can modify challenges"
    ON public.challenges FOR ALL
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Per-user grant ledger. The UNIQUE constraint is the idempotency guarantee.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_challenges (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    challenge_key TEXT REFERENCES public.challenges(key) ON DELETE CASCADE NOT NULL,
    cycle         TEXT NOT NULL DEFAULT 'once',
    reward_amount NUMERIC NOT NULL,
    xp            INTEGER NOT NULL DEFAULT 0,
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, challenge_key, cycle)
);

CREATE INDEX IF NOT EXISTS idx_user_challenges_user ON public.user_challenges(user_id, granted_at DESC);

ALTER TABLE public.user_challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own challenge grants" ON public.user_challenges;
CREATE POLICY "Users can view own challenge grants"
    ON public.user_challenges FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin());
-- No INSERT/UPDATE policy on purpose: only the SECURITY DEFINER grant function
-- may write here.

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Seed the catalogue
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.challenges (key, title, description, category, reward_amount, xp, repeat_limit, sort_order) VALUES
    -- Performance
    ('first_blood',      'First Blood',        'Place your first executed order.',                                            'performance',  1000,  50,    1,  10),
    ('titan_20',         '20% Titan',          'Grow your realized profit to +20% of your starting capital.',                 'performance',  5000, 500,    1,  20),
    ('sniper',           'Sniper',             'Close a position of at least ₹10,000 for a 20% gain, held over a day.',       'performance',  2000, 200,    3,  30),
    ('green_day',        'Green Day',          'Finish a trading day with your portfolio in profit.',                          'performance',   500,  40,    5,  40),
    ('century_club_1l',  'Century Club',       'Cross ₹1,00,000 in lifetime realized profit.',                                'performance', 10000, 400,    1,  50),
    ('century_club_5l',  'Century Club V',     'Cross ₹5,00,000 in lifetime realized profit.',                                'performance', 25000, 900,    1,  51),
    ('century_club_10l', 'Century Club X',     'Cross ₹10,00,000 in lifetime realized profit.',                               'performance', 50000,1800,    1,  52),
    -- Habit
    ('login_streak_3',   'Warming Up',         'Open the app 3 days in a row.',                                               'habit',         200,  30,    1,  60),
    ('login_streak_7',   'Week Strong',        'Open the app 7 days in a row.',                                               'habit',         750,  80,    1,  61),
    ('login_streak_14',  'Fortnight Focus',    'Open the app 14 days in a row.',                                              'habit',        2000, 200,    1,  62),
    ('login_streak_30',  'Iron Habit',         'Open the app 30 days in a row.',                                              'habit',        5000, 600,    1,  63),
    ('trader_streak',    'Active Trader',      'Trade on 5 separate days within a week.',                                     'habit',        1500, 150,    1,  70),
    ('morning_bell',     'Morning Bell',       'Place an order in the first 15 minutes of the open, on 3 different days.',     'habit',         800, 100,    1,  80),
    -- Breadth
    ('globetrotter',     'Globetrotter',       'Hold Indian stocks, US stocks and crypto at the same time.',                  'breadth',      3000, 350,    1,  90),
    ('diversifier',      'Diversifier',        'Hold 5 or more different symbols at once.',                                   'breadth',      1500, 150,    1, 100),
    ('derivatives_debut','Derivatives Debut',  'Place your first futures or options trade.',                                  'breadth',      2500, 250,    1, 110),
    -- Learning
    ('autopsy_analyst',  'Autopsy Analyst',    'Run a trade autopsy on 5 of your losing trades.',                             'learning',     1000, 150,    1, 120),
    ('glossary_graduate','Glossary Graduate',  'Pass the trading glossary quiz.',                                             'learning',      750, 120,    1, 130),
    ('alert_watcher',    'Alert Watcher',      'Set 3 price alerts and have them trigger.',                                   'learning',      500,  60,    1, 140),
    -- Social
    ('referral_1',       'Recruiter',          'Bring 1 friend onto Trading Titans.',                                         'social',       1000, 100,    1, 150),
    ('referral_5',       'Talent Scout',       'Bring 5 friends onto Trading Titans.',                                        'social',       5000, 400,    1, 151),
    ('referral_10',      'Kingmaker',          'Bring 10 friends onto Trading Titans.',                                        'social',      12000, 900,    1, 152),
    ('podium_1',         'Weekly Champion',    'Finish the week 1st on the profit leaderboard.',                              'social',       2500, 500, NULL, 160),
    ('podium_2',         'Weekly Runner-up',   'Finish the week 2nd on the profit leaderboard.',                              'social',       1500, 300, NULL, 161),
    ('podium_3',         'Weekly Third',       'Finish the week 3rd on the profit leaderboard.',                              'social',       1000, 200, NULL, 162)
ON CONFLICT (key) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    reward_amount = EXCLUDED.reward_amount,
    xp = EXCLUDED.xp,
    repeat_limit = EXCLUDED.repeat_limit,
    sort_order = EXCLUDED.sort_order;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Grant helper — the only writer of user_challenges.
-- ─────────────────────────────────────────────────────────────────────────────
-- Monthly ceiling on granted demo cash. Stops a bug or a farming pattern from
-- printing unlimited balance.
-- ponytail: hardcoded ceiling. If it ever needs to differ per user, move it to
-- app_flags with a numeric value column.
CREATE OR REPLACE FUNCTION public.grant_challenge(
    p_user_id UUID,
    p_key     TEXT,
    p_cycle   TEXT DEFAULT 'once'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_monthly_cap   CONSTANT NUMERIC := 75000;
    v_challenge     public.challenges;
    v_already       INTEGER;
    v_granted_month NUMERIC;
    v_inserted      INTEGER;
BEGIN
    SELECT * INTO v_challenge FROM public.challenges
     WHERE key = p_key AND is_active;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Repeat limit: how many times has this key ever paid out for this user?
    IF v_challenge.repeat_limit IS NOT NULL THEN
        SELECT count(*) INTO v_already FROM public.user_challenges
         WHERE user_id = p_user_id AND challenge_key = p_key;
        IF v_already >= v_challenge.repeat_limit THEN
            RETURN false;
        END IF;
    END IF;

    -- Monthly cash ceiling.
    SELECT COALESCE(sum(reward_amount), 0) INTO v_granted_month
      FROM public.user_challenges
     WHERE user_id = p_user_id
       AND granted_at >= date_trunc('month', now());
    IF v_granted_month + v_challenge.reward_amount > v_monthly_cap THEN
        RETURN false;
    END IF;

    INSERT INTO public.user_challenges (user_id, challenge_key, cycle, reward_amount, xp)
    VALUES (p_user_id, p_key, p_cycle, v_challenge.reward_amount, v_challenge.xp)
    ON CONFLICT (user_id, challenge_key, cycle) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    IF v_inserted = 0 THEN
        RETURN false;   -- already granted for this cycle
    END IF;

    -- Payout rides the existing rewards pipe: the app picks this up and shows
    -- the confetti dialog, and claim_reward() credits the wallet atomically.
    INSERT INTO public.rewards (user_id, amount, message, is_claimed)
    VALUES (p_user_id, v_challenge.reward_amount,
            v_challenge.title || ' — ' || v_challenge.description, false);

    INSERT INTO public.notifications (user_id, title, body, is_read, action_type)
    VALUES (p_user_id,
            'Challenge complete: ' || v_challenge.title || ' 🏆',
            'You earned ₹' || to_char(v_challenge.reward_amount, 'FM999999999')
              || ' demo cash. Open the app to claim it.',
            false, 'reward');

    UPDATE public.profiles
       SET total_xp = total_xp + v_challenge.xp
     WHERE id = p_user_id;

    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_challenge(UUID, TEXT, TEXT) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Evaluator. Recomputes every condition from source tables and grants what
--    is newly earned. Safe to call as often as you like — the UNIQUE index on
--    (user_id, challenge_key, cycle) absorbs repeats.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.evaluate_challenges(p_user_id UUID DEFAULT auth.uid())
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_granted   INTEGER := 0;
    v_profile   public.profiles;
    v_today     TEXT := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD');
    v_count     INTEGER;
    v_sum       NUMERIC;
    v_order     RECORD;
BEGIN
    -- A signed-in non-admin may only ever evaluate themselves, whatever they
    -- pass in. Admins and the service role (auth.uid() IS NULL) may target
    -- anyone, which is what the nightly cron needs.
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
        p_user_id := auth.uid();
    END IF;

    IF p_user_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    -- ── First Blood ─────────────────────────────────────────────────────────
    IF EXISTS (SELECT 1 FROM public.orders
                WHERE user_id = p_user_id AND status = 'executed') THEN
        IF public.grant_challenge(p_user_id, 'first_blood') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── 20% Titan + Century Club tiers ──────────────────────────────────────
    -- Realized profit is used (not mark-to-market) so the milestone needs real
    -- closed trades and needs no live quote server-side.
    IF v_profile.total_realized_pnl >= 0.20 * v_profile.challenge_baseline_capital THEN
        IF public.grant_challenge(p_user_id, 'titan_20') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.total_realized_pnl >= 100000 THEN
        IF public.grant_challenge(p_user_id, 'century_club_1l') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.total_realized_pnl >= 500000 THEN
        IF public.grant_challenge(p_user_id, 'century_club_5l') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.total_realized_pnl >= 1000000 THEN
        IF public.grant_challenge(p_user_id, 'century_club_10l') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Sniper: one payout per qualifying closing trade ──────────────────────
    -- Anti-farming: the position must be worth >= ₹10,000, the gain must be
    -- >= 20% of cost, and a matching buy must exist at least a day earlier so a
    -- same-session round trip on a wide spread cannot qualify.
    FOR v_order IN
        SELECT o.id, o.realized_pnl, (o.total - o.realized_pnl) AS cost
          FROM public.orders o
         WHERE o.user_id = p_user_id
           AND o.side = 'sell'
           AND o.status = 'executed'
           AND o.realized_pnl > 0
           AND (o.total - o.realized_pnl) >= 10000
           AND o.realized_pnl >= 0.20 * (o.total - o.realized_pnl)
           AND EXISTS (
                 SELECT 1 FROM public.orders b
                  WHERE b.user_id = o.user_id
                    AND b.symbol = o.symbol
                    AND b.market = o.market
                    AND b.side = 'buy'
                    AND b.status = 'executed'
                    AND b.created_at <= o.created_at - INTERVAL '1 day')
         ORDER BY o.created_at
    LOOP
        IF public.grant_challenge(p_user_id, 'sniper', 'order:' || v_order.id) THEN
            v_granted := v_granted + 1;
        END IF;
    END LOOP;

    -- ── Green Day (today, IST) ──────────────────────────────────────────────
    -- Booked from `orders` rather than `pnl_history`: the snapshot-pnl job has
    -- no cron schedule in this repo, so pnl_history cannot be relied on. Using
    -- realized P&L also means the day has to be closed out at a profit, not
    -- merely marked up.
    SELECT COALESCE(sum(realized_pnl), 0) INTO v_sum
      FROM public.orders
     WHERE user_id = p_user_id
       AND status = 'executed'
       AND to_char(created_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD') = v_today;
    IF v_sum > 0 THEN
        IF public.grant_challenge(p_user_id, 'green_day', v_today) THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Login streaks (longest ever, so a lapse does not revoke a badge) ─────
    IF v_profile.longest_login_streak >= 3 THEN
        IF public.grant_challenge(p_user_id, 'login_streak_3') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.longest_login_streak >= 7 THEN
        IF public.grant_challenge(p_user_id, 'login_streak_7') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.longest_login_streak >= 14 THEN
        IF public.grant_challenge(p_user_id, 'login_streak_14') THEN v_granted := v_granted + 1; END IF;
    END IF;
    IF v_profile.longest_login_streak >= 30 THEN
        IF public.grant_challenge(p_user_id, 'login_streak_30') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Active Trader: 5 distinct trading days inside the last 7 ─────────────
    -- ponytail: calendar days, not exchange days. A 5-in-7 window can only be
    -- hit on real trading days anyway, so a holiday calendar would add code
    -- without changing outcomes.
    SELECT count(DISTINCT (created_at AT TIME ZONE 'Asia/Kolkata')::date) INTO v_count
      FROM public.orders
     WHERE user_id = p_user_id
       AND status = 'executed'
       AND created_at >= now() - INTERVAL '7 days';
    IF v_count >= 5 THEN
        IF public.grant_challenge(p_user_id, 'trader_streak') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Morning Bell: 3 different days with an order in 09:15–09:30 IST ──────
    SELECT count(DISTINCT (created_at AT TIME ZONE 'Asia/Kolkata')::date) INTO v_count
      FROM public.orders
     WHERE user_id = p_user_id
       AND status = 'executed'
       AND (created_at AT TIME ZONE 'Asia/Kolkata')::time BETWEEN TIME '09:15' AND TIME '09:30';
    IF v_count >= 3 THEN
        IF public.grant_challenge(p_user_id, 'morning_bell') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Globetrotter: all three markets held at once ─────────────────────────
    SELECT count(DISTINCT market) INTO v_count
      FROM public.holdings
     WHERE user_id = p_user_id
       AND quantity > 0
       AND market IN ('stock', 'us_stock', 'crypto');
    IF v_count >= 3 THEN
        IF public.grant_challenge(p_user_id, 'globetrotter') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Diversifier ─────────────────────────────────────────────────────────
    -- ponytail: distinct symbols, not distinct sectors — there is no sector
    -- column on `instruments` yet. Add one and tighten this to 3+ sectors.
    SELECT count(DISTINCT symbol) INTO v_count
      FROM public.holdings
     WHERE user_id = p_user_id AND quantity > 0;
    IF v_count >= 5 THEN
        IF public.grant_challenge(p_user_id, 'diversifier') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Derivatives Debut ───────────────────────────────────────────────────
    IF EXISTS (SELECT 1 FROM public.orders
                WHERE user_id = p_user_id
                  AND status = 'executed'
                  AND instrument_type IN ('OPTION', 'FUTURE')) THEN
        IF public.grant_challenge(p_user_id, 'derivatives_debut') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Autopsy Analyst ─────────────────────────────────────────────────────
    SELECT count(*) INTO v_count FROM public.trade_autopsies
     WHERE user_id = p_user_id AND pnl < 0;
    IF v_count >= 5 THEN
        IF public.grant_challenge(p_user_id, 'autopsy_analyst') THEN v_granted := v_granted + 1; END IF;
    END IF;

    -- ── Alert Watcher ───────────────────────────────────────────────────────
    -- `price_alerts` is used by the app but was never created by a migration,
    -- so it may or may not exist in a given environment. Probe first and use
    -- dynamic SQL so this function neither fails to create nor throws at run
    -- time when the table is absent.
    IF to_regclass('public.price_alerts') IS NOT NULL THEN
        EXECUTE 'SELECT count(*) FROM public.price_alerts
                  WHERE user_id = $1 AND status = ''triggered'''
           INTO v_count USING p_user_id;
        IF v_count >= 3 THEN
            IF public.grant_challenge(p_user_id, 'alert_watcher') THEN v_granted := v_granted + 1; END IF;
        END IF;
    END IF;

    -- ── Referral milestones ─────────────────────────────────────────────────
    SELECT count(*) INTO v_count FROM public.profiles WHERE referred_by = p_user_id;
    IF v_count >= 1  THEN IF public.grant_challenge(p_user_id, 'referral_1')  THEN v_granted := v_granted + 1; END IF; END IF;
    IF v_count >= 5  THEN IF public.grant_challenge(p_user_id, 'referral_5')  THEN v_granted := v_granted + 1; END IF; END IF;
    IF v_count >= 10 THEN IF public.grant_challenge(p_user_id, 'referral_10') THEN v_granted := v_granted + 1; END IF; END IF;

    RETURN v_granted;
END;
$$;

REVOKE ALL ON FUNCTION public.evaluate_challenges(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.evaluate_challenges(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Login streak. Called by the app on startup; always acts on the caller.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_login_streak()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_uid   UUID := auth.uid();
    v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_last  DATE;
    v_streak INTEGER;
BEGIN
    IF v_uid IS NULL THEN
        RETURN 0;
    END IF;

    SELECT last_login_date, login_streak INTO v_last, v_streak
      FROM public.profiles WHERE id = v_uid;

    IF v_last = v_today THEN
        RETURN v_streak;                       -- already counted today
    ELSIF v_last = v_today - 1 THEN
        v_streak := COALESCE(v_streak, 0) + 1; -- consecutive
    ELSE
        v_streak := 1;                         -- first login, or streak broken
    END IF;

    UPDATE public.profiles
       SET last_login_date      = v_today,
           login_streak         = v_streak,
           longest_login_streak = GREATEST(longest_login_streak, v_streak)
     WHERE id = v_uid;

    PERFORM public.evaluate_challenges(v_uid);
    RETURN v_streak;
END;
$$;

REVOKE ALL ON FUNCTION public.touch_login_streak() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_login_streak() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Glossary quiz. The pass/fail is decided in the app, but the grant is here
--    so the reward amount and the one-shot limit stay server-side.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_glossary_quiz()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    RETURN public.grant_challenge(auth.uid(), 'glossary_graduate');
END;
$$;

REVOKE ALL ON FUNCTION public.award_glossary_quiz() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.award_glossary_quiz() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Weekly podium. Ranks on realized P&L booked inside the ISO week, taken
--     straight from `orders`, so no extra snapshot table is needed.
--     Owners and admins are excluded: they hold large demo balances by design
--     and would otherwise sweep the podium every week.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_weekly_podium(p_week TEXT DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_week    TEXT := COALESCE(p_week, to_char(now() AT TIME ZONE 'Asia/Kolkata', 'IYYY-"W"IW'));
    v_granted INTEGER := 0;
    v_row     RECORD;
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'award_weekly_podium is admin/service-role only';
    END IF;

    FOR v_row IN
        SELECT o.user_id,
               row_number() OVER (ORDER BY sum(o.realized_pnl) DESC) AS rank
          FROM public.orders o
          JOIN public.profiles p ON p.id = o.user_id
         WHERE o.status = 'executed'
           AND to_char(o.created_at AT TIME ZONE 'Asia/Kolkata', 'IYYY-"W"IW') = v_week
           AND NOT p.is_admin
           AND p.email NOT IN ('pawan.2u2@gmail.com', 'triloks34@gmail.com',
                               'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com')
         GROUP BY o.user_id
        HAVING sum(o.realized_pnl) > 0
         LIMIT 3
    LOOP
        IF public.grant_challenge(v_row.user_id, 'podium_' || v_row.rank, v_week) THEN
            v_granted := v_granted + 1;
        END IF;
    END LOOP;

    RETURN v_granted;
END;
$$;

REVOKE ALL ON FUNCTION public.award_weekly_podium(TEXT) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Nightly sweep for everyone. Service role only (called by the cron).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.evaluate_challenges_all()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_total INTEGER := 0;
    v_id    UUID;
BEGIN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'evaluate_challenges_all is admin/service-role only';
    END IF;

    -- Only users who did something in the last 2 days can have newly qualified
    -- for a day-scoped challenge, so skip the long tail of dormant accounts.
    FOR v_id IN
        SELECT id FROM public.profiles
         WHERE last_login_date >= (now() AT TIME ZONE 'Asia/Kolkata')::date - 2
            OR id IN (SELECT DISTINCT user_id FROM public.orders
                       WHERE created_at >= now() - INTERVAL '2 days')
    LOOP
        v_total := v_total + public.evaluate_challenges(v_id);
    END LOOP;

    RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.evaluate_challenges_all() FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Read-side helper: catalogue + this user's progress in one round trip.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_challenges()
RETURNS TABLE (
    key           TEXT,
    title         TEXT,
    description   TEXT,
    category      TEXT,
    reward_amount NUMERIC,
    xp            INTEGER,
    repeat_limit  INTEGER,
    sort_order    INTEGER,
    times_earned  INTEGER,
    total_earned  NUMERIC,
    last_earned_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
           c.repeat_limit, c.sort_order,
           COALESCE(count(uc.id), 0)::INTEGER              AS times_earned,
           COALESCE(sum(uc.reward_amount), 0)              AS total_earned,
           max(uc.granted_at)                              AS last_earned_at
      FROM public.challenges c
      LEFT JOIN public.user_challenges uc
             ON uc.challenge_key = c.key AND uc.user_id = auth.uid()
     WHERE c.is_active
     GROUP BY c.key, c.title, c.description, c.category, c.reward_amount, c.xp,
              c.repeat_limit, c.sort_order
     ORDER BY c.sort_order;
$$;

REVOKE ALL ON FUNCTION public.get_my_challenges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_challenges() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. Schedules. Same pg_cron pattern as the existing NSE / F&O jobs.
--     Times are UTC; IST is UTC+5:30.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('evaluate-challenges-daily')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'evaluate-challenges-daily');

SELECT cron.unschedule('award-weekly-podium')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'award-weekly-podium');

-- Mon–Fri 16:15 IST (10:45 UTC), after the 15:30 IST close, so day-scoped
-- challenges (Green Day, Morning Bell, Active Trader) settle the same evening.
SELECT cron.schedule(
  'evaluate-challenges-daily',
  '45 10 * * 1-5',
  $cron$ SELECT public.evaluate_challenges_all(); $cron$
);

-- Sunday 00:30 IST (Saturday 19:00 UTC): the trading week is over, so the
-- podium is final. Passing NULL uses the just-finished ISO week.
SELECT cron.schedule(
  'award-weekly-podium',
  '0 19 * * 6',
  $cron$ SELECT public.award_weekly_podium(); $cron$
);
