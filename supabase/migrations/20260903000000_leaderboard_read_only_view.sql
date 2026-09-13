-- Make the leaderboard and tier views readable again, and read-ONLY
-- ============================================================================
-- This supersedes 20260902000400_restore_leaderboard_visibility.sql, which was
-- correct about the symptom and dangerously incomplete about the cause.
--
-- THE FULL PICTURE
-- `public.leaderboard` is `SELECT id, name, plan, total_realized_pnl,
-- wallet_balance FROM public.profiles`. Every column is a plain column reference
-- over a single table, which makes it a simple **auto-updatable** view: Postgres
-- will happily route INSERT/UPDATE/DELETE through it into `profiles`.
--
-- `anon` and `authenticated` held INSERT, UPDATE, DELETE and TRUNCATE on it —
-- Supabase's default GRANT ALL on new objects in `public`, never revoked for these
-- two views.
--
-- Combine those two facts with `security_invoker = false` and the view becomes a
-- write path that runs as its owner (postgres) and therefore bypasses `profiles`
-- RLS and the entire financial write lockdown. Verified against production inside
-- a rolled-back transaction, as `authenticated` with a real user's JWT claims:
--
--     update public.leaderboard set wallet_balance = 99999999 where id = <uuid>;
--     -- 1 row; wallet_balance 11000.0 -> 99999999
--
-- Over PostgREST that is one request:
--     PATCH /rest/v1/leaderboard?id=eq.<any user>   {"wallet_balance": 99999999}
--
-- So the two obvious states were each half-wrong:
--   security_invoker = on   -> no write hole, but the view returns only the
--                              caller's own row, so the League tab and every
--                              PRO/TITAN badge silently disappear.
--   security_invoker = off  -> the features work, and anyone signed in can rewrite
--                              any wallet balance.
--
-- The answer is `off` for reads AND no write privileges at all. Verified in the
-- same rolled-back transaction: after the revokes the same UPDATE fails with 42501
-- while a SELECT still returns all 201 rows.
--
-- WHY NOT JUST LEAVE security_invoker = on
-- Because bypassing row security is the whole reason these views exist. `profiles`
-- is deliberately own-row-only (it holds email, is_admin, purchased_cash_floor), and
-- a leaderboard has to read everybody. The safe way to publish that is a view that
-- projects only the harmless columns and runs as its owner. Enforcing the caller's
-- RLS does not make it safer; it makes it return nothing.
--
-- ABOUT THE SUPABASE LINTER
-- The database linter raises `security_definer_view` at ERROR level for both of
-- these and recommends turning security_invoker on. Following that advice is what
-- broke the League tab and the plan badges, twice. **For these two views that
-- finding is expected and must be left alone.** With writes revoked, the thing the
-- lint warns about — privileged access through a view — is reduced to reading five
-- non-sensitive columns, which is the feature.
--
-- EXPECTED AFFECTED OBJECTS
--   public.leaderboard : security_invoker -> false;
--                        INSERT/UPDATE/DELETE/TRUNCATE revoked from anon+authenticated;
--                        SELECT revoked from anon
--   public.user_tiers  : same treatment
--   No table, policy, function or column grant is touched. `profiles` keeps its
--   own-row-only policy exactly as it is.
--
-- WHY SELECT IS ALSO REVOKED FROM anon
-- Both clients gate these screens behind a session, so nothing legitimate reads
-- them signed out. Before this, the public anon key was enough to list all 201
-- users' names, wallet balances and realised P&L over the REST API.
--
-- CLIENT COMPATIBILITY IMPACT
-- None. The Flutter app and the web app both query these views as a signed-in
-- user, which is unaffected. No rebuild or release is needed.
--
-- ROLLBACK
--   grant select, insert, update, delete, truncate
--     on public.leaderboard, public.user_tiers to anon, authenticated;
--   alter view public.leaderboard set (security_invoker = on);
--   alter view public.user_tiers  set (security_invoker = on);
-- (That restores both the broken features and the write hole. Recorded only for
-- completeness.)
--
-- VERIFY AFTER APPLYING
--   set local role authenticated;
--   select set_config('request.jwt.claims',
--     json_build_object('sub', (select id from profiles limit 1),
--                       'role','authenticated')::text, true);
--   select count(*) from public.leaderboard;   -- expect ~201
--   update public.leaderboard set wallet_balance = 1 where true;  -- expect 42501
--   select count(*) from public.profiles;      -- expect 1
--   reset role;

-- Reads bypass caller RLS, which is the point of these views.
alter view public.leaderboard set (security_invoker = false);
alter view public.user_tiers  set (security_invoker = false);

-- ...and nothing may write through them. This is the half that was missing.
revoke insert, update, delete, truncate on public.leaderboard from anon, authenticated;
revoke insert, update, delete, truncate on public.user_tiers  from anon, authenticated;

-- Signed-in only. Both clients require a session to reach these screens.
revoke select on public.leaderboard from anon;
revoke select on public.user_tiers  from anon;

-- Stop the next `create view` in public from handing these privileges out again.
alter default privileges in schema public
  revoke insert, update, delete, truncate on tables from anon, authenticated;

comment on view public.leaderboard is
  'Publishes the safe columns of profiles (id, name, plan, total_realized_pnl, '
  'wallet_balance) for the League screen. READ ONLY: insert/update/delete are '
  'revoked from anon and authenticated because this is a simple auto-updatable '
  'view, and with security_invoker=false a write through it would run as postgres '
  'and bypass the financial lockdown — a signed-in user could rewrite any wallet '
  'balance. MUST stay security_invoker = false or it returns only the caller''s own '
  'row and the League tab goes empty. The Supabase linter flags this as '
  'security_definer_view; that finding is expected here and must NOT be "fixed" — '
  'doing so has already broken this feature twice.';

comment on view public.user_tiers is
  'Publishes current_tier(id) per user for the PRO/TITAN badge on profiles and the '
  'League screen. Same rules as public.leaderboard: read only, and MUST stay '
  'security_invoker = false or every badge except your own disappears. The linter''s '
  'security_definer_view finding on this view is expected and must NOT be "fixed".';
