-- 1. FIX PROFILES DISPLAY CURRENCY CONSTRAINT
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_display_currency_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_display_currency_check
    CHECK (display_currency IN ('INR', 'USD', 'PKR', 'EUR'));

-- 2. UPDATE SAVE_USER_PREFERENCES RPC
CREATE OR REPLACE FUNCTION public.save_user_preferences(
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
         WHERE m IN ('stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock');
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
$$;

-- 3. UPDATE GUEST & USER INITIAL DEMO CASH TO 500 & 1100
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
declare
  ref_by uuid;
  is_guest boolean := coalesce(new.is_anonymous, false);
  initial_bal numeric := case when is_guest then 500.0 else 1100.0 end;
  baseline numeric := initial_bal;
  v_email text;
  v_name text;
begin
  begin
    ref_by := nullif(new.raw_user_meta_data->>'referred_by', '')::uuid;
  exception when others then
    ref_by := null;
  end;

  v_email := coalesce(new.email, new.id::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(new.raw_user_meta_data->>'name', ''),
                     nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
                     'Guest Titan');

  begin
    if ref_by is not null then
      initial_bal := initial_bal + 500.0;
      update public.profiles
        set wallet_balance = wallet_balance + 500.0
        where id = ref_by;
    end if;

    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan,
       total_realized_pnl, referred_by, challenge_baseline_capital)
    values
      (new.id, v_email, v_name, initial_bal, true, 'free_starter', 0.0, ref_by,
       baseline);

    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (new.id, v_email, 'trigger', 'created');
  exception when others then
    insert into public.profile_provisioning_log(user_id, email, source, outcome, detail)
    values (new.id, v_email, 'trigger', 'error', sqlerrm);
  end;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION public.ensure_profile()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
declare
  uid uuid := auth.uid();
  v_email text;
  v_name text;
  v_guest boolean;
  v_bal numeric;
  v_created boolean := false;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from public.profiles where id = uid) then
    return false;
  end if;

  select email, raw_user_meta_data->>'name', coalesce(is_anonymous, false)
    into v_email, v_name, v_guest
  from auth.users where id = uid;

  v_email := coalesce(v_email, uid::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(v_name, ''),
                     nullif(split_part(coalesce(v_email, ''), '@', 1), ''),
                     'Titan');
  v_bal := case when coalesce(v_guest, false) then 500.0 else 1100.0 end;

  begin
    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan,
       total_realized_pnl, challenge_baseline_capital)
    values
      (uid, v_email, v_name, v_bal, true, 'free_starter', 0.0, v_bal)
    on conflict (id) do nothing;

    v_created := true;
    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (uid, v_email, 'self_heal', 'created');
  exception when others then
    insert into public.profile_provisioning_log(user_id, email, source, outcome, detail)
    values (uid, v_email, 'self_heal', 'error', sqlerrm);
    raise;
  end;

  return v_created;
end;
$$;

CREATE OR REPLACE FUNCTION public.convert_guest_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  c_guest_grant CONSTANT numeric := 500.0;
  c_full_grant  CONSTANT numeric := 1100.0;
  c_bonus       CONSTANT numeric := 600.0;
  uid uuid := auth.uid();
  v_email text;
  v_confirmed timestamptz;
  v_is_anon boolean;
  v_ident_name text;
  v_baseline numeric;
  v_converted timestamptz;
  v_paid numeric := 0;
  v_balance numeric;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT u.email,
         u.email_confirmed_at,
         coalesce(u.is_anonymous, false),
         coalesce(nullif(u.raw_user_meta_data->>'name', ''),
                  nullif(u.raw_user_meta_data->>'full_name', ''))
    INTO v_email, v_confirmed, v_is_anon, v_ident_name
    FROM auth.users u
   WHERE u.id = uid;

  IF v_email IS NULL OR v_email = '' OR v_email LIKE '%@guest.tradingtitans' THEN
    RETURN jsonb_build_object('converted', false, 'reason', 'no_identity');
  END IF;

  IF v_is_anon AND v_confirmed IS NULL THEN
    RETURN jsonb_build_object('converted', false, 'reason', 'not_verified');
  END IF;

  SELECT p.challenge_baseline_capital, p.converted_at
    INTO v_baseline, v_converted
    FROM public.profiles p
   WHERE p.id = uid
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('converted', false, 'reason', 'no_profile');
  END IF;

  IF v_converted IS NOT NULL THEN
    UPDATE public.profiles
       SET email = v_email
     WHERE id = uid
    RETURNING wallet_balance INTO v_balance;

    RETURN jsonb_build_object('converted', true, 'bonus', 0,
                              'already_converted', true, 'balance', v_balance);
  END IF;

  IF v_baseline <= c_guest_grant THEN
    v_paid := c_bonus;
    PERFORM set_config('app.wallet_reason', 'conversion_bonus', true);
  END IF;

  UPDATE public.profiles
     SET email = v_email,
         name = CASE WHEN name = 'Guest Titan'
                     THEN coalesce(v_ident_name,
                                   nullif(split_part(v_email, '@', 1), ''),
                                   name)
                     ELSE name END,
         wallet_balance = wallet_balance + v_paid,
         challenge_baseline_capital = c_full_grant,
         converted_at = now()
   WHERE id = uid
  RETURNING wallet_balance INTO v_balance;

  IF v_paid > 0 THEN
    INSERT INTO public.notifications (user_id, title, body, is_read, action_type)
    VALUES (uid,
            'Account upgraded 🎉',
            '₹' || to_char(c_bonus, 'FM999999999') ||
            ' upgrade bonus added to your demo wallet. All your trades came with you.',
            false,
            'wallet');
  END IF;

  RETURN jsonb_build_object('converted', true, 'bonus', v_paid, 'balance', v_balance);
END;
$$;
