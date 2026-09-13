-- US equities support.
--
-- Currency model
-- --------------
-- The wallet is a single INR balance and the order engine does all of its money
-- math in INR. US equities are quoted and displayed in USD, so the engine
-- converts exactly once at fill time and records what it used:
--
--   orders.price            INR  (what the wallet actually moved by)
--   orders.native_price     USD  (what the user saw and agreed to)
--   orders.fx_rate          USD -> INR rate applied at that fill
--   holdings.avg_price      INR  (cost basis the engine reasons about)
--   holdings.native_avg_price USD (cost basis the app displays)
--
-- Keeping both means a past US trade can be reconciled later; storing only the
-- INR figure would make the dollar price unrecoverable once the rate moved.
--
-- Every column is nullable and additive, so existing Indian and crypto rows are
-- untouched and stay NULL.

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS native_price    NUMERIC,
    ADD COLUMN IF NOT EXISTS native_currency TEXT,
    ADD COLUMN IF NOT EXISTS fx_rate         NUMERIC;

ALTER TABLE public.holdings
    ADD COLUMN IF NOT EXISTS native_avg_price NUMERIC,
    ADD COLUMN IF NOT EXISTS native_currency  TEXT;

ALTER TABLE public.watchlist
    ADD COLUMN IF NOT EXISTS native_currency TEXT;

COMMENT ON COLUMN public.orders.native_price IS
    'Price in the instrument''s own currency (USD for us_stock). NULL for INR markets.';
COMMENT ON COLUMN public.orders.fx_rate IS
    'USD->INR rate applied at fill. Needed to reconcile native_price against price.';
COMMENT ON COLUMN public.holdings.native_avg_price IS
    'Cost basis in the instrument''s own currency, for display only. Wallet math uses avg_price.';

-- `market` is free-text on these tables (no CHECK constraint), so 'us_stock'
-- needs no constraint change. Index the new market so portfolio and challenge
-- queries that filter by it stay cheap.
CREATE INDEX IF NOT EXISTS idx_holdings_user_market ON public.holdings(user_id, market);
CREATE INDEX IF NOT EXISTS idx_orders_user_market ON public.orders(user_id, market);

-- ─────────────────────────────────────────────────────────────────────────────
-- Overnight execution window for the US session.
--
-- The US regular session is 09:30-16:00 America/New_York, which in UTC is
-- 13:30-20:00 during EDT and 14:30-21:00 during EST. The cron below covers the
-- union of both (13:30-21:00 UTC) and the function itself refuses to fill
-- outside the real session, so running a few extra times is harmless.
--
-- In IST that window is roughly 7:00 PM to 2:30 AM, i.e. it spans two IST
-- dates. That is why this is a separate schedule rather than an extension of the
-- Indian one.
-- ─────────────────────────────────────────────────────────────────────────────
-- The bearer token is copied out of an existing net.http_post cron job inside
-- the database, so no key is written into this file or printed anywhere. Same
-- approach as the kv-push trigger. If no such job exists the block raises rather
-- than silently scheduling a job that would 401 forever.
DO $do$
DECLARE
    v_sample  TEXT;
    v_bearer  TEXT;
    v_base    TEXT;
BEGIN
    SELECT command INTO v_sample
      FROM cron.job
     WHERE command ILIKE '%net.http_post%'
       AND command ILIKE '%/functions/v1/%'
       AND command ILIKE '%Bearer %'
     LIMIT 1;

    IF v_sample IS NULL THEN
        RAISE EXCEPTION
          'No existing edge-function cron job to copy credentials from. Schedule execute-pending-us-orders manually.';
    END IF;

    v_bearer := substring(v_sample FROM 'Bearer ([A-Za-z0-9._\-]+)');
    v_base   := substring(v_sample FROM '(https://[a-z0-9\-]+\.supabase\.co)');

    IF v_bearer IS NULL OR v_base IS NULL THEN
        RAISE EXCEPTION 'Could not extract project URL or bearer from the sample cron job.';
    END IF;

    PERFORM cron.unschedule('execute-pending-us-orders')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'execute-pending-us-orders');

    PERFORM cron.schedule(
      'execute-pending-us-orders',
      '*/5 13-21 * * 1-5',
      format(
        $fmt$SELECT net.http_post(
          url := %L,
          headers := jsonb_build_object('Content-Type','application/json','Authorization',%L)
        );$fmt$,
        v_base || '/functions/v1/execute-pending-orders?commit=1',
        'Bearer ' || v_bearer
      )
    );
END
$do$;
