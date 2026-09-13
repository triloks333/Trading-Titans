-- Financial write lockdown — make the server authoritative for all money state.
-- ============================================================================
-- STATUS: NOT APPLIED. Prepared for review.
--
-- Evidence: supabase/tests/financial_integrity_probe.sql, run against production
-- inside a rolled-back transaction as a normal `authenticated` user. Baseline
-- before this migration: 45 assertions, 17 PASS, 28 FAIL, 0 inconclusive.
--
-- THE PATTERN BEING REMOVED
-- Six tables carry a policy of the shape `USING (auth_uid() = user_id)` with no
-- WITH CHECK and no column restriction, plus a table-wide grant. RLS cannot
-- restrict columns, so "may edit own row" and "may rewrite own P&L" are the same
-- privilege. Verified: `realized_pnl = 999999` and `status = 'executed'` written
-- on an own order; 100,000 units of a holding created from nothing; `net_qty`,
-- `margin_blocked` and `realized_pnl` rewritten on an F&O position.
--
-- NOT CHANGED BY THIS MIGRATION
--   * The execution trigger rules (SELL fills at LTP >= limit, BUY at LTP <= limit).
--   * resolveFillPrice / isRestingLimit.
--   * The claim/CAS idempotency in execute-pending-orders.
--   * Any function body. This file only moves privileges and policies.
--   * `evaluate_challenges` and `claim_reward` — both already enforce auth.uid()
--     correctly and both are used by the app.
--   * The dormant on-device paths are NOT deleted (separate cleanup, by request).
--
-- SERVICE ROLE IS UNAFFECTED throughout, so place-order, modify-order,
-- cancel-order, execute-pending-orders, settle-expired-positions, snapshot-pnl
-- and every cron continue to work.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ORDERS
--    Creation is exclusively place-order; modification exclusively modify-order;
--    cancellation exclusively cancel-order. One narrow client transition is kept
--    for already-installed app builds — see section 8.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert own orders"        on public.orders;
drop policy if exists "Users can update their own orders"  on public.orders;

revoke insert, update, delete on public.orders from authenticated, anon;

-- Column-level: the ONLY column a client may ever write. This is the part RLS
-- cannot express, and it is what puts realized_pnl, quantity, price, limit_price,
-- total, user_id, created_at, executed_at, execution_price_source and
-- execution_reference_price out of reach entirely.
grant update (status) on public.orders to authenticated;

-- ...and the only transition it may make. USING inspects the existing row,
-- WITH CHECK the proposed one, so together these permit pending -> cancelled and
-- refuse pending -> executed, pending -> executing, pending -> failed,
-- cancelled -> pending, and any row belonging to somebody else.
create policy "orders_owner_may_cancel_only"
  on public.orders for update to authenticated
  using      (auth_uid() = user_id and status = 'pending')
  with check (auth_uid() = user_id and status = 'cancelled');

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. HOLDINGS — server-owned outright. No client write is legitimate: all 12
--    write sites in the app are in the dormant on-device paths.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert own holdings" on public.holdings;
drop policy if exists "Users can update own holdings" on public.holdings;
drop policy if exists "Users can delete own holdings" on public.holdings;
revoke insert, update, delete on public.holdings from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. FO_POSITIONS — server-owned. net_qty, avg_entry_price, margin_blocked,
--    realized_pnl, is_settled and settlement_price are all accounting state.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert own fo_positions" on public.fo_positions;
drop policy if exists "Users can update own fo_positions" on public.fo_positions;
drop policy if exists "Users can delete own fo_positions" on public.fo_positions;
revoke insert, update, delete on public.fo_positions from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CRYPTO_HOLDINGS — server-owned, same shape as holdings.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert own crypto_holdings" on public.crypto_holdings;
drop policy if exists "Users can update own crypto_holdings" on public.crypto_holdings;
drop policy if exists "Users can delete own crypto_holdings" on public.crypto_holdings;
revoke insert, update, delete on public.crypto_holdings from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. TRADE_AUTOPSIES — trade history. Written by the trade-autopsy function.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert own trade autopsies" on public.trade_autopsies;
drop policy if exists "Users can update own trade autopsies" on public.trade_autopsies;
drop policy if exists "Users can delete own trade autopsies" on public.trade_autopsies;
revoke insert, update, delete on public.trade_autopsies from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. SETTLEMENT_LEDGER — described in its own migration as an immutable record.
--    A client INSERT contradicts that.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert their own settlements" on public.settlement_ledger;
revoke insert, update, delete on public.settlement_ledger from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. REFERRAL_COMMISSIONS — commission_amount is money. apply_referral_code()
--    (SECURITY DEFINER, auth.uid()-scoped) is the legitimate writer.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert referral commissions"          on public.referral_commissions;
drop policy if exists "Users can update their own referral commissions" on public.referral_commissions;
revoke insert, update, delete on public.referral_commissions from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Tables RLS already blocks, but whose grants are still open.
--    Revoking closes the gap where a future permissive policy would silently
--    re-open a write path, because the grant was never withdrawn.
--    No behaviour change today: the probe confirms all of these already refuse.
-- ─────────────────────────────────────────────────────────────────────────────
revoke insert, update, delete on public.wallet_transactions from authenticated, anon;
revoke insert, update, delete on public.pnl_history         from authenticated, anon;
revoke insert, update, delete on public.realized_pnl_log    from authenticated, anon;
revoke insert, update, delete on public.user_challenges     from authenticated, anon;
revoke insert, update, delete on public.orders_archive      from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. PROFILES — already correct. Do NOT grant UPDATE.
--
--    Verified: `profiles` has no UPDATE privilege at table or column level, so
--    every attempt fails with 42501 before RLS is consulted. The UPDATE policy is
--    therefore unreachable, and dropping it is a no-op TODAY but strictly safer
--    TOMORROW: with no policy, a future `grant update` would still deny-all,
--    whereas leaving a permissive `USING (auth_uid() = id)` policy in place means
--    such a grant would instantly expose wallet_balance, total_realized_pnl,
--    is_admin, plan and subscription_active. Removing the policy makes the safe
--    state the default rather than an accident.
--
--    The five genuinely user-settable fields (name, display_currency,
--    preferred_markets, onboarding_completed_at, location) are written by
--    save_user_preferences() and accept_terms(), both SECURITY DEFINER and both
--    scoped to auth.uid(). Those are NOT touched.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Users can update their own profile" on public.profiles;
revoke insert, delete on public.profiles from authenticated, anon;

-- rewards: INSERT is is_admin()-only via policy and UPDATE has no privilege.
-- grant_challenge() writes it as DEFINER and is unaffected by the revoke.
revoke insert, delete on public.rewards from authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RPCs
-- ─────────────────────────────────────────────────────────────────────────────
-- grant_challenge: SECURITY DEFINER, arbitrary p_user_id, no auth.uid() check and
-- no is_admin() check. Being DEFINER it bypasses the is_admin()-only INSERT policy
-- on `rewards` and writes a claimable row directly. Verified: ₹50,000 of claimable
-- cash created in one call by a normal user; ₹142,000 forgeable across the 25
-- active challenges; 3 have repeat_limit = NULL, so the ₹75,000/month ceiling is
-- the only remaining bound.
--
-- Safe to revoke: its callers are evaluate_challenges() and
-- evaluate_challenges_all(), both SECURITY DEFINER owned by `postgres`, so the
-- inner privilege check is made as postgres. The nightly cron and the app's own
-- evaluate_challenges() call are unaffected. No client calls it directly.
revoke execute on function public.grant_challenge(uuid, text, text) from authenticated, anon;

-- place_fo_order_transaction: SECURITY INVOKER, arbitrary p_user_id, arbitrary
-- p_wallet_credit, and p_skip_balance_check to bypass its own FOR UPDATE balance
-- guard. Not currently exploitable — as INVOKER it inherits the caller's lack of
-- `profiles` UPDATE privilege and fails 42501 — but its safety is accidental and
-- rests entirely on section 9 staying true. Only live caller is
-- execute-pending-orders, as service_role.
-- NOTE: `from authenticated, anon` alone is NOT enough here, and finding that out
-- cost a follow-up migration. This function's ACL was `=X/postgres`, i.e. EXECUTE
-- granted to PUBLIC, and a role-specific revoke does not remove access that
-- arrives via PUBLIC. The revoke silently did nothing and the function stayed
-- callable. The other three functions below had explicit ACLs with no PUBLIC
-- entry, so their role-specific revokes did take effect.
--
-- Always check `proacl` for a leading `=X/` before assuming a revoke landed:
--   select proname, proacl from pg_proc where proname = '...';
revoke execute on function public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, boolean
) from public, authenticated, anon;

-- credit_demo_cash: SECURITY DEFINER, auth.uid()-scoped (cannot target another
-- user), rejects guests. Caps a SINGLE call at 1,000,000 but places no limit on
-- the number of calls and has no cumulative cap and no rate limit, so the cap
-- limits nothing. Does not consult any payment record — there is no
-- payment_orders table to consult.
revoke execute on function public.credit_demo_cash(numeric) from authenticated, anon;

-- activate_subscription: SECURITY DEFINER, auth.uid()-scoped, rejects guests.
-- No cap of any kind. Credits ₹5,00,000 for 'titan_5l', ₹10,00,000 for
-- 'titan_pro', and ₹1,00,000 for ANY other string. Also sets
-- subscription_active = true and writes `plan` from the unvalidated argument —
-- the exact field a future paywall would read. No payment verification.
revoke execute on function public.activate_subscription(text) from authenticated, anon;

-- Both are safe to revoke now: `creditDemoCash`, `activateSubscription`,
-- `purchasePackage` and `createSubscriptionOrder` are DEFINED in
-- app/lib/services/supabase_service.dart but have ZERO call sites anywhere in the
-- app or the web client — not even from the (already flag-gated) wallet and
-- subscribe screens. Nothing references them.
--
-- This deliberately does NOT add a replacement. No payment verification is
-- invented here and the payment architecture is untouched; these are simply
-- closed. Reintroducing paid top-ups requires the separate work in
-- docs/monetisation-plan.md Phase 1.

-- DELIBERATELY NOT REVOKED:
--   evaluate_challenges(uuid) — the app calls it as rpc('evaluate_challenges')
--     relying on `p_user_id DEFAULT auth.uid()`, and it already overwrites
--     p_user_id with auth.uid() for any non-admin caller, granting only challenges
--     the account actually satisfies. It is the safe front door.
--   claim_reward(text) — auth.uid()-scoped and requires an unclaimed reward owned
--     by the caller. The probe confirms it refuses another user's reward.

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Documentation the next reader will actually see.
-- ─────────────────────────────────────────────────────────────────────────────
comment on table public.orders is
  'Server-written. Clients may SELECT their own rows and may only set status '
  'pending->cancelled (temporary, for older app builds). All other mutation goes '
  'through place-order / modify-order / cancel-order. Never re-add a blanket '
  'UPDATE or INSERT policy: RLS cannot restrict columns, so such a policy '
  'necessarily also grants realized_pnl, status and quantity.';

comment on table public.holdings is
  'Server-written. Clients may SELECT their own rows only.';
comment on table public.fo_positions is
  'Server-written. Clients may SELECT their own rows only.';
comment on table public.crypto_holdings is
  'Server-written. Clients may SELECT their own rows only.';
comment on table public.trade_autopsies is
  'Server-written by the trade-autopsy function. Clients may SELECT only.';
comment on table public.settlement_ledger is
  'Immutable server-written settlement record. Clients may SELECT only.';
comment on table public.referral_commissions is
  'Server-written by apply_referral_code(). Clients may SELECT their own only.';
comment on table public.profiles is
  'Money and account-state columns are server-owned; there is deliberately NO '
  'UPDATE privilege for clients. User-settable fields (name, display_currency, '
  'preferred_markets, onboarding_completed_at, location) are written by '
  'save_user_preferences() and accept_terms(), both SECURITY DEFINER and scoped '
  'to auth.uid(). Do not grant UPDATE to add a profile field.';

commit;

-- ── Verify ──────────────────────────────────────────────────────────────────
-- Re-run the probe. Expect 45 assertions, 45 PASS, 0 FAIL, 0 inconclusive:
--   psql "$DATABASE_URL" -f supabase/tests/financial_integrity_probe.sql
--
-- ── Rollback ────────────────────────────────────────────────────────────────
-- supabase/migrations/20260901000000_financial_write_lockdown_ROLLBACK.sql
-- restores the previous state exactly. Note that doing so reopens every
-- vulnerability listed above.
