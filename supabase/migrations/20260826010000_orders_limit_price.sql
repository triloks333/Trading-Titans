-- Give a limit order its own column for the price the user actually asked for.
--
-- `orders.price` does double duty: it holds the limit while the order is pending,
-- then the execution engine overwrites it with the fill price
-- (execute-pending-orders: `.update({ status: "executed", price: execPrice, ... })`).
-- Once an order filled there was no record anywhere that the user had asked for
-- 281 — which is why an "Order Pending ₹281.00" notification could be followed by
-- a "Sell Order Executed ... at ₹281.4" one and nothing could reconcile the two.
--
-- The resting-limit fix in execute-pending-orders now makes fill == limit for
-- resting orders, so this is an audit/history concern rather than a money one.
-- It still matters for market orders and for genuinely marketable limit orders,
-- where price improvement means the two values legitimately differ.
--
-- Additive and nullable: every existing read of `price` keeps working untouched.
alter table public.orders
  add column if not exists limit_price numeric;

comment on column public.orders.limit_price is
  'Price the user requested for a limit order, stamped at placement and never overwritten. NULL for market orders. `price` holds the limit while pending and the actual fill price once executed.';

-- Backfill ONLY still-pending limit orders, where `price` is provably still the
-- untouched limit.
--
-- Already-executed rows are deliberately left NULL: their `price` is the fill,
-- the original limit was overwritten at execution and is not recoverable. Copying
-- price into limit_price there would fabricate an audit trail that says the user
-- asked for exactly what they got, which is the very confusion this column
-- exists to prevent.
update public.orders
set limit_price = price
where order_type = 'limit'
  and status = 'pending'
  and limit_price is null;
