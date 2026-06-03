-- Migration: Add Options Columns to Orders, Holdings, and Watchlist
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS instrument_type TEXT NOT NULL DEFAULT 'EQUITY';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS strike_price NUMERIC;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS option_type TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS expiry_date TEXT;

ALTER TABLE public.holdings ADD COLUMN IF NOT EXISTS instrument_type TEXT NOT NULL DEFAULT 'EQUITY';
ALTER TABLE public.holdings ADD COLUMN IF NOT EXISTS strike_price NUMERIC;
ALTER TABLE public.holdings ADD COLUMN IF NOT EXISTS option_type TEXT;
ALTER TABLE public.holdings ADD COLUMN IF NOT EXISTS expiry_date TEXT;

ALTER TABLE public.watchlist ADD COLUMN IF NOT EXISTS instrument_type TEXT NOT NULL DEFAULT 'EQUITY';
ALTER TABLE public.watchlist ADD COLUMN IF NOT EXISTS strike_price NUMERIC;
ALTER TABLE public.watchlist ADD COLUMN IF NOT EXISTS option_type TEXT;
ALTER TABLE public.watchlist ADD COLUMN IF NOT EXISTS expiry_date TEXT;
