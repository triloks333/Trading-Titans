-- Commodities (gold, silver, crude, gas, copper) become a market a user can pick
-- as one of their 3 preferred markets. Only change from the live definition: the
-- whitelist in save_user_preferences gains 'commodity'. Orders/holdings have no
-- market CHECK constraint, so nothing else in the schema needs touching.
CREATE OR REPLACE FUNCTION public.save_user_preferences(p_display_currency text DEFAULT NULL::text, p_preferred_markets text[] DEFAULT NULL::text[], p_complete_onboarding boolean DEFAULT false, p_location text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_state text DEFAULT NULL::text)
 RETURNS TABLE(display_currency text, preferred_markets text[], location text, country_code text, state text, onboarding_completed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        IF v_currency NOT IN ('INR', 'USD', 'PKR', 'EUR') THEN
            RAISE EXCEPTION 'display_currency must be INR, USD, PKR or EUR, got %', p_display_currency;
        END IF;
    END IF;

    IF p_country_code IS NOT NULL THEN
        v_country := upper(btrim(p_country_code));
        IF v_country !~ '^[A-Z]{2}$' THEN
            RAISE EXCEPTION 'country_code must be ISO 3166-1 alpha-2, got %', p_country_code;
        END IF;
        v_location := CASE WHEN v_country = 'IN' THEN 'india' ELSE 'outside_india' END;
    ELSIF p_location IS NOT NULL THEN
        v_location := lower(btrim(p_location));
        IF v_location NOT IN ('india', 'outside_india') THEN
            RAISE EXCEPTION 'location must be india or outside_india, got %', p_location;
        END IF;
    END IF;

    IF p_state IS NOT NULL THEN
        v_state := btrim(p_state);
        IF v_state = '' THEN
            v_state := NULL;
        ELSIF length(v_state) > 80 THEN
            RAISE EXCEPTION 'state is too long';
        END IF;
    END IF;

    IF p_preferred_markets IS NOT NULL THEN
        SELECT array_agg(DISTINCT m) INTO v_markets
          FROM unnest(p_preferred_markets) AS m
         WHERE m IN ('stock', 'us_stock', 'crypto', 'commodity', 'pakistan_stock', 'italy_stock');
        IF v_markets IS NULL OR array_length(v_markets, 1) = 0 THEN
            v_markets := ARRAY['stock'];
        END IF;
    END IF;

    UPDATE public.profiles p
       SET display_currency        = COALESCE(v_currency, p.display_currency),
           preferred_markets       = COALESCE(v_markets, p.preferred_markets),
           location                = COALESCE(v_location, p.location),
           country_code            = CASE WHEN p_country_code IS NOT NULL THEN v_country ELSE p.country_code END,
           state                   = CASE WHEN p_state IS NOT NULL THEN v_state ELSE p.state END,
           onboarding_completed_at = CASE
                                       WHEN p_complete_onboarding AND p.onboarding_completed_at IS NULL THEN now()
                                       ELSE p.onboarding_completed_at
                                     END
     WHERE p.id = v_uid;

    RETURN QUERY
    SELECT p.display_currency, p.preferred_markets, p.location,
           p.country_code, p.state, p.onboarding_completed_at
      FROM public.profiles p
     WHERE p.id = v_uid;
END;
$function$;
