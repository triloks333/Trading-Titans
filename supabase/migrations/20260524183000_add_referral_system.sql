-- 1. Create a function to generate random 8-character unique referral code (prefixed with TT-)
CREATE OR REPLACE FUNCTION generate_referral_code() RETURNS TEXT AS $$
DECLARE
  chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  result TEXT := '';
  i INTEGER := 0;
BEGIN
  LOOP
    result := 'TT-';
    FOR i IN 1..6 LOOP
      result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    -- check if it already exists
    PERFORM 1 FROM public.profiles WHERE referral_code = result;
    IF NOT FOUND THEN
      RETURN result;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 2. Add columns to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES public.profiles(id);

-- Populate existing users with referral codes if they don't have one
UPDATE public.profiles SET referral_code = generate_referral_code() WHERE referral_code IS NULL;

-- Now make the column UNIQUE and NOT NULL
ALTER TABLE public.profiles ALTER COLUMN referral_code SET NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN referral_code SET DEFAULT generate_referral_code();

-- 3. Create referral_commissions table
CREATE TABLE IF NOT EXISTS public.referral_commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    referred_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    package_name TEXT NOT NULL,
    package_price NUMERIC NOT NULL,
    commission_amount NUMERIC NOT NULL,
    status TEXT NOT NULL DEFAULT 'unclaimed' CHECK (status IN ('unclaimed', 'claimed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Enable RLS on referral_commissions
ALTER TABLE public.referral_commissions ENABLE ROW LEVEL SECURITY;

-- 5. Policies for referral_commissions
DROP POLICY IF EXISTS "Users can view their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can view their own referral commissions" 
    ON public.referral_commissions 
    FOR SELECT 
    USING (auth.uid() = referrer_id);

DROP POLICY IF EXISTS "Users can update their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can update their own referral commissions" 
    ON public.referral_commissions 
    FOR UPDATE 
    USING (auth.uid() = referrer_id);
