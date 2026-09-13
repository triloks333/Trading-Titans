-- Close two holes in the 7-day notification purge (20260907151036).
--
-- ── 1. purge_read_notifications() was callable by anon ──────────────────────
-- It was created without revoking the default PUBLIC EXECUTE, so:
--
--     has_function_privilege('anon', 'public.purge_read_notifications()', 'EXECUTE') = true
--
-- PostgREST exposes every public-schema function the caller can execute, and the
-- function is SECURITY DEFINER with no auth.uid() guard. That made
--
--     POST /rest/v1/rpc/purge_read_notifications
--
-- an UNAUTHENTICATED endpoint that deletes 5,000 of any users' read
-- notifications per call, and it can be called in a loop. It only removes rows
-- the cron would remove within the day, so this is not a disclosure — but it is
-- an anon-triggerable DELETE on a user-facing table, and nothing outside the
-- cron has any reason to call it.
--
-- ── 2. stamp_notification_read_at() had a mutable search_path ───────────────
-- Flagged by the Supabase security advisor. It runs on every notification that
-- gets marked read, so an unqualified name inside it resolves through whatever
-- search_path the caller happens to have set.
--
-- AFFECTED OBJECTS
--   public.purge_read_notifications()    grants only, body unchanged
--   public.stamp_notification_read_at()  adds SET search_path, body unchanged
--
-- CLIENT COMPATIBILITY
--   None. No shipped build calls either function — the trigger fires inside the
--   `is_read` UPDATE the app already sends, and the purge only ever ran from
--   pg_cron as the postgres superuser, which is unaffected by these revokes.
--
-- ROLLBACK
--   GRANT EXECUTE ON FUNCTION public.purge_read_notifications() TO PUBLIC;
--   ALTER FUNCTION public.stamp_notification_read_at() RESET search_path;

-- ── The purge is service-role only ──────────────────────────────────────────
REVOKE ALL ON FUNCTION public.purge_read_notifications() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_read_notifications() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_read_notifications() TO service_role;

-- ── Pin the trigger function's search_path ──────────────────────────────────
-- ALTER rather than CREATE OR REPLACE: the body is already correct and this way
-- the trigger is never momentarily pointing at a redefined function.
ALTER FUNCTION public.stamp_notification_read_at()
    SET search_path TO 'public', 'pg_temp';

-- A trigger function has no business being called directly either. Revoking
-- EXECUTE does not affect the trigger: Postgres runs trigger functions as the
-- table owner regardless of who issued the UPDATE.
REVOKE ALL ON FUNCTION public.stamp_notification_read_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stamp_notification_read_at() FROM anon, authenticated;
