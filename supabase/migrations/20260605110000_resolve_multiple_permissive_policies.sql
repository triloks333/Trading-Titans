-- Drop the redundant SELECT policy on public.profiles to resolve multiple_permissive_policies warning
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
