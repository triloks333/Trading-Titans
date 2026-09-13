-- ROLLBACK for 20260901000000_financial_write_lockdown.sql
-- ============================================================================
-- Restores the exact pre-lockdown state. Kept as a named file rather than a
-- reconstruct-from-memory exercise, because the thing you need at 2am is a file
-- you can run, not a diff you have to reason about.
--
-- WARNING: running this REOPENS every vulnerability the lockdown closed —
-- realized_pnl and order status writable by any signed-in user, holdings and F&O
-- positions fabricable, ₹50,000 of claimable cash creatable in one RPC call.
-- Only run it if the lockdown has broken something that cannot wait for a fix
-- forward, and treat it as an incident, not a routine revert.
--
-- PARTIAL ROLLBACK IS USUALLY BETTER. If exactly one surface broke, restore only
-- that section. The sections are independent; nothing here depends on anything
-- else here.
-- ============================================================================

begin;

-- 1. ORDERS
drop policy if exists "orders_owner_may_cancel_only" on public.orders;
revoke update (status) on public.orders from authenticated;
grant insert, update, delete on public.orders to authenticated, anon;
create policy "Users can insert own orders" on public.orders
  for insert to public with check (auth_uid() = user_id);
create policy "Users can update their own orders" on public.orders
  for update to public using (auth_uid() = user_id);

-- 2. HOLDINGS
grant insert, update, delete on public.holdings to authenticated, anon;
create policy "Users can insert own holdings" on public.holdings
  for insert to public with check (auth_uid() = user_id);
create policy "Users can update own holdings" on public.holdings
  for update to public using (auth_uid() = user_id);
create policy "Users can delete own holdings" on public.holdings
  for delete to public using (auth_uid() = user_id);

-- 3. FO_POSITIONS
grant insert, update, delete on public.fo_positions to authenticated, anon;
create policy "Users can insert own fo_positions" on public.fo_positions
  for insert to public with check ((select auth.uid()) = user_id);
create policy "Users can update own fo_positions" on public.fo_positions
  for update to public using ((select auth.uid()) = user_id)
                  with check ((select auth.uid()) = user_id);
create policy "Users can delete own fo_positions" on public.fo_positions
  for delete to public using ((select auth.uid()) = user_id);

-- 4. CRYPTO_HOLDINGS
grant insert, update, delete on public.crypto_holdings to authenticated, anon;
create policy "Users can insert own crypto_holdings" on public.crypto_holdings
  for insert to public with check (auth_uid() = user_id);
create policy "Users can update own crypto_holdings" on public.crypto_holdings
  for update to public using (auth_uid() = user_id);
create policy "Users can delete own crypto_holdings" on public.crypto_holdings
  for delete to public using (auth_uid() = user_id);

-- 5. TRADE_AUTOPSIES
grant insert, update, delete on public.trade_autopsies to authenticated, anon;
create policy "Users can insert own trade autopsies" on public.trade_autopsies
  for insert to public with check (auth_uid() = user_id);
create policy "Users can update own trade autopsies" on public.trade_autopsies
  for update to public using (auth_uid() = user_id);
create policy "Users can delete own trade autopsies" on public.trade_autopsies
  for delete to public using (auth_uid() = user_id);

-- 6. SETTLEMENT_LEDGER
grant insert, update, delete on public.settlement_ledger to authenticated, anon;
create policy "Users can insert their own settlements" on public.settlement_ledger
  for insert to public with check ((select auth.uid()) = user_id);

-- 7. REFERRAL_COMMISSIONS
grant insert, update, delete on public.referral_commissions to authenticated, anon;
create policy "Users can insert referral commissions" on public.referral_commissions
  for insert to public with check ((select auth.uid()) = referred_id);
create policy "Users can update their own referral commissions" on public.referral_commissions
  for update to public using ((select auth_uid()) = referrer_id);

-- 8. Grants RLS was already blocking
grant insert, update, delete on public.wallet_transactions to authenticated, anon;
grant insert, update, delete on public.pnl_history         to authenticated, anon;
grant insert, update, delete on public.realized_pnl_log    to authenticated, anon;
grant insert, update, delete on public.user_challenges     to authenticated, anon;
grant insert, update, delete on public.orders_archive      to authenticated, anon;

-- 9. PROFILES / REWARDS
--    NOTE: the original state had an UPDATE *policy* but no UPDATE *privilege*,
--    so the policy did nothing. It is restored for exactness. Do NOT add
--    `grant update` here — that was never the previous state and would be a
--    genuine escalation rather than a rollback.
grant insert, delete on public.profiles to authenticated, anon;
create policy "Users can update their own profile" on public.profiles
  for update to public using (auth_uid() = id);
grant insert, delete on public.rewards to authenticated, anon;

-- 10. RPCs
grant execute on function public.grant_challenge(uuid, text, text) to authenticated, anon;
-- PUBLIC, because that is what the original ACL was (`=X/postgres`). Granting to
-- authenticated/anon only would NOT restore the prior state.
grant execute on function public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, boolean
) to public;

-- Monetisation RPCs. Restoring these reopens uncapped, unverified wallet credit
-- (activate_subscription has no cap at all). They had no call sites when they were
-- revoked, so restoring them is almost never the right response to an incident —
-- if a paid flow is being built, build it on verified payments instead.
grant execute on function public.credit_demo_cash(numeric)     to authenticated;
grant execute on function public.activate_subscription(text)   to authenticated;

commit;

-- After running this, the probe should return to 17 PASS / 28 FAIL. If it does
-- not, the rollback is incomplete — compare against the audit's recorded
-- baseline in docs/financial-integrity-audit.md.
