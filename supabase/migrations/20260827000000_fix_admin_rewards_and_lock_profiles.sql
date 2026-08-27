-- Fix the admin "Give Reward" button, and close the privilege-escalation hole
-- that would otherwise make the fix dangerous.
--
-- THE REPORTED BUG
-- `sendReward()` (app/lib/services/supabase_service.dart) inserts into
-- public.rewards from the client. That table has RLS enabled with exactly two
-- policies -- SELECT and UPDATE, both `auth_uid() = user_id` -- and NO INSERT
-- policy. In Postgres, RLS enabled with no permissive policy for a command
-- denies that command outright, so every admin reward failed with
-- `42501 new row violates row-level security policy for table "rewards"`.
--
-- It has never worked. All 131 existing rows are gamification grants ("First
-- Blood", "Weekly Champion", ...) written by the challenge/podium crons under
-- the service role, which bypasses RLS. That masked the broken client path.
--
-- WHY THE OBVIOUS ONE-LINER WAS NOT SAFE ON ITS OWN
-- The natural fix gates the INSERT on is_admin(), which reads
-- profiles.is_admin. But `anon` and `authenticated` held UPDATE on profiles,
-- the RLS policy was `auth_uid() = id` with a NULL with_check and no column
-- restriction, and none of the three triggers on the table guard any column. So
-- any signed-in user could set their own `is_admin = true` (or set
-- `wallet_balance` directly). Gating a reward -- which `claim_reward` converts
-- into real wallet balance -- on a self-settable flag would have created a
-- money-minting path. Statement 1 therefore has to land before statement 2;
-- both are in this one transaction so there is no window between them.
--
-- WHY REVOKING UPDATE ON profiles BREAKS NOTHING
-- Audited every client write path first. No live code does a direct UPDATE on
-- profiles:
--   * Every profile write goes through a SECURITY DEFINER RPC -- ensure_profile,
--     save_user_preferences, credit_demo_cash, activate_subscription,
--     claim_reward, touch_login_streak, award_glossary_quiz,
--     evaluate_challenges, convert_guest_account, apply_referral_code. DEFINER
--     functions run as the owner, so they are unaffected by these grants.
--   * The direct `.from('profiles').update(...)` calls in supabase_service.dart
--     all sit inside _placeOrderLocal, _executePendingOrdersInner and
--     settleExpiredDerivatives, which return early behind
--     `_useServerPlaceOrder = true` / `_serverExecOnly = true`. Dead code.
--   * website/api/verify-payment.js credits wallets with the SERVICE ROLE key
--     ("bypasses RLS" per its own comment), not the anon key.
--   * place_fo_order_transaction is SECURITY INVOKER, but the live callers are
--     the place-order / execute-pending-orders edge functions using the service
--     role. Its two Dart call sites are in the dead paths above.
-- The app source even assumes this is already the case: the comment above
-- saveUserPreferences says "`profiles` has no user UPDATE policy". It did have
-- one. Now the grant matches the intent.
--
-- Supabase-only by design: no app code changes, so no version bump and no Play
-- Store release. The shipped client keeps calling the same two inserts.
--
-- ROLLBACK
--   grant update on public.profiles to anon, authenticated;
--   grant update on public.rewards  to anon, authenticated;
--   drop policy rewards_insert_admin on public.rewards;

-- 1. No client may write profiles directly any more. Column-level privileges are
--    checked independently of (and before) RLS, so this is a hard stop rather
--    than another policy to reason about. Closes both the is_admin escalation
--    and direct wallet_balance / total_realized_pnl / plan self-service.
revoke update on public.profiles from anon, authenticated;

-- 2. Admins may create reward rows. This is what unblocks the button.
--    Scoped `to authenticated` so the anon role can never satisfy it, and safe
--    now that is_admin cannot be self-granted. `authenticated` already holds the
--    INSERT privilege on this table, so the missing policy was the only blocker.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'rewards'
      and policyname = 'rewards_insert_admin'
  ) then
    create policy rewards_insert_admin on public.rewards
      for insert to authenticated
      with check (public.is_admin());
  end if;
end $$;

-- 3. Users may no longer edit their own reward rows. The existing UPDATE policy
--    was `auth_uid() = user_id` with no column restriction, so a user could
--    raise `amount` before claiming, or flip `is_claimed` back to false and
--    claim the same reward repeatedly. No client code updates this table -- the
--    only client writes are the admin insert and a SELECT -- and claim_reward is
--    SECURITY DEFINER, so it keeps working.
revoke update on public.rewards from anon, authenticated;
