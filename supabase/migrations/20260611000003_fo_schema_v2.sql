CREATE TABLE IF NOT EXISTS fo_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  symbol TEXT NOT NULL,
  instrument_type TEXT NOT NULL DEFAULT 'OPTION',
  option_type TEXT DEFAULT '',
  strike_price NUMERIC(10, 2) DEFAULT 0,
  lot_size INTEGER NOT NULL DEFAULT 1,
  expiry_date DATE,
  net_qty INTEGER NOT NULL DEFAULT 0,
  avg_entry_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
  margin_blocked NUMERIC(12, 2) NOT NULL DEFAULT 0,
  is_settled BOOLEAN NOT NULL DEFAULT FALSE,
  settlement_price NUMERIC(12, 2),
  realized_pnl NUMERIC(12, 2),
  settled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Backfill or safe alterations for safety/compatibility
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS instrument_type TEXT NOT NULL DEFAULT 'OPTION';
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS option_type TEXT DEFAULT '';
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS strike_price NUMERIC(10, 2) DEFAULT 0;
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS lot_size INTEGER NOT NULL DEFAULT 1;

-- Expiry Date Nullable first (already nullable/created, but keep matching comments)
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS expiry_date DATE;
UPDATE fo_positions SET expiry_date = CURRENT_DATE WHERE expiry_date IS NULL;
ALTER TABLE fo_positions ALTER COLUMN expiry_date SET NOT NULL;

ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS net_qty INTEGER NOT NULL DEFAULT 0;
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS avg_entry_price NUMERIC(12, 2) NOT NULL DEFAULT 0;
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS margin_blocked NUMERIC(12, 2) NOT NULL DEFAULT 0;
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS is_settled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS settlement_price NUMERIC(12, 2);
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS realized_pnl NUMERIC(12, 2);
ALTER TABLE fo_positions ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uq_fo_position
  ON fo_positions (user_id, symbol, instrument_type, option_type, strike_price, expiry_date)
  WHERE is_settled = FALSE;

CREATE TABLE IF NOT EXISTS realized_pnl_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  position_id UUID REFERENCES fo_positions(id),
  pnl_amount NUMERIC(12, 2) NOT NULL,
  pnl_type TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
