ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'executed' CHECK (status IN ('executed', 'pending', 'cancelled'));
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS executed_at TIMESTAMPTZ;
