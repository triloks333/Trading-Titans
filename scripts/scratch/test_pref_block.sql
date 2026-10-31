DO $$
BEGIN
  -- Test updating with EUR and pakistan_stock, italy_stock
  UPDATE public.profiles
     SET display_currency = 'EUR',
         preferred_markets = ARRAY['stock', 'pakistan_stock', 'italy_stock']
   WHERE id = 'bafab9da-751d-4f1e-ad38-bf8251a70c10';

  -- Revert
  UPDATE public.profiles
     SET display_currency = 'INR',
         preferred_markets = ARRAY['crypto', 'stock', 'us_stock']
   WHERE id = 'bafab9da-751d-4f1e-ad38-bf8251a70c10';
END $$;
SELECT 1 as test_passed;
