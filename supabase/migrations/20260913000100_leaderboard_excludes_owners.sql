-- Owners and admins off the leaderboard.
--
-- Requested: "since pawan, trilok and manav are owners hide them from leaderboard
-- as they have lots of money in there accounts".
--
-- The same predicate already exists in award_weekly_podium()
-- (20260805000000_gamification_and_app_flags.sql:525-531), whose header gives the
-- same reason: owners hold large demo balances by design and would otherwise
-- sweep the podium every week. Until now they were excluded from *winning* the
-- podium but still sat on top of the board, which is the inconsistency this
-- closes.
--
-- ── WHY create or replace, NOT drop + create ────────────────────────────────
-- The output column list is deliberately unchanged, which is what makes
-- `create or replace view` legal here. That keeps the GRANTs — a drop + create
-- would restore Supabase's default GRANT ALL on a new object in `public` and
-- reopen a one-request `PATCH /rest/v1/leaderboard {"wallet_balance": 99999999}`
-- on any account, because this is a simple auto-updatable view over `profiles`
-- and with security_invoker = false a write through it runs as postgres and
-- bypasses the financial lockdown.
--
-- ── THE WITH CLAUSE IS LOAD-BEARING, NOT DECORATION ─────────────────────────
-- `create or replace view` does NOT preserve reloptions: with no WITH clause the
-- new definition's options REPLACE the old ones, so security_invoker silently
-- reverts to the default (on). The view then returns only the caller's own row
-- and the League tab goes empty for everyone — the exact bug
-- 20260903000000_leaderboard_read_only_view.sql records as having shipped twice.
--
-- This was not theoretical. The first attempt at this migration omitted the WITH
-- clause, and the assertion block at the bottom caught it and aborted the
-- transaction before it reached production.
--
-- Adding a WHERE clause does not change auto-updatability, so the existing
-- revokes remain the thing standing between this view and that hole. They are
-- verified again at the bottom of this file.
--
-- ── WHY wallet_balance IS STILL PROJECTED ───────────────────────────────────
-- The user also asked that the leaderboard show P&L only, not wallet balance.
-- That is done in the two clients, NOT here, because both of them name the column
-- explicitly:
--
--   app/lib/services/supabase_service.dart:1531
--     .select('id, name, wallet_balance, total_realized_pnl')
--   web/src/pages/Leaderboard.tsx:41
--     .select('id, name, total_realized_pnl, wallet_balance')
--
-- 1.2.3 has been live for weeks. Dropping the column would make PostgREST reject
-- that select outright, so every already-installed app would show an error where
-- the League tab used to be, until each user updated. The column can be removed
-- once no supported build asks for it; `min_supported_version` is the gate for
-- that, and it is currently 1.0.0.
--
-- ── AFFECTED OBJECTS ────────────────────────────────────────────────────────
--   public.leaderboard : body gains a WHERE clause. Columns, options, grants,
--                        security_invoker and comment all unchanged.
--   Nothing else. No table, policy, function or column grant is touched, and
--   public.user_tiers is not involved (it is keyed per user id, and both clients
--   only look up tiers for rows the board already returned).
--
-- ── CLIENT COMPATIBILITY ────────────────────────────────────────────────────
-- Safe for every shipped build, and it takes effect for ALL users immediately
-- with no release: the four owner accounts simply stop appearing. Old builds see
-- a shorter list, which is the intent. Their "Your position" card is computed
-- from the returned rows, so an owner on an old build now falls out of the board;
-- that is the point of the change.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   create or replace view public.leaderboard as
--     select id, name, plan, total_realized_pnl, wallet_balance
--       from public.profiles
--     order by total_realized_pnl desc;

create or replace view public.leaderboard
  with (security_invoker = false) as
  select p.id,
         p.name,
         p.plan,
         p.total_realized_pnl,
         p.wallet_balance
    from public.profiles p
   -- coalesce on both, because `not null` and `null not in (...)` both evaluate to
   -- NULL, which the WHERE would drop — silently hiding any account with a null
   -- email or is_admin instead of only the owners.
   where coalesce(p.is_admin, false) = false
     and coalesce(p.email, '') not in (
           'pawan.2u2@gmail.com',
           'triloks34@gmail.com',
           'mr.engineer5000@gmail.com',
           'manavagg2003@gmail.com'
         )
   order by p.total_realized_pnl desc;

-- The list above is duplicated from award_weekly_podium(). Left duplicated rather
-- than factored into a shared helper: rewriting that function to call one would
-- mean touching a SECURITY DEFINER function that grants challenge badges, which is
-- a worse trade than two copies of four strings. If a fifth owner is ever added,
-- BOTH places need it — grep for 'pawan.2u2@gmail.com'.
comment on view public.leaderboard is
  'Publishes the safe columns of profiles (id, name, plan, total_realized_pnl, '
  'wallet_balance) for the League screen, EXCLUDING admins and the four owner '
  'accounts — they hold large demo balances by design and would otherwise sit '
  'permanently on top. Same exclusion as award_weekly_podium(); keep the two in '
  'step. READ ONLY: insert/update/delete are revoked from anon and authenticated '
  'because this is a simple auto-updatable view, and with security_invoker=false '
  'a write through it would run as postgres and bypass the financial lockdown — a '
  'signed-in user could rewrite any wallet balance. MUST stay '
  'security_invoker = false or it returns only the caller''s own row and the '
  'League tab goes empty. The Supabase linter flags this as '
  'security_definer_view; that finding is expected here and must NOT be "fixed" — '
  'doing so has already broken this feature twice. wallet_balance is still '
  'projected only because shipped clients select it by name; the clients no longer '
  'display it.';

-- Belt and braces. `create or replace` keeps these, but this view's protections
-- have been lost twice, so assert rather than assume.
do $$
begin
  if (select reloptions::text from pg_class where relname = 'leaderboard')
       is distinct from '{security_invoker=false}' then
    raise exception 'leaderboard lost security_invoker=false; the League tab will be empty';
  end if;

  if has_table_privilege('authenticated', 'public.leaderboard', 'UPDATE')
     or has_table_privilege('anon', 'public.leaderboard', 'UPDATE') then
    raise exception 'leaderboard is writable through PostgREST again — wallet balances are forgeable';
  end if;

  if has_table_privilege('anon', 'public.leaderboard', 'SELECT') then
    raise exception 'leaderboard readable signed out again';
  end if;
end
$$;
