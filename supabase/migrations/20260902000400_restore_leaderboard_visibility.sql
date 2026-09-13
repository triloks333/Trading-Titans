-- Restore the leaderboard to showing more than one row
-- ============================================================================
-- !! SUPERSEDED BY 20260903000000_leaderboard_read_only_view.sql — DO NOT REAPPLY
--
-- This migration was right about the symptom and dangerously incomplete about the
-- cause. `leaderboard` is a simple auto-updatable view over `profiles`, and
-- `anon`/`authenticated` still held INSERT/UPDATE/DELETE on it. Setting
-- security_invoker = false without revoking those grants turned the view into a
-- write path running as postgres, so any signed-in user could
--
--     PATCH /rest/v1/leaderboard?id=eq.<anyone>  {"wallet_balance": 99999999}
--
-- and bypass the entire financial write lockdown. Verified reproducible; audited
-- afterwards and not exploited while it was open.
--
-- The replacement does both halves: security_invoker = false for reads AND all
-- write privileges revoked. Read that file instead; everything below is kept only
-- as the record of how this was diagnosed.
--
-- WHAT BROKE
-- `public.leaderboard` is in production with `security_invoker = on`. The view
-- selects from `public.profiles`, whose only SELECT policy is
-- `profiles_select_own_or_admin`. With security_invoker the view runs as the
-- CALLER, so profiles RLS applies and every signed-in user sees exactly one row:
-- their own. Verified against production as the `authenticated` role with a real
-- user's JWT claims — the app's own query returned 1 row out of 196 accounts.
--
-- Symptom: the League tab in the Android app and the Leaderboard page on the web
-- both show a board containing only you.
--
-- WHERE IT CAME FROM
-- 20260621000200_profiles_pii_lockdown.sql creates this view explicitly
-- `WITH (security_invoker = false)`. Nothing in version control changes that, so
-- it was flipped outside the migrations — almost certainly by acting on the
-- Supabase database linter, which raises `security_definer_view` at ERROR level
-- and recommends enabling security_invoker. That advice is right for most views
-- and wrong for this one.
--
-- WHY security_invoker = false IS CORRECT HERE
-- Bypassing row security is the view's entire purpose. `profiles` is deliberately
-- own-row-only because it holds email, is_admin and wallet_balance. A leaderboard
-- has to read everybody's row, so the safe way to publish one is a view that
-- projects only the non-sensitive columns and runs as its owner. Turning
-- security_invoker on does not make that safer, it just makes the feature return
-- nothing.
--
-- WHAT THIS EXPOSES (unchanged from the original design)
--   id, name, plan, total_realized_pnl, wallet_balance
-- No email, no is_admin, no purchased_cash_floor. Realised P&L and wallet balance
-- are the ranking columns the leaderboard has always displayed in both clients.
--
-- EXPECTED AFFECTED OBJECTS
--   - public.leaderboard: security_invoker back to false
--   - two COMMENTs, so the next linter sweep does not undo this again
--   - no table, policy, grant or function is touched
--
-- CLIENT COMPATIBILITY IMPACT
-- Strictly restorative. Both clients already query this view and handle a short
-- list; they simply start receiving the other rows. No rebuild needed.
--
-- ROLLBACK
--   alter view public.leaderboard set (security_invoker = on);
-- (That is the broken state; recorded only for completeness.)
--
-- VERIFY AFTER APPLYING
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     json_build_object('sub', (select id from profiles limit 1),
--                       'role','authenticated')::text, true);
--   select count(*) from public.leaderboard;   -- expect many, not 1
--   reset role;

alter view public.leaderboard set (security_invoker = false);

-- The linter will keep flagging both of these as `security_definer_view`. The
-- comment is the only durable place to say why that finding is expected, since
-- the last time it was "fixed" the leaderboard silently died.
comment on view public.leaderboard is
  'Publishes the safe, non-sensitive columns of profiles for the leaderboard. '
  'MUST stay security_invoker = false: profiles is own-row-only, so with '
  'security_invoker on this view returns just the caller''s own row and the '
  'leaderboard appears empty. The Supabase linter flags this as '
  'security_definer_view; that finding is expected and must not be "fixed". '
  'Exposes id, name, plan, total_realized_pnl, wallet_balance and nothing else.';

comment on view public.user_tiers is
  'Publishes current_tier(id) per user for the PRO/TITAN badge on profiles and the '
  'leaderboard. MUST stay security_invoker = false for the same reason as '
  'public.leaderboard: it reads every profiles row, and enforcing the caller''s '
  'RLS would reduce it to one row and silently remove everyone else''s badge. '
  'Exposes a user id and a tier name, nothing else.';

-- ── The anon read, now handled ──────────────────────────────────────────────
-- This migration also left the view readable by `anon`, because 20260621000200
-- granted SELECT to `anon, authenticated`. Confirmed at the time against the live
-- REST API with only the public anon key: an unauthenticated request returned every
-- user's name and realised P&L.
--
-- 20260903000000 revokes that too, along with the write privileges.
