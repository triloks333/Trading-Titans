-- Guest (anonymous) mode enablement + safety.
--
-- STEP A: make handle_new_user() tolerate anonymous users.
--   profiles.email and profiles.name are NOT NULL, but anonymous auth users
--   have a NULL email and no name metadata. Without this, signInAnonymously()
--   would fail the trigger and break guest sign-in. We synthesize a unique
--   placeholder email and a friendly default name. The referral logic is
--   unchanged (anonymous users never carry referred_by metadata).
--
-- STEP B: prevent the demo-cash / subscription / referral RPCs from being
--   abused by unlimited throwaway anonymous accounts. Real (registered) users
--   keep the beta top-up / purchase flow exactly as-is; guests must create a
--   real account before they can top up, buy a plan, or trigger a referral
--   payout. Detection uses the `is_anonymous` JWT claim Supabase sets.

-- ─── STEP A ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  ref_by UUID;
  initial_bal NUMERIC := 11000.0;
  v_email TEXT;
  v_name TEXT;
BEGIN
  ref_by := (new.raw_user_meta_data->>'referred_by')::UUID;

  IF ref_by IS NOT NULL THEN
    initial_bal := initial_bal + 5000.0;
    UPDATE public.profiles
      SET wallet_balance = wallet_balance + 5000.0
      WHERE id = ref_by;
  END IF;

  -- NOT NULL safe email (anonymous users have NULL email).
  v_email := COALESCE(new.email, new.id::text || '@guest.tradingtitans');

  -- NOT NULL safe display name with sensible fallbacks.
  v_name := COALESCE(
    NULLIF(new.raw_user_meta_data->>'name', ''),
    NULLIF(split_part(COALESCE(new.email, ''), '@', 1), ''),
    'Guest Titan'
  );

  INSERT INTO public.profiles (
    id, email, name, wallet_balance, subscription_active, plan,
    total_realized_pnl, referred_by
  )
  VALUES (
    new.id, v_email, v_name, initial_bal, true, 'free_starter', 0.0, ref_by
  );

  RETURN new;
END;
$function$;

-- ─── STEP B ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.credit_demo_cash(p_amount numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  uid uuid := auth.uid();
  new_balance numeric;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Guests must create an account to top up demo cash';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Invalid amount'; end if;
  if p_amount > 1000000 then raise exception 'Amount exceeds the maximum top-up of 1,000,000'; end if;
  update public.profiles
    set wallet_balance = wallet_balance + p_amount
    where id = uid
    returning wallet_balance into new_balance;
  return new_balance;
end;
$function$;

CREATE OR REPLACE FUNCTION public.activate_subscription(p_plan_id text)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  uid uuid := auth.uid();
  plan_cash numeric;
  new_balance numeric;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Guests must create an account to activate a plan';
  end if;
  plan_cash := case p_plan_id
                 when 'titan_5l' then 500000
                 when 'titan_pro' then 1000000
                 else 100000 end;
  update public.profiles
    set wallet_balance = wallet_balance + plan_cash,
        subscription_active = true,
        plan = p_plan_id
    where id = uid
    returning wallet_balance into new_balance;
  return new_balance;
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_referral_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_existing uuid;
  v_created timestamptz;
  v_referrer uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) THEN
    RAISE EXCEPTION 'Guests must create an account to use a referral code';
  END IF;

  IF p_code IS NULL OR length(btrim(p_code)) = 0 THEN
    RAISE EXCEPTION 'Invalid referral code';
  END IF;

  SELECT referred_by, created_at
    INTO v_existing, v_created
    FROM public.profiles
    WHERE id = uid
    FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'already_referred');
  END IF;

  IF v_created < now() - interval '30 minutes' THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'window_expired');
  END IF;

  SELECT id INTO v_referrer
    FROM public.profiles
    WHERE referral_code = upper(btrim(p_code));

  IF v_referrer IS NULL THEN
    RAISE EXCEPTION 'Invalid referral code';
  END IF;

  IF v_referrer = uid THEN
    RAISE EXCEPTION 'You cannot use your own referral code';
  END IF;

  UPDATE public.profiles
    SET referred_by = v_referrer,
        wallet_balance = wallet_balance + 5000.0
    WHERE id = uid;

  UPDATE public.profiles
    SET wallet_balance = wallet_balance + 5000.0
    WHERE id = v_referrer;

  RETURN jsonb_build_object('applied', true);
END;
$function$;
