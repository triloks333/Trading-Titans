-- Read notifications delete themselves after 7 days.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- RECONSTRUCTED FROM THE LIVE DATABASE, 13 Sep 2026.
--
-- This migration version (20260907151036) is recorded as applied in
-- supabase_migrations.schema_migrations, but its .sql file was never committed —
-- so `supabase db reset` would have produced a database without the feature
-- while production had it. The definitions below are taken verbatim from
-- pg_get_functiondef / pg_get_triggerdef on production, so a fresh database now
-- reproduces what is actually running.
--
-- Nothing here re-runs against production: the version is already in the
-- migration history, so `db push` skips it. Every statement is idempotent
-- regardless.
--
-- The grants recorded at the bottom are the ones production actually had, hole
-- included — see 20260913000000_harden_notification_purge.sql, which closes it.
-- Reproducing the mistake and then fixing it keeps the history honest.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. When the row was read ────────────────────────────────────────────────
-- `is_read` is a boolean, so on its own there is nothing to measure seven days
-- from. This is the clock the purge reads.
ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

COMMENT ON COLUMN public.notifications.read_at IS
    'When is_read first went false -> true. NULL while unread. Set by '
    'trg_stamp_notification_read_at, and the only input to purge_read_notifications().';

-- ── 2. Stamp it server-side, not in the client ──────────────────────────────
-- A trigger rather than asking each caller to set it: the app marks rows read
-- from two places, and edge functions and SQL crons write this table too. One
-- writer forgetting would leave a row that never expires.
CREATE OR REPLACE FUNCTION public.stamp_notification_read_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
begin
  -- Only the false -> true transition. Re-reading must not restart the clock, or
  -- a user who opens their bell often would keep notifications forever.
  if new.is_read and not coalesce(old.is_read, false) and new.read_at is null then
    new.read_at := now();
  end if;
  -- Unreading clears it, so the row is not deleted while it still shows unread.
  if not new.is_read then
    new.read_at := null;
  end if;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_stamp_notification_read_at ON public.notifications;
-- BEFORE UPDATE OF is_read: it has to be BEFORE to modify NEW, and narrowing to
-- the one column keeps it off every unrelated update of the row.
CREATE TRIGGER trg_stamp_notification_read_at
    BEFORE UPDATE OF is_read ON public.notifications
    FOR EACH ROW EXECUTE FUNCTION public.stamp_notification_read_at();

-- Rows already read when this shipped have no read_at, so they would never
-- expire. Stamping them now starts their seven days from here rather than
-- deleting a backlog the moment the cron first runs.
UPDATE public.notifications
   SET read_at = now()
 WHERE is_read AND read_at IS NULL;

-- ── 3. The sweep ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.purge_read_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  removed integer;
begin
  -- Bounded per run so one sweep cannot hold a long transaction over a table the
  -- app reads on every launch. At 5,000 a day the current 9,869 clear in two runs.
  with doomed as (
    select id from public.notifications
     where read_at is not null
       and read_at < now() - interval '7 days'
     limit 5000
  )
  delete from public.notifications n
   using doomed d
   where n.id = d.id;

  get diagnostics removed = row_count;
  return removed;
end;
$function$;

COMMENT ON FUNCTION public.purge_read_notifications() IS
    'Deletes notifications read more than 7 days ago, max 5000 per call. '
    'Hard delete: the row is gone, order fills and payment notices included. '
    'Service role only — called by the purge-read-notifications cron.';

-- ── 4. Daily, well after the market crons ───────────────────────────────────
-- 20:20 UTC = 01:50 IST, when nothing else is running and nobody is trading.
SELECT cron.unschedule('purge-read-notifications')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-read-notifications');

SELECT cron.schedule(
    'purge-read-notifications',
    '20 20 * * *',
    'SELECT public.purge_read_notifications();'
);

-- ── 5. Grants, as production had them ───────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.purge_read_notifications() TO service_role;
