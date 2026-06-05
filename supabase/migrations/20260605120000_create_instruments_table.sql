-- Enable pg_trgm extension for fast text matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create instruments table to store Fyers symbol masters
CREATE TABLE IF NOT EXISTS public.instruments (
    fyers_token TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    name TEXT NOT NULL,
    market TEXT NOT NULL, -- 'stock' | 'future' | 'option'
    instrument_type TEXT NOT NULL, -- 'EQUITY' | 'FUTURE' | 'OPTION'
    expiry_date TEXT, -- YYYY-MM-DD
    strike_price NUMERIC,
    option_type TEXT, -- 'CE' | 'PE'
    lot_size NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS on the instruments table
ALTER TABLE public.instruments ENABLE ROW LEVEL SECURITY;

-- Allow anyone to read instruments
DROP POLICY IF EXISTS "Anyone can read instruments" ON public.instruments;
CREATE POLICY "Anyone can read instruments" ON public.instruments 
    FOR SELECT USING (true);

-- Create indexes for fast search queries
CREATE INDEX IF NOT EXISTS idx_instruments_symbol ON public.instruments(symbol);
CREATE INDEX IF NOT EXISTS idx_instruments_market_symbol ON public.instruments(market, symbol);
CREATE INDEX IF NOT EXISTS idx_instruments_name_trgm ON public.instruments USING gin (name gin_trgm_ops) WHERE name IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_instruments_symbol_trgm ON public.instruments USING gin (symbol gin_trgm_ops);
