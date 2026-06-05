-- 1. Enable pg_cron and http extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS http;

-- 2. Drop unused tables
DROP TABLE IF EXISTS public.upstox_tokens CASCADE;
DROP TABLE IF EXISTS public.upstox_states CASCADE;

-- 3. Create crypto_coins
CREATE TABLE IF NOT EXISTS public.crypto_coins (
    symbol TEXT PRIMARY KEY,
    base_currency TEXT NOT NULL,
    quote_currency TEXT NOT NULL,
    min_quantity NUMERIC,
    max_quantity NUMERIC,
    min_price NUMERIC,
    step NUMERIC,
    order_types TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.crypto_coins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read crypto_coins" ON public.crypto_coins;
CREATE POLICY "Anyone can read crypto_coins" ON public.crypto_coins FOR SELECT USING (true);

-- 4. Create crypto_prices
CREATE TABLE IF NOT EXISTS public.crypto_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol TEXT NOT NULL,
    price NUMERIC NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.crypto_prices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read crypto_prices" ON public.crypto_prices;
CREATE POLICY "Anyone can read crypto_prices" ON public.crypto_prices FOR SELECT USING (true);

-- 5. Create tick_data
CREATE TABLE IF NOT EXISTS public.tick_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol TEXT NOT NULL,
    price NUMERIC NOT NULL,
    volume NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.tick_data ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read tick_data" ON public.tick_data;
CREATE POLICY "Anyone can read tick_data" ON public.tick_data FOR SELECT USING (true);

-- 6. Create pnl_history (required for snapshot-pnl)
CREATE TABLE IF NOT EXISTS public.pnl_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    market TEXT NOT NULL, -- 'equity' | 'crypto'
    total_pnl NUMERIC NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.pnl_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own pnl_history" ON public.pnl_history;
CREATE POLICY "Users can view own pnl_history" ON public.pnl_history FOR SELECT USING (true);

-- 7. Create ws_health (required for health check edge functions)
CREATE TABLE IF NOT EXISTS public.ws_health (
    id TEXT PRIMARY KEY, -- 'equity' | 'crypto'
    last_tick_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reconnect_required BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.ws_health ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read ws_health" ON public.ws_health;
CREATE POLICY "Anyone can read ws_health" ON public.ws_health FOR SELECT USING (true);

-- 8. Create fo_expiry_config (required for update-expiry-dates)
CREATE TABLE IF NOT EXISTS public.fo_expiry_config (
    symbol TEXT PRIMARY KEY, -- 'NIFTY', 'BANKNIFTY', 'FINNIFTY'
    weekly_expiry DATE,
    monthly_expiry DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.fo_expiry_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read fo_expiry_config" ON public.fo_expiry_config;
CREATE POLICY "Anyone can read fo_expiry_config" ON public.fo_expiry_config FOR SELECT USING (true);

-- 9. Create crypto_holdings
CREATE TABLE IF NOT EXISTS public.crypto_holdings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    symbol TEXT NOT NULL, -- e.g. BTCINR
    quantity NUMERIC NOT NULL,
    avg_price NUMERIC NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.crypto_holdings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can view own crypto_holdings" ON public.crypto_holdings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Users can insert own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can insert own crypto_holdings" ON public.crypto_holdings FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Users can update own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can update own crypto_holdings" ON public.crypto_holdings FOR UPDATE USING (true);
DROP POLICY IF EXISTS "Users can delete own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can delete own crypto_holdings" ON public.crypto_holdings FOR DELETE USING (true);

-- 10. Standalone user_id indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rewards_user_id ON public.rewards(user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_crypto_holdings_user_id ON public.crypto_holdings(user_id);

-- 11. created_at DESC indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_holdings_created_at ON public.holdings(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_watchlist_created_at ON public.watchlist(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_trade_autopsies_created_at ON public.trade_autopsies(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_tickets_created_at ON public.support_tickets(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rewards_created_at ON public.rewards(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_referral_commissions_created_at ON public.referral_commissions(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pnl_history_user_created ON public.pnl_history(user_id, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_crypto_holdings_created_at ON public.crypto_holdings(created_at DESC);

-- 12. Composite / Specific indexes for orders
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_status ON public.orders(user_id, status);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_symbol ON public.orders(user_id, symbol);

-- 13. Alter instruments table to add Fyers CM/FO master fields if not present
ALTER TABLE public.instruments 
ADD COLUMN IF NOT EXISTS exchange TEXT,
ADD COLUMN IF NOT EXISTS segment TEXT,
ADD COLUMN IF NOT EXISTS tick_size NUMERIC,
ADD COLUMN IF NOT EXISTS expiry TEXT;

-- 14. Indexes for instruments
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instruments_exchange ON public.instruments(exchange, segment);

-- 15. Indexes for crypto
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_crypto_prices_symbol_time ON public.crypto_prices(symbol, created_at DESC);

-- 16. Security definer auth function
CREATE OR REPLACE FUNCTION public.auth_uid() 
RETURNS uuid 
LANGUAGE sql STABLE SECURITY DEFINER
AS $$ SELECT auth.uid() $$;

-- 17. Optimize all RLS policies with auth_uid()
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (public.auth_uid() = id);

DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
CREATE POLICY "Users can view own orders" ON public.orders FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own orders" ON public.orders;
CREATE POLICY "Users can insert own orders" ON public.orders FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own orders" ON public.orders;
CREATE POLICY "Users can update their own orders" ON public.orders FOR UPDATE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own holdings" ON public.holdings;
CREATE POLICY "Users can view own holdings" ON public.holdings FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own holdings" ON public.holdings;
CREATE POLICY "Users can insert own holdings" ON public.holdings FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update own holdings" ON public.holdings;
CREATE POLICY "Users can update own holdings" ON public.holdings FOR UPDATE USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own holdings" ON public.holdings;
CREATE POLICY "Users can delete own holdings" ON public.holdings FOR DELETE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own watchlist" ON public.watchlist;
CREATE POLICY "Users can view own watchlist" ON public.watchlist FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own watchlist" ON public.watchlist;
CREATE POLICY "Users can insert own watchlist" ON public.watchlist FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own watchlist" ON public.watchlist;
CREATE POLICY "Users can update their own watchlist" ON public.watchlist FOR UPDATE USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own watchlist" ON public.watchlist;
CREATE POLICY "Users can delete own watchlist" ON public.watchlist FOR DELETE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can view their own referral commissions" ON public.referral_commissions FOR SELECT USING (public.auth_uid() = referrer_id);
DROP POLICY IF EXISTS "Users can update their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can update their own referral commissions" ON public.referral_commissions FOR UPDATE USING (public.auth_uid() = referrer_id);

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
CREATE POLICY "Users can insert own notifications" ON public.notifications FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications FOR UPDATE USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
CREATE POLICY "Users can delete own notifications" ON public.notifications FOR DELETE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can view own trade autopsies" ON public.trade_autopsies FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can insert own trade autopsies" ON public.trade_autopsies FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can update own trade autopsies" ON public.trade_autopsies FOR UPDATE USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can delete own trade autopsies" ON public.trade_autopsies FOR DELETE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Select support tickets" ON public.support_tickets;
CREATE POLICY "Select support tickets" ON public.support_tickets FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Insert support tickets" ON public.support_tickets;
CREATE POLICY "Insert support tickets" ON public.support_tickets FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Update support tickets" ON public.support_tickets;
CREATE POLICY "Update support tickets" ON public.support_tickets FOR UPDATE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own rewards" ON public.rewards;
CREATE POLICY "Users can view own rewards" ON public.rewards FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update own rewards" ON public.rewards;
CREATE POLICY "Users can update own rewards" ON public.rewards FOR UPDATE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can view own crypto_holdings" ON public.crypto_holdings FOR SELECT USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can insert own crypto_holdings" ON public.crypto_holdings FOR INSERT WITH CHECK (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can update own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can update own crypto_holdings" ON public.crypto_holdings FOR UPDATE USING (public.auth_uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own crypto_holdings" ON public.crypto_holdings;
CREATE POLICY "Users can delete own crypto_holdings" ON public.crypto_holdings FOR DELETE USING (public.auth_uid() = user_id);

DROP POLICY IF EXISTS "Users can view own pnl_history" ON public.pnl_history;
CREATE POLICY "Users can view own pnl_history" ON public.pnl_history FOR SELECT USING (public.auth_uid() = user_id);

-- 18. Configure Supabase Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

ALTER PUBLICATION supabase_realtime SET TABLE public.orders, public.holdings, public.watchlist, public.notifications, public.crypto_holdings;
