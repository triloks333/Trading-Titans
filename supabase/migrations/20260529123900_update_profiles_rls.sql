-- Allow public read of profiles for leaderboards and referral registrations
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can read profiles" ON public.profiles;

CREATE POLICY "Anyone can read profiles" 
ON public.profiles 
FOR SELECT 
USING (true);
