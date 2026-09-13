-- Per-user display currency and preferred markets, plus a first-run onboarding
-- marker.
--
-- Display currency is presentation only. The wallet ledger, order prices, P&L
-- and every engine calculation stay in INR exactly as before; the app converts
-- at render time using a live USD/INR rate. Nothing here changes stored money.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS display_currency TEXT NOT NULL DEFAULT 'INR',
    ADD COLUMN IF NOT EXISTS preferred_markets TEXT[] NOT NULL DEFAULT ARRAY['stock','crypto'],
    ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

-- Guard the currency to the two options the picker offers, so a bad client can
-- never store something the formatter cannot handle.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_display_currency_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_display_currency_check
    CHECK (display_currency IN ('INR', 'USD'));

COMMENT ON COLUMN public.profiles.display_currency IS
    'Presentation currency for the whole app (INR or USD). Stored money is always INR.';
COMMENT ON COLUMN public.profiles.preferred_markets IS
    'Markets the user cares about: any of stock, us_stock, crypto. Drives default tab and ordering; does not restrict access.';
COMMENT ON COLUMN public.profiles.onboarding_completed_at IS
    'Set when the first-run currency/markets questions are answered. NULL means show onboarding.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Preference writes go through a validated RPC. `profiles` has no UPDATE policy
-- for users (money columns live on the same row), so this is the only way for a
-- client to change its own preferences — and it can only touch these three
-- columns.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.save_user_preferences(
    p_display_currency  TEXT DEFAULT NULL,
    p_preferred_markets TEXT[] DEFAULT NULL,
    p_complete_onboarding BOOLEAN DEFAULT false
)
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    onboarding_completed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_uid      UUID := auth.uid();
    v_currency TEXT;
    v_markets  TEXT[];
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_display_currency IS NOT NULL THEN
        v_currency := upper(btrim(p_display_currency));
        IF v_currency NOT IN ('INR', 'USD') THEN
            RAISE EXCEPTION 'display_currency must be INR or USD, got %', p_display_currency;
        END IF;
    END IF;

    IF p_preferred_markets IS NOT NULL THEN
        -- Drop anything unrecognised rather than rejecting the whole call, so a
        -- newer client sending a market this build does not know about still
        -- saves the rest.
        SELECT array_agg(DISTINCT m) INTO v_markets
          FROM unnest(p_preferred_markets) AS m
         WHERE m IN ('stock', 'us_stock', 'crypto');
        -- An empty selection is meaningless; fall back to the Indian default.
        IF v_markets IS NULL OR array_length(v_markets, 1) = 0 THEN
            v_markets := ARRAY['stock'];
        END IF;
    END IF;

    UPDATE public.profiles p
       SET display_currency  = COALESCE(v_currency, p.display_currency),
           preferred_markets = COALESCE(v_markets, p.preferred_markets),
           onboarding_completed_at = CASE
               WHEN p_complete_onboarding THEN COALESCE(p.onboarding_completed_at, now())
               ELSE p.onboarding_completed_at
           END
     WHERE p.id = v_uid;

    RETURN QUERY
    SELECT p.display_currency, p.preferred_markets, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN) TO authenticated;

-- Read side: the app needs its own preferences before the first frame, and
-- `profiles` SELECT is restricted to self/admin already, so a narrow getter
-- keeps the client from having to read the whole money row.
CREATE OR REPLACE FUNCTION public.get_user_preferences()
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    onboarding_completed_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT p.display_currency, p.preferred_markets, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_user_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_preferences() TO authenticated;
