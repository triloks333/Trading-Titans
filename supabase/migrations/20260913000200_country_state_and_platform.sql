-- Where users are, in detail, and what they run the app on.
--
-- Requested: "Location classification so that we will know exactly from where
-- which country the users are from, which state and so on ... this must be very
-- broad" and "Platform classification as users are using on android app or on
-- webapp".
--
-- ── WHAT EXISTED ───────────────────────────────────────────────────────────
-- `profiles.location` is a two-value self-declared answer, india | outside_india
-- (20260808000000). Today: 242 india, 33 outside_india, 41 null. Nothing anywhere
-- records a country, a state, or which platform an account uses. `push_tokens`
-- has a `platform` column but it only ever says android or ios, and a
-- browser-only user has no row at all, so its absence conflates web users with
-- users who denied notifications.
--
-- ── location IS DERIVED FROM country_code, NOT STORED ALONGSIDE IT ──────────
-- This is the load-bearing decision. `location` is a MONEY input: it is the sole
-- reason create-payment-order charges in USD rather than INR
-- (functions/create-payment-order/index.ts:137, `location === "outside_india"`).
-- Its own comment is explicit that currency must come from residency and never
-- from the client's display preference.
--
-- Keeping a country AND an independent india/outside_india flag would be two
-- copies of the same fact, and the day they disagreed someone in London would be
-- billed in rupees. So `save_user_preferences` now derives location from
-- country_code: 'IN' means india, any other country means outside_india. There is
-- no path that sets one without the other.
--
-- No IP geolocation, deliberately. The user chose self-declared dropdowns, which
-- also means app/lib/core/legal.dart:300 can keep promising "No contacts, no
-- precise location" — an IP lookup would have made that copy false and needed a
-- privacy policy change.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.profiles                +country_code, +state, +last_platform
--   public.save_user_preferences   dropped and recreated with two more params
--   public.get_user_preferences    dropped and recreated, returns the new fields
--   public.record_platform         new
--   public.admin_user_stats        new
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Safe for shipped builds. The new parameters default to NULL, and PostgREST
-- resolves by argument name, so 1.2.3's four-named-argument call still binds and
-- still leaves the new columns untouched. Both preference RPCs are dropped rather
-- than overloaded for exactly that reason: two candidates would make the call
-- ambiguous and break every client at once (the note is inherited from
-- 20260808000000, which learned it the same way).
--
-- Extra columns on the RETURNS TABLE are additive; the app reads named keys off
-- the returned map.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   drop function if exists public.admin_user_stats();
--   drop function if exists public.record_platform(text);
--   alter table public.profiles
--     drop column if exists country_code,
--     drop column if exists state,
--     drop column if exists last_platform;
--   -- then re-run 20260808000000 to restore the 4-argument preference RPCs.

-- ── 1. Columns ─────────────────────────────────────────────────────────────
alter table public.profiles
    add column if not exists country_code  text,
    add column if not exists state         text,
    add column if not exists last_platform text;

alter table public.profiles drop constraint if exists profiles_country_code_check;
alter table public.profiles
    add constraint profiles_country_code_check
    -- ISO 3166-1 alpha-2, uppercase. A pattern rather than an enum of 250 values:
    -- the country list belongs in the client, and pinning it here would mean a
    -- migration every time a country is renamed or added.
    check (country_code is null or country_code ~ '^[A-Z]{2}$');

alter table public.profiles drop constraint if exists profiles_last_platform_check;
alter table public.profiles
    add constraint profiles_last_platform_check
    check (last_platform is null or last_platform in ('android', 'ios', 'web'));

comment on column public.profiles.country_code is
    'ISO 3166-1 alpha-2, uppercase. Self-declared. NULL for accounts that predate '
    'the question. location is DERIVED from this by save_user_preferences and must '
    'never be set independently — it decides the billing currency.';
comment on column public.profiles.state is
    'Subdivision within country_code, as the user picked or typed it. Free text: '
    'the authoritative list is per country and lives in the client.';
comment on column public.profiles.last_platform is
    'android | ios | web. The platform of the most recent session, written by '
    'record_platform() on launch. Last-seen, not first-seen: it answers "what are '
    'people using", so a user who moves from web to the app should move with them.';

-- Cheap covering indexes for the admin breakdown. Partial, because a NULL bucket
-- is not something anyone filters on and 41 of the rows are NULL today.
create index if not exists profiles_country_idx  on public.profiles (country_code) where country_code is not null;
create index if not exists profiles_platform_idx on public.profiles (last_platform) where last_platform is not null;

-- ── 2. Preferences, now carrying country and state ─────────────────────────
drop function if exists public.save_user_preferences(TEXT, TEXT[], BOOLEAN, TEXT);
drop function if exists public.get_user_preferences();

create or replace function public.save_user_preferences(
    p_display_currency    TEXT DEFAULT NULL,
    p_preferred_markets   TEXT[] DEFAULT NULL,
    p_complete_onboarding BOOLEAN DEFAULT false,
    p_location            TEXT DEFAULT NULL,
    p_country_code        TEXT DEFAULT NULL,
    p_state               TEXT DEFAULT NULL
)
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    location                TEXT,
    country_code            TEXT,
    state                   TEXT,
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
    v_country  TEXT;
    v_state    TEXT;
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

    IF p_country_code IS NOT NULL THEN
        v_country := upper(btrim(p_country_code));
        IF v_country !~ '^[A-Z]{2}$' THEN
            RAISE EXCEPTION 'country_code must be ISO 3166-1 alpha-2, got %', p_country_code;
        END IF;
        -- THE DERIVATION. A country implies the residency flag, so the two cannot
        -- drift apart and bill someone in the wrong currency. An explicit
        -- p_location in the same call is ignored on purpose rather than fought
        -- over: the more specific answer wins.
        v_location := CASE WHEN v_country = 'IN' THEN 'india' ELSE 'outside_india' END;
    ELSIF p_location IS NOT NULL THEN
        -- Still accepted on its own, because 1.2.3 is live and sends exactly this
        -- and nothing else.
        v_location := lower(btrim(p_location));
        IF v_location NOT IN ('india', 'outside_india') THEN
            RAISE EXCEPTION 'location must be india or outside_india, got %', p_location;
        END IF;
    END IF;

    IF p_state IS NOT NULL THEN
        v_state := btrim(p_state);
        -- Empty means "clear it", which is different from NULL meaning "leave it".
        IF v_state = '' THEN
            v_state := NULL;
        ELSIF length(v_state) > 80 THEN
            RAISE EXCEPTION 'state is too long';
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
           country_code      = COALESCE(v_country, p.country_code),
           -- Not COALESCE: p_state = '' resolves v_state to NULL and must clear the
           -- column, which COALESCE would silently refuse to do.
           state             = CASE WHEN p_state IS NULL THEN p.state ELSE v_state END,
           onboarding_completed_at = CASE
               WHEN p_complete_onboarding THEN COALESCE(p.onboarding_completed_at, now())
               ELSE p.onboarding_completed_at
           END
     WHERE p.id = v_uid;

    RETURN QUERY
    SELECT p.display_currency, p.preferred_markets, p.location,
           p.country_code, p.state, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_user_preferences(TEXT, TEXT[], BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

create or replace function public.get_user_preferences()
RETURNS TABLE (
    display_currency        TEXT,
    preferred_markets       TEXT[],
    location                TEXT,
    country_code            TEXT,
    state                   TEXT,
    onboarding_completed_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT p.display_currency, p.preferred_markets, p.location,
           p.country_code, p.state, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_user_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_preferences() TO authenticated;

-- ── 3. Platform, recorded on launch ────────────────────────────────────────
-- Its own RPC rather than a parameter on save_user_preferences: preferences are
-- saved when someone changes a setting, and platform has to be recorded every
-- launch. Folding them together would mean either writing preferences that nobody
-- changed, or only learning the platform of users who visit Settings.
create or replace function public.record_platform(p_platform TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_uid      UUID := auth.uid();
    v_platform TEXT := lower(btrim(coalesce(p_platform, '')));
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    -- Anything unrecognised is dropped silently rather than raised: this is called
    -- on every launch as a side effect, and a future platform name must not be
    -- able to make the app fail to start.
    IF v_platform NOT IN ('android', 'ios', 'web') THEN
        RETURN;
    END IF;
    UPDATE public.profiles SET last_platform = v_platform
     WHERE id = v_uid AND coalesce(last_platform, '') <> v_platform;
END;
$$;

REVOKE ALL ON FUNCTION public.record_platform(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_platform(TEXT) TO authenticated;

comment on function public.record_platform(TEXT) is
    'Records the caller''s platform on profiles.last_platform. Own row only, '
    'derived from auth.uid(). Writes nothing when the value is unchanged or '
    'unrecognised, so it is safe to call on every launch.';

-- ── 4. The admin breakdown ─────────────────────────────────────────────────
-- Long format — (dimension, value, users) — rather than one function per
-- breakdown or a wide row. One shape means the screen groups rows instead of
-- knowing about each dimension, so adding a dimension later needs no client
-- change at all.
create or replace function public.admin_user_stats()
RETURNS TABLE (dimension TEXT, value TEXT, users BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    -- Admin only. This aggregates across every account, which is precisely what
    -- profiles' own-row-only policy exists to prevent for ordinary users. Counts
    -- only, never a row per user, so it cannot become a way to enumerate people.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'admin_user_stats is admin only';
    END IF;

    RETURN QUERY
    SELECT 'total'::TEXT, 'all'::TEXT, count(*) FROM public.profiles
    UNION ALL
    SELECT 'country', coalesce(p.country_code, 'unknown'), count(*)
      FROM public.profiles p GROUP BY coalesce(p.country_code, 'unknown')
    UNION ALL
    -- State is only meaningful next to its country, so the label carries both.
    SELECT 'state', coalesce(p.country_code, '??') || ' · ' || coalesce(p.state, 'unknown'), count(*)
      FROM public.profiles p GROUP BY coalesce(p.country_code, '??'), coalesce(p.state, 'unknown')
    UNION ALL
    SELECT 'platform', coalesce(p.last_platform, 'unknown'), count(*)
      FROM public.profiles p GROUP BY coalesce(p.last_platform, 'unknown')
    UNION ALL
    -- Kept because it is what the billing currency actually reads, so a mismatch
    -- between this and the country breakdown is a bug worth seeing.
    SELECT 'residency', coalesce(p.location, 'unknown'), count(*)
      FROM public.profiles p GROUP BY coalesce(p.location, 'unknown')
    ORDER BY 1, 3 DESC, 2;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_stats() TO authenticated;

comment on function public.admin_user_stats() is
    'Aggregate user counts by country, state, platform and residency, for the admin '
    'analytics screen. Admin only, enforced inside the function. Returns counts '
    'only — never a row per user.';
