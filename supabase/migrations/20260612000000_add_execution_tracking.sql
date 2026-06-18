-- Add audit tracking to orders
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS execution_price_source TEXT,
ADD COLUMN IF NOT EXISTS execution_reference_price NUMERIC,
ADD COLUMN IF NOT EXISTS nse_contract_date DATE;

-- Table for daily bhavcopy price snapshot
CREATE TABLE IF NOT EXISTS public.nse_fo_bhavcopy (
    symbol TEXT NOT NULL,
    expiry_date DATE NOT NULL,
    strike_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
    option_type TEXT NOT NULL DEFAULT 'XX',
    trading_symbol TEXT NOT NULL,
    open_price NUMERIC(12, 2),
    high_price NUMERIC(12, 2),
    low_price NUMERIC(12, 2),
    close_price NUMERIC(12, 2),
    last_price NUMERIC(12, 2),
    settle_price NUMERIC(12, 2),
    lot_size INTEGER,
    prev_close NUMERIC(12, 2),
    volume_value NUMERIC(15, 2),
    open_interest BIGINT,
    trading_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (trading_symbol, trading_date)
);

CREATE INDEX IF NOT EXISTS idx_bhavcopy_symbol_expiry ON public.nse_fo_bhavcopy (symbol, expiry_date);
