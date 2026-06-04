-- Update the check constraint on order_type to allow expiry_settlement
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_type_check;
ALTER TABLE orders ADD CONSTRAINT orders_order_type_check CHECK (order_type IN ('market', 'limit', 'expiry_settlement'));
