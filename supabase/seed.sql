-- Seed: Create demo holdings for any user who has no holdings
-- This gives new users instant Groww/Zerodha-like portfolio data

-- Insert sample holdings for a new user (run once after signup)
-- Replace USER_UUID_HERE with the actual user UUID from auth.users
-- Or use this as a template to insert your own demo holdings

-- Demo holdings for a user (replace with actual user ID):
-- INSERT INTO public.holdings (user_id, symbol, market, quantity, avg_price, name) VALUES
--   ('USER_UUID_HERE', 'RELIANCE', 'stock', 10, 2850.00, 'Reliance Industries Ltd.'),
--   ('USER_UUID_HERE', 'TCS', 'stock', 5, 3890.00, 'Tata Consultancy Services Ltd.'),
--   ('USER_UUID_HERE', 'HDFCBANK', 'stock', 15, 1680.00, 'HDFC Bank Ltd.'),
--   ('USER_UUID_HERE', 'INFY', 'stock', 20, 1560.00, 'Infosys Ltd.'),
--   ('USER_UUID_HERE', 'ICICIBANK', 'stock', 25, 1120.00, 'ICICI Bank Ltd.'),
--   ('USER_UUID_HERE', 'bitcoin', 'crypto', 0.025, 5200000.00, 'Bitcoin'),
--   ('USER_UUID_HERE', 'ethereum', 'crypto', 0.5, 310000.00, 'Ethereum'),
--   ('USER_UUID_HERE', 'TATAMOTORS', 'stock', 50, 780.00, 'Tata Motors Ltd.'),
--   ('USER_UUID_HERE', 'WIPRO', 'stock', 30, 540.00, 'Wipro Ltd.'),
--   ('USER_UUID_HERE', 'HINDUNILVR', 'stock', 8, 2650.00, 'Hindustan Unilever Ltd.');

-- Or use this function to auto-seed new users:
CREATE OR REPLACE FUNCTION public.seed_demo_holdings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.holdings (user_id, symbol, market, quantity, avg_price, name) VALUES
    (NEW.id, 'RELIANCE', 'stock', 10, 2850.00, 'Reliance Industries Ltd.'),
    (NEW.id, 'TCS', 'stock', 5, 3890.00, 'Tata Consultancy Services Ltd.'),
    (NEW.id, 'HDFCBANK', 'stock', 15, 1680.00, 'HDFC Bank Ltd.'),
    (NEW.id, 'INFY', 'stock', 20, 1560.00, 'Infosys Ltd.'),
    (NEW.id, 'ICICIBANK', 'stock', 25, 1120.00, 'ICICI Bank Ltd.'),
    (NEW.id, 'bitcoin', 'crypto', 0.025, 5200000.00, 'Bitcoin'),
    (NEW.id, 'ethereum', 'crypto', 0.5, 310000.00, 'Ethereum'),
    (NEW.id, 'TATAMOTORS', 'stock', 50, 780.00, 'Tata Motors Ltd.'),
    (NEW.id, 'WIPRO', 'stock', 30, 540.00, 'Wipro Ltd.'),
    (NEW.id, 'HINDUNILVR', 'stock', 8, 2650.00, 'Hindustan Unilever Ltd.');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Silently ignore (duplicates, etc.)
  RETURN NEW;
END;
$$;

-- Uncomment to auto-seed all NEW users on signup:
-- DROP TRIGGER IF EXISTS on_profile_created ON public.profiles;
-- CREATE TRIGGER on_profile_created
--   AFTER INSERT ON public.profiles
--   FOR EACH ROW
--   EXECUTE FUNCTION public.seed_demo_holdings();
