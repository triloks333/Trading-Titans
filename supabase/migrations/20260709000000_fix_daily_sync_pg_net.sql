-- Fix daily NSE sync reliability.
--
-- Problem: the daily bhavcopy + contract sync crons invoked their edge
-- functions via the synchronous `http()` extension, which has a 5s timeout.
-- Downloading + parsing the ~35k-row NSE bhavcopy file takes much longer, so
-- every nightly run aborted with "Operation timed out after ~5000ms". The
-- settlement cron separately failed with `schema "net" does not exist`.
-- On top of that, the final `sync_lots_from_staging` cascade exceeded
-- service_role's statement timeout, 500-ing even a completed download.
--
-- Fix (schema-level, no secrets — safe to commit):
--   1. Enable pg_net so pg_cron can trigger long-running edge functions
--      asynchronously (fire-and-forget) instead of blocking for the response.
--   2. Give service_role a generous statement_timeout so the heavy staging
--      cascade completes. Only affects trusted server-side operations; anon
--      (3s) and authenticated (8s) user limits are unchanged.
--
-- NOTE: the matching cron.alter_job() rewrites that repoint jobs 26/27 (and
-- the settlement cron) to net.http_post embed the service_role key, so they
-- are applied OPERATIONALLY via execute_sql and intentionally NOT committed
-- here (secrets stay out of the repo).

create extension if not exists pg_net;

alter role service_role set statement_timeout = '180s';
