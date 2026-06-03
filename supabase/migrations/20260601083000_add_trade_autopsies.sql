-- Create Trade Autopsies Table to store calculated heuristics feedback
CREATE TABLE public.trade_autopsies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL UNIQUE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    symbol TEXT NOT NULL,
    market TEXT NOT NULL,
    pnl NUMERIC NOT NULL,
    reason TEXT NOT NULL,
    advice TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.trade_autopsies ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own trade autopsies"
    ON public.trade_autopsies FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own trade autopsies"
    ON public.trade_autopsies FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own trade autopsies"
    ON public.trade_autopsies FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own trade autopsies"
    ON public.trade_autopsies FOR DELETE
    USING (auth.uid() = user_id);

-- Create index for performance
CREATE INDEX idx_trade_autopsies_user ON public.trade_autopsies(user_id);
CREATE INDEX idx_trade_autopsies_order ON public.trade_autopsies(order_id);
