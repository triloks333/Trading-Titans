-- Where the user is trading from: India, or outside India.
--
-- Two values only, by design. It is stored for its own sake (and to pre-select
-- sensible answers to the currency and market questions during onboarding); it
-- does not gate access to anything.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS location TEXT;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_location_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_location_check
    CHECK (location IS NULL OR location IN ('india', 'outside_india'));

COMMENT ON COLUMN public.profiles.location IS
    'india | outside_india. NULL for accounts that predate the question.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Both preference RPCs gain the new field. The old signatures are dropped rather
-- than overloaded: PostgREST resolves by argument name, and two candidates would
-- make the call ambiguous. The new parameter defaults to NULL, so a client that
-- omits it still resolves and leaves the column untouched.
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.save_user_preferences(TEXT, TEXT[], BOOLEAN);
DROP FUNCTION IF EXISTS public.get_user_preferences();

CREATE OR REPLACE FUNCTION public.save_user_preferences(
    p_display_currency    TEXT DEFAULT NULL,
    p_preferred_markets   TEXT[] DEFAULT NULL,
    p_complete_onboarding BOOLEAN DEFAULT false,
    p_location            TEXT DEFAULT NULL
)
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    location                TEXT,
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
    v_location TEXT;
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

    IF p_location IS NOT NULL THEN
        v_location := lower(btrim(p_location));
        IF v_location NOT IN ('india', 'outside_india') THEN
            RAISE EXCEPTION 'location must be india or outside_india, got %', p_location;
        END IF;
    END IF;

    IF p_preferred_markets IS NOT NULL THEN
        -- Drop anything unrecognised rather than rejecting the whole call, so a
        -- newer client sending a market this build does not know about still
        -- saves the rest.
        SELECT array_agg(DISTINCT m) INTO v_markets
          FROM unnest(p_preferred_markets) AS m
         WHERE m IN ('stock', 'us_stock', 'crypto');
        IF v_markets IS NULL OR array_length(v_markets, 1) = 0 THEN
            v_markets := ARRAY['stock'];
        END IF;
    END IF;

    UPDATE public.profiles p
       SET display_currency  = COALESCE(v_currency, p.display_currency),
           preferred_markets = COALESCE(v_markets, p.preferred_markets),
           location          = COALESCE(v_location, p.location),
           onboarding_completed_at = CASE
               WHEN p_complete_onboarding THEN COALESCE(p.onboarding_completed_at, now())
               ELSE p.onboarding_completed_at
           END
     WHERE p.id = v_uid;

    RETURN QUERY
    SELECT p.display_currency, p.preferred_markets, p.location, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_preferences()
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    location                TEXT,
    onboarding_completed_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT p.display_currency, p.preferred_markets, p.location, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_user_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_preferences() TO authenticated;
