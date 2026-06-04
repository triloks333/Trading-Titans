-- Create admin rewards / popups table
CREATE TABLE IF NOT EXISTS public.rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC NOT NULL,
    message TEXT NOT NULL,
    is_claimed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying unclaimed rewards
CREATE INDEX IF NOT EXISTS idx_rewards_unclaimed ON public.rewards(user_id) WHERE is_claimed = false;

-- Enable RLS
ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own rewards" ON public.rewards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own rewards" ON public.rewards FOR UPDATE USING (auth.uid() = user_id);
