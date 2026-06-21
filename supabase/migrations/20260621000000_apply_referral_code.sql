-- Apply a referral code AFTER signup (needed for Google/OAuth signups, where
-- we cannot pass `referred_by` in the auth signUp metadata the way the
-- email/password flow does via handle_new_user()).
--
-- Safety properties:
--   * SECURITY DEFINER with a pinned search_path.
--   * Operates only on the calling user (auth.uid()).
--   * Idempotent: only applies when the caller's profile has referred_by IS NULL,
--     so it can never double-credit an email signup that was already referred
--     by the handle_new_user() trigger.
--   * Locks the caller's profile row (FOR UPDATE) to avoid races.
--   * Rejects self-referral and codes that don't resolve to a real profile.
--   * Only valid within 30 minutes of account creation (new-signup intent),
--     so it cannot be used to retro-claim referrals on aged accounts.
--   * Mirrors the existing reward: +5000 to the new user and +5000 to referrer.

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

  IF p_code IS NULL OR length(btrim(p_code)) = 0 THEN
    RAISE EXCEPTION 'Invalid referral code';
  END IF;

  -- Lock the caller's profile and read current state.
  SELECT referred_by, created_at
    INTO v_existing, v_created
    FROM public.profiles
    WHERE id = uid
    FOR UPDATE;

  -- Already referred (e.g. email signup handled by handle_new_user): no-op.
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'already_referred');
  END IF;

  -- Only honor referral intent for freshly created accounts.
  IF v_created < now() - interval '30 minutes' THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'window_expired');
  END IF;

  -- Resolve the referrer by code (codes are stored upper-cased).
  SELECT id INTO v_referrer
    FROM public.profiles
    WHERE referral_code = upper(btrim(p_code));

  IF v_referrer IS NULL THEN
    RAISE EXCEPTION 'Invalid referral code';
  END IF;

  IF v_referrer = uid THEN
    RAISE EXCEPTION 'You cannot use your own referral code';
  END IF;

  -- Apply: link referrer and credit both sides, matching the email flow.
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

-- Only signed-in users may call it; never anon.
REVOKE ALL ON FUNCTION public.apply_referral_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_referral_code(text) TO authenticated;
