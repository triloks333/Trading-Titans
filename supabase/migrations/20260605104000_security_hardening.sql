-- 1. Hardening Function Search Paths (function_search_path_mutable)
ALTER FUNCTION public.generate_referral_code() SET search_path = public;
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- 2. Restrict Security Definer Function execution (anon_security_definer_function_executable / authenticated_security_definer_function_executable)
-- Since public.handle_new_user is only meant to be run by the trigger (invoked by trigger on auth.users under postgres context),
-- we revoke permissions so users/anonymous clients cannot execute it directly via RPC.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- 3. Hardening RLS policies (rls_policy_always_true)
-- A. public.notifications: Remove broad "Anyone/authenticated can insert notifications" policy
DROP POLICY IF EXISTS "Anyone/authenticated can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
CREATE POLICY "Users can insert own notifications" ON public.notifications FOR INSERT WITH CHECK (auth.uid() = user_id);

-- B. public.rewards: Remove unrestricted insert policy
-- Users should never be allowed to insert rewards directly from the client.
DROP POLICY IF EXISTS "Admins/authenticated can insert rewards" ON public.rewards;

-- C. public.waitlist: Harden insert checks and remove broad list policy
DROP POLICY IF EXISTS "Allow public inserts" ON public.waitlist;
CREATE POLICY "Allow public inserts" ON public.waitlist 
    FOR INSERT 
    WITH CHECK (
        email IS NOT NULL AND 
        length(email) > 3 AND 
        email LIKE '%@%'
    );

-- Remove broad select policy that allowed public users to list all emails
DROP POLICY IF EXISTS "Allow users to view their status" ON public.waitlist;

-- 4. Harden Storage Bucket (public_bucket_allows_listing)
-- Drop the broad SELECT policy on support_attachments to prevent public listing of support files.
-- Because the bucket is public, files can still be accessed via direct URL, but listing files is blocked.
DROP POLICY IF EXISTS "Allow public read support_attachments" ON storage.objects;

-- 5. Harden backend token tables (rls_enabled_no_policy)
-- To resolve the lint warnings for tables that should only be accessed by the backend/service_role:
-- We explicitly define a "No access" RLS policy for the public/authenticated APIs.
-- This satisfies the linter while keeping the tables 100% blocked for all client-side requests.
-- (The service_role key automatically bypasses RLS, so the backend remains fully functional).

DROP POLICY IF EXISTS "Block public reads on fyers_tokens" ON public.fyers_tokens;
CREATE POLICY "Block public reads on fyers_tokens" ON public.fyers_tokens FOR ALL TO PUBLIC USING (false);

DROP POLICY IF EXISTS "Block public reads on upstox_states" ON public.upstox_states;
CREATE POLICY "Block public reads on upstox_states" ON public.upstox_states FOR ALL TO PUBLIC USING (false);

DROP POLICY IF EXISTS "Block public reads on upstox_tokens" ON public.upstox_tokens;
CREATE POLICY "Block public reads on upstox_tokens" ON public.upstox_tokens FOR ALL TO PUBLIC USING (false);
