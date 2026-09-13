-- Guest → permanent account conversion.
--
-- Problem: guests were granted the same ₹11,000 as a registered user, so there
-- was no reason to ever create a real account. New guests now start at ₹5,000
-- and are offered the remaining ₹6,000 as a one-time bonus when they attach a
-- real identity (Google or email+password).
--
-- Nothing is migrated. Supabase converts an anonymous user in place: the row in
-- auth.users keeps the same id, so orders / holdings / fo_positions / rewards /
-- user_challenges / watchlist / price_alerts / wallet_transactions all follow
-- the account automatically. This migration only has to (a) grant less at
-- signup, (b) top up once at conversion, (c) nudge.
--
-- Money safety:
--   * The top-up is ADDITIVE (balance + 6000), never `balance = 11000`. Guests
--     have traded — at the time of writing one sits at ₹14,118 and another at
--     ₹29 — so an assignment would confiscate from one and reward the other.
--   * Paid at most once, guarded by profiles.converted_at, which is a real
--     column and not a lookup into wallet_transactions: that ledger's trigger
--     deliberately swallows its own errors, so it must never be load-bearing
--     for a money decision.
--   * The 44 guests created before this migration keep their ₹11,000 and are
--     NOT paid the bonus (they would land at ₹17,000). They are recognised by
--     challenge_baseline_capital = 11000, since only the new cohort is stamped
--     with 5000.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Conversion marker.
-- ─────────────────────────────────────────────────────────────────────────────
-- Serves three purposes: the one-shot guard for the bonus, the stop signal for
-- the upgrade nudges, and the restart of the referral-code window.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS converted_at TIMESTAMPTZ;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Signup grant: ₹5,000 for anonymous users, ₹11,000 for real ones.
-- ─────────────────────────────────────────────────────────────────────────────
-- Both grant paths are patched. handle_new_user() is the trigger, but it
-- swallows its own exceptions by design, and ensure_profile() is the client's
-- self-heal for exactly that case — it hardcoded 11000 too, so patching only
-- the trigger would have left a guest one failed insert away from the full
-- balance.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
declare
  ref_by uuid;
  is_guest boolean := coalesce(new.is_anonymous, false);
  initial_bal numeric := case when is_guest then 5000.0 else 11000.0 end;
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
      initial_bal := initial_bal + 5000.0;
      update public.profiles
        set wallet_balance = wallet_balance + 5000.0
        where id = ref_by;
    end if;

    -- challenge_baseline_capital is set explicitly: the column DEFAULT is
    -- 11000, which would leave a ₹5,000 guest needing a 44% return to clear
    -- the "20% of capital" milestone — harder than a registered user.
    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan,
       total_realized_pnl, referred_by, challenge_baseline_capital)
    values
      (new.id, v_email, v_name, initial_bal, true, 'free_starter', 0.0, ref_by,
       baseline);

    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (new.id, v_email, 'trigger', 'created');
  exception when others then
    -- Never abort the auth signup. Record the failure so it is visible, and
    -- the client's ensure_profile() self-heal recovers the user on next login.
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
    return false; -- already healthy, nothing to do
  end if;

  select email, raw_user_meta_data->>'name', coalesce(is_anonymous, false)
    into v_email, v_name, v_guest
  from auth.users where id = uid;

  v_email := coalesce(v_email, uid::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(v_name, ''),
                     nullif(split_part(coalesce(v_email, ''), '@', 1), ''),
                     'Titan');
  v_bal := case when coalesce(v_guest, false) then 5000.0 else 11000.0 end;

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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. The conversion itself.
-- ─────────────────────────────────────────────────────────────────────────────
-- Called by the app after supabase.auth.updateUser(email:) has been verified,
-- or after linkIdentity(google) returns. Takes no arguments on purpose: the
-- identity is read from auth.users, so the client cannot declare an email it
-- does not own.
--
-- Also syncs profiles.email/name. Nothing else does: the only trigger on
-- auth.users is AFTER INSERT, so without this the profile keeps its
-- <uuid>@guest.tradingtitans placeholder and the app goes on rendering
-- "Guest account" for a user who has just converted.
CREATE OR REPLACE FUNCTION public.convert_guest_account()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  c_guest_grant CONSTANT numeric := 5000.0;
  c_full_grant  CONSTANT numeric := 11000.0;
  c_bonus       CONSTANT numeric := 6000.0;
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

  -- No real identity attached yet. The placeholder domain can never receive a
  -- confirmation link, so it can never be a genuine conversion.
  IF v_email IS NULL OR v_email = '' OR v_email LIKE '%@guest.tradingtitans' THEN
    RETURN jsonb_build_object('converted', false, 'reason', 'no_identity');
  END IF;

  -- An email change that has not been clicked through is not a conversion.
  -- linkIdentity(google) clears is_anonymous outright, so that path passes
  -- here even before any email confirmation lands.
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

  -- Already converted. Keep the identity in sync (a user can change their email
  -- again later) but never pay a second time: link Google, unlink, link email
  -- would otherwise be worth ₹12,000.
  IF v_converted IS NOT NULL THEN
    UPDATE public.profiles
       SET email = v_email
     WHERE id = uid
    RETURNING wallet_balance INTO v_balance;

    RETURN jsonb_build_object('converted', true, 'bonus', 0,
                              'already_converted', true, 'balance', v_balance);
  END IF;

  -- Only the ₹5,000 cohort is topped up. Guests from before this migration
  -- already hold ₹11,000 and must not be pushed to ₹17,000.
  IF v_baseline = c_guest_grant THEN
    v_paid := c_bonus;
    -- Labels the wallet_transactions row the ledger trigger is about to write.
    PERFORM set_config('app.wallet_reason', 'conversion_bonus', true);
  END IF;

  UPDATE public.profiles
     SET email = v_email,
         -- Only ever replace the placeholder, so a display name the user chose
         -- themselves survives conversion.
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
            ' demo cash added. Your balance is now ₹' ||
            to_char(v_balance, 'FM999999999D00') ||
            '. Your account is permanent now — nothing is lost if you sign out.',
            false, 'reward');
  END IF;

  RETURN jsonb_build_object('converted', true, 'bonus', v_paid,
                            'already_converted', false, 'balance', v_balance);
END;
$$;

REVOKE ALL ON FUNCTION public.convert_guest_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.convert_guest_account() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Referral window runs from conversion, not signup.
-- ─────────────────────────────────────────────────────────────────────────────
-- Unchanged apart from the window: a guest is blocked from apply_referral_code
-- entirely, so by the time they are allowed to call it their 30 minutes from
-- signup are long gone and no converted user could ever use a code.
CREATE OR REPLACE FUNCTION public.apply_referral_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  uid uuid := auth.uid();
  v_existing uuid;
  v_created timestamptz;
  v_converted timestamptz;
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

  SELECT referred_by, created_at, converted_at
    INTO v_existing, v_created, v_converted
    FROM public.profiles
    WHERE id = uid
    FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'already_referred');
  END IF;

  IF coalesce(v_converted, v_created) < now() - interval '30 minutes' THEN
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
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Upgrade nudges, tapered.
-- ─────────────────────────────────────────────────────────────────────────────
-- Rides the existing pipe: inserting into public.notifications fires the
-- AFTER INSERT trigger that calls the push-notification function, so there is
-- no new plumbing and no edge function to redeploy. action_type 'guest_upgrade'
-- falls through channelFor()'s default to the broadcast channel, which is the
-- right home for a nudge.
--
-- Days 1, 3, 7 and 14 after signup, then weekly. Daily was the original ask and
-- is a Play policy risk plus a reliable source of one-star reviews; the taper
-- keeps the reach without the churn.
--
-- ponytail: day offsets are derived from full days elapsed, which is correct
-- only while the job runs once per day (each run advances the count by exactly
-- 1 whatever time of day the user signed up). If it ever needs to run more
-- often, record sent nudges in their own table instead of counting days.
CREATE OR REPLACE FUNCTION public.notify_guest_upgrade()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH due AS (
    SELECT p.id,
           p.challenge_baseline_capital AS baseline,
           floor(extract(epoch FROM (now() - p.created_at)) / 86400)::int AS days
      FROM public.profiles p
      JOIN auth.users u ON u.id = p.id
     WHERE coalesce(u.is_anonymous, false)
       AND p.converted_at IS NULL
  ),
  eligible AS (
    SELECT id, baseline
      FROM due
     WHERE (days IN (1, 3, 7, 14) OR (days > 14 AND (days - 14) % 7 = 0))
       -- Belt and braces against a manual re-run or a cron retry.
       AND NOT EXISTS (
             SELECT 1 FROM public.notifications n
              WHERE n.user_id = due.id
                AND n.action_type = 'guest_upgrade'
                AND n.created_at > now() - interval '20 hours')
  ),
  notif AS (
    INSERT INTO public.notifications (user_id, title, body, is_read, action_type)
    SELECT id,
           CASE WHEN baseline = 5000
                THEN 'You are missing ₹6,000'
                ELSE 'Do not lose your progress' END,
           CASE WHEN baseline = 5000
                THEN 'Guest accounts start with ₹5,000. Make your account permanent to unlock the full ₹11,000 and keep your portfolio forever — Profile → Make account permanent.'
                ELSE 'A guest account disappears the moment you sign out or reinstall, and it cannot be recovered. Make it permanent to keep your portfolio, rewards and streak — Profile → Make account permanent.' END,
           false, 'guest_upgrade'
      FROM eligible
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM eligible;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_guest_upgrade() FROM PUBLIC, anon, authenticated;

-- 12:00 UTC = 17:30 IST, after the Indian close.
--
-- Created INACTIVE on purpose. The nudge tells people to go to
-- "Profile → Make account permanent", which does not exist until the app build
-- carrying this feature is live on Play. Turn it on after the rollout with:
--
--   select cron.alter_job(
--     (select jobid from cron.job where jobname = 'notify-guest-upgrade'),
--     active := true);
DO $do$
DECLARE
  v_jobid bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('notify-guest-upgrade')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-guest-upgrade');

    v_jobid := cron.schedule(
      'notify-guest-upgrade',
      '0 12 * * *',
      $cron$ select public.notify_guest_upgrade(); $cron$
    );

    PERFORM cron.alter_job(v_jobid, active := false);
  END IF;
END
$do$;
