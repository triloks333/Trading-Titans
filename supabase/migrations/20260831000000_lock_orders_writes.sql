-- Make the server the only writer of money on `orders`.
--
-- THE HOLE (verified exploitable before writing this)
-- The UPDATE policy was:
--     "Users can update their own orders"  USING (auth_uid() = user_id)
-- with no WITH CHECK and no column restriction, and `authenticated` held table
-- level UPDATE. RLS cannot restrict columns, so this granted a signed-in user
-- the right to set ANY column on their own order rows. No exploit was needed;
-- it was the documented API surface of the table. Confirmed by impersonating a
-- real user's role and JWT claims in a rolled-back transaction:
--
--     update orders set realized_pnl = 999999, status = 'executed' where id = ...
--     -> 1 row, status 'executed', realized_pnl 999999
--
-- `realized_pnl` feeds analytics, trade autopsy and order history; `status` and
-- `quantity` are what the execution engine reads. INSERT had the same shape, so
-- locking only UPDATE would leave a fabricated executed row one call away.
--
-- WHAT REPLACES IT
-- Edge functions running as service_role, which validate ownership and order
-- state and write only the fields an edit may touch:
--   * cancel-order   pending -> cancelled, compare-and-swap on status
--   * modify-order   quantity / price / limit_price / total, recomputed server-side
-- Rules and their 19 tests: supabase/functions/_shared/order_edit{,_test}.ts
--
-- WHY THIS KEEPS A NARROW UPDATE PATH INSTEAD OF REVOKING OUTRIGHT
-- The Android app ships through Play and cannot be force-updated. Revoking UPDATE
-- outright would break Cancel for every already-installed build, permanently, for
-- users who never update. So this migration:
--   * removes column-level access to every financial and state field, and
--   * keeps exactly one legal client transition, pending -> cancelled, on exactly
--     one column, `status`.
-- A stale client's Cancel therefore still works. Its Modify stops working and
-- reports a permission error, which is visible rather than silent, and the
-- current app build already routes Modify through modify-order.
-- Once release adoption is high, 20260831000100_finish_orders_lockdown.sql drops
-- even this and makes cancel-order the only path.
--
-- UNAFFECTED
--   * Reading orders: SELECT policy and grant untouched.
--   * place-order, execute-pending-orders, settle-expired-positions and every
--     cron: all service_role, which RLS and these revokes do not apply to.
--   * The trigger comparison, the fill-price rule, the claim/CAS idempotency.
--
-- STOPS WORKING
--   * The legacy on-device execution paths in supabase_service.dart, which write
--     order and money rows from the phone. Already inert behind
--     `_serverExecOnly = true` / `_useServerPlaceOrder = true`, whose own comment
--     says they must stay true once this lockdown lands. Flipping one back now
--     fails at the database instead of silently writing. Intended end state of
--     the server-trust migration, not a regression.

-- 1. Drop the blanket write policies.
drop policy if exists "Users can update their own orders" on public.orders;
drop policy if exists "Users can insert own orders" on public.orders;

-- 2. Take away table-wide write access, then hand back the single column a
--    client is allowed to touch. This is the part RLS cannot express: with a
--    column-level grant, `realized_pnl`, `quantity`, `price`, `limit_price`,
--    `total`, `user_id`, `created_at`, `executed_at`, `execution_price_source`
--    and `execution_reference_price` are unreachable from a client at all.
revoke insert, update on public.orders from authenticated;
revoke insert, update on public.orders from anon;

grant update (status) on public.orders to authenticated;

-- 3. And constrain the one column to the one legal transition. USING sees the
--    existing row, WITH CHECK sees the proposed one, so together they permit
--    pending -> cancelled and nothing else: not pending -> executed, not
--    cancelled -> pending, and not another user's row.
create policy "orders_owner_may_cancel_only"
  on public.orders
  for update
  to authenticated
  using (auth_uid() = user_id and status = 'pending')
  with check (auth_uid() = user_id and status = 'cancelled');

-- DELETE is neither granted nor policied, so it was already denied.

-- 4. Close the equivalent path through the F&O money RPC.
--    `place_fo_order_transaction` is SECURITY INVOKER, takes p_user_id,
--    p_wallet_debit, p_wallet_credit, a whole order payload, and a
--    p_skip_balance_check flag that bypasses its own FOR UPDATE balance guard —
--    and it was callable by `authenticated`. That is a second route to the same
--    fabricated-fill outcome. Its only live caller is execute-pending-orders,
--    which uses service_role, so this revoke costs nothing that is switched on.
revoke execute on function public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, boolean
) from authenticated;
revoke execute on function public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, boolean
) from anon;

comment on table public.orders is
  'Server-written. Clients may SELECT their own rows and may only ever set '
  'status pending->cancelled; everything else goes through the place-order, '
  'modify-order and cancel-order edge functions. Do not re-add a blanket '
  'UPDATE/INSERT policy: RLS cannot restrict columns, so such a policy '
  'necessarily also grants realized_pnl and status.';
