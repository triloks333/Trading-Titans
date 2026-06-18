CREATE TABLE IF NOT EXISTS fo_instruments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_token    BIGINT NOT NULL,          
  exchange_token      BIGINT,
  tradingsymbol       TEXT NOT NULL,             
  exchange            TEXT NOT NULL,             
  underlying          TEXT NOT NULL,             
  instrument_type     TEXT NOT NULL,             
  expiry_date         DATE NOT NULL,
  strike_price        NUMERIC(10, 2) NOT NULL DEFAULT 0,
  lot_size            INTEGER NOT NULL,
  tick_size           NUMERIC(6, 2) NOT NULL DEFAULT 0.05,
  last_synced_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_fo_instrument UNIQUE (tradingsymbol, exchange)
);

CREATE INDEX IF NOT EXISTS idx_fo_inst_underlying_expiry ON fo_instruments (underlying, expiry_date);
CREATE INDEX IF NOT EXISTS idx_fo_inst_token ON fo_instruments (instrument_token);
CREATE INDEX IF NOT EXISTS idx_fo_inst_expiry_date ON fo_instruments (expiry_date);

ALTER TABLE fo_instruments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fo_instruments_read_authenticated"
  ON fo_instruments FOR SELECT
  TO authenticated
  USING (true);

-- App Config Table
CREATE TABLE IF NOT EXISTS app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO app_config (key, value) VALUES
  ('fo_seller_margin_pct', '0.15'),
  ('fo_future_margin_pct', '0.15')
ON CONFLICT (key) DO NOTHING;
