-- Drop the holdings quantity > 0 check constraint to support short/negative holdings (e.g., short selling futures/options)
ALTER TABLE public.holdings DROP CONSTRAINT IF EXISTS holdings_quantity_check;
