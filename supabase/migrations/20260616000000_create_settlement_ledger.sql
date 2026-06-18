-- Migration: Create settlement_ledger table and enable RLS
CREATE TABLE IF NOT EXISTS settlement_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  position_id UUID,
  symbol TEXT NOT NULL,
  instrument_type TEXT NOT NULL,
  option_type TEXT,
  strike_price NUMERIC(10, 2),
  expiry_date DATE NOT NULL,
  quantity NUMERIC(12, 2) NOT NULL,
  avg_price NUMERIC(12, 2) NOT NULL,
  settlement_type TEXT NOT NULL,
  intrinsic_value NUMERIC(12, 2) NOT NULL,
  premium_received NUMERIC(12, 2) NOT NULL,
  margin_released NUMERIC(12, 2) NOT NULL,
  wallet_change NUMERIC(12, 2) NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE settlement_ledger ENABLE ROW LEVEL SECURITY;

-- Select Policy: Users can view only their own records
CREATE POLICY "Users can view their own settlements"
  ON settlement_ledger FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Insert Policy: Users can insert only their own records
CREATE POLICY "Users can insert their own settlements"
  ON settlement_ledger FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
