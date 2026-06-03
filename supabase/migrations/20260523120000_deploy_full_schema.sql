-- Add missing columns
ALTER TABLE public.watchlist ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'executed';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS executed_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.holdings ADD COLUMN IF NOT EXISTS name TEXT;

-- Add UPDATE policies
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update their own profile') THEN
    CREATE POLICY "Users can update their own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'orders' AND policyname = 'Users can update their own orders') THEN
    CREATE POLICY "Users can update their own orders" ON orders FOR UPDATE USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'watchlist' AND policyname = 'Users can update their own watchlist') THEN
    CREATE POLICY "Users can update their own watchlist" ON watchlist FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END
$$;

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, wallet_balance, subscription_active, plan, total_realized_pnl, referred_by)
  VALUES (
    new.id, 
    new.email, 
    COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    11000.0, 
    true, 
    'free_starter', 
    0.0,
    (new.raw_user_meta_data->>'referred_by')::UUID
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
