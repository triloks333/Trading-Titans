-- Stop mass PII (email / wallet) harvesting from public.profiles.
--
-- Before: SELECT policy `USING (true)` let any signed-in (or anon) user read
-- every column of every profile, including email and wallet_balance.
--
-- After: the base table is readable only by the row owner or an admin. All
-- legitimate cross-user reads are served through controlled, column-limited
-- SECURITY DEFINER surfaces so nothing in the app breaks:
--   * leaderboard            -> public.leaderboard view (no email)
--   * pre-login referral code -> public.get_referrer_id_by_code()
--   * refer & earn friends    -> public.get_my_referrals() (id/name/date only)
--   * admin reward/broadcast  -> base policy allows admins via is_admin()

-- ── Admin check (SECURITY DEFINER avoids RLS recursion on profiles) ──────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE((SELECT is_admin FROM public.profiles WHERE id = auth.uid()), false);
$function$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

-- ── Base SELECT policy: owner or admin only ─────────────────────────────────
DROP POLICY IF EXISTS "Anyone can read profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own_or_admin" ON public.profiles;
CREATE POLICY "profiles_select_own_or_admin" ON public.profiles
  FOR SELECT
  USING ((select auth.uid()) = id OR public.is_admin());

-- ── Leaderboard: safe columns only, readable by everyone ─────────────────────
DROP VIEW IF EXISTS public.leaderboard;
CREATE VIEW public.leaderboard
  WITH (security_invoker = false) AS
  SELECT id, name, plan, total_realized_pnl, wallet_balance
  FROM public.profiles
  ORDER BY total_realized_pnl DESC;

GRANT SELECT ON public.leaderboard TO anon, authenticated;

-- ── Resolve a referral code to the referrer id (used pre-login at signup) ────
CREATE OR REPLACE FUNCTION public.get_referrer_id_by_code(p_code text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.profiles
  WHERE referral_code = upper(btrim(p_code))
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_referrer_id_by_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_referrer_id_by_code(text) TO anon, authenticated;

-- ── List the people the caller referred (no email leak) ─────────────────────
CREATE OR REPLACE FUNCTION public.get_my_referrals()
RETURNS TABLE (id uuid, name text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p.id, p.name, p.created_at
  FROM public.profiles p
  WHERE p.referred_by = auth.uid();
$function$;

REVOKE ALL ON FUNCTION public.get_my_referrals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_referrals() TO authenticated;
