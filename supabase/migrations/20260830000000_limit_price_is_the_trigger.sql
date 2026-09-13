-- Make `limit_price` the single source of truth for a limit order's trigger.
--
-- `orders.price` is overloaded: it holds the limit while a row is pending, then
-- execute-pending-orders overwrites it with the fill price. `limit_price` was
-- added later to survive that overwrite, and the executor reads the trigger as
-- `limit_price ?? price`.
--
-- The app's modifyOrder wrote `price` alone, so editing a resting limit order
-- left the engine matching the ORIGINAL limit while the order card showed the
-- new one. AEROENTER sell 500 was placed at 149 and modified to 145.80: the
-- engine kept testing against 149, so an LTP of 146.03 correctly did not fill,
-- and the screen made that look like a broken matching engine.
--
-- The client fix is in app/lib/services/supabase_service.dart. This migration
-- repairs the rows that already diverged and stops a silent recurrence.

-- 1. Resting limit orders whose trigger disagrees with the displayed price.
--    The displayed price is what the user last asked for, so it wins.
update public.orders
   set limit_price = price
 where status = 'pending'
   and order_type = 'limit'
   and limit_price is distinct from price;

-- 2. Resting limit orders predating the column. Same reasoning: while a row is
--    pending, `price` IS the limit, so copying it forward loses nothing and
--    removes the executor's reliance on its `?? price` fallback.
update public.orders
   set limit_price = price
 where status = 'pending'
   and order_type = 'limit'
   and limit_price is null;

-- 3. A market order has no trigger to carry.
update public.orders
   set limit_price = null
 where order_type <> 'limit'
   and limit_price is not null;

-- Executed and cancelled rows are deliberately left alone: for an executed row
-- `price` is legitimately the fill price, and rewriting either column would be
-- falsifying trade history to make a constraint pass.

-- 4. A resting limit order must carry its trigger.
--    NOT VALID so the ~2,184 historic executed rows with a null limit_price are
--    not retro-checked; the constraint still applies to every insert and update
--    from here on, which is what actually needs guarding.
alter table public.orders
  drop constraint if exists orders_pending_limit_has_trigger;

alter table public.orders
  add constraint orders_pending_limit_has_trigger
  check (
    order_type <> 'limit'
    or status <> 'pending'
    or limit_price is not null
  ) not valid;

comment on column public.orders.limit_price is
  'The trigger price for a limit order; NULL for a market order. Source of truth: '
  '`price` holds the limit only while pending and is overwritten with the fill '
  'price on execution. Any writer that changes a resting order''s limit MUST '
  'update this column too.';
