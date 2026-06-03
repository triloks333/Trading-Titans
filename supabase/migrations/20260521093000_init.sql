-- Migration from MongoDB to Supabase PostgreSQL

-- 1. Profiles Table (extends auth.users)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    wallet_balance NUMERIC NOT NULL DEFAULT 11000.0,
    subscription_active BOOLEAN NOT NULL DEFAULT true,
    plan TEXT NOT NULL DEFAULT 'free_starter',
    total_realized_pnl NUMERIC NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Orders Table
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    symbol TEXT NOT NULL,
    name TEXT,
    market TEXT NOT NULL,
    side TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
    quantity NUMERIC NOT NULL CHECK (quantity > 0),
    price NUMERIC NOT NULL,
    total NUMERIC NOT NULL,
    realized_pnl NUMERIC NOT NULL DEFAULT 0.0,
    status TEXT NOT NULL DEFAULT 'executed' CHECK (status IN ('executed', 'pending', 'cancelled')),
    order_type TEXT NOT NULL DEFAULT 'market' CHECK (order_type IN ('market', 'limit')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_orders_user_created ON public.orders(user_id, created_at DESC);

-- 3. Holdings Table
CREATE TABLE public.holdings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    symbol TEXT NOT NULL,
    market TEXT NOT NULL,
    quantity NUMERIC NOT NULL CHECK (quantity > 0),
    avg_price NUMERIC NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, symbol, market)
);

-- 4. Watchlist Table
CREATE TABLE public.watchlist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    symbol TEXT NOT NULL,
    market TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, symbol, market)
);

-- 5. Upstox Token Table
CREATE TABLE public.upstox_tokens (
    id TEXT PRIMARY KEY DEFAULT 'main',
    access_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Upstox State Table (for OAuth flow)
CREATE TABLE public.upstox_states (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Set up Row Level Security (RLS)

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holdings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.upstox_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.upstox_states ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read their own profile, update their own profile (with restrictions)
CREATE POLICY "Users can read own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

-- Orders: users can only see and create their own orders
CREATE POLICY "Users can view own orders"
    ON public.orders FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Holdings: users can view and manage their own holdings
CREATE POLICY "Users can view own holdings"
    ON public.holdings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own holdings"
    ON public.holdings FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own holdings"
    ON public.holdings FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own holdings"
    ON public.holdings FOR DELETE
    USING (auth.uid() = user_id);

-- Watchlist: users can manage their own watchlist
CREATE POLICY "Users can view own watchlist"
    ON public.watchlist FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own watchlist"
    ON public.watchlist FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own watchlist"
    ON public.watchlist FOR DELETE
    USING (auth.uid() = user_id);

-- Upstox token and states: Only accessible by service role (backend edge functions)
-- No RLS policies for public access to these tables.
