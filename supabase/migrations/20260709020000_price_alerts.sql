-- Backfills the migration for `public.price_alerts`.
--
-- The table already exists in production — it was created through the dashboard
-- and never had a migration file, so the repo did not describe the real schema.
-- Shape below was read back from the live database (PostgREST OpenAPI spec), so
-- this is a faithful record rather than a guess.
--
-- Every statement is idempotent: applying this to an environment that already
-- has the table is a no-op, and applying it to a fresh one reproduces it.

CREATE TABLE IF NOT EXISTS public.price_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    symbol          TEXT NOT NULL,
    market          TEXT NOT NULL DEFAULT 'stock',
    name            TEXT,
    target_price    NUMERIC NOT NULL,
    direction       TEXT NOT NULL,          -- 'above' | 'below'
    reference_price NUMERIC,                -- price when the alert was created
    status          TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'triggered'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    triggered_at    TIMESTAMPTZ
);

-- Serves the "my active alerts" read on every quote refresh.
CREATE INDEX IF NOT EXISTS idx_price_alerts_user_status
    ON public.price_alerts(user_id, status);

ALTER TABLE public.price_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own price alerts" ON public.price_alerts;
CREATE POLICY "Users can view own price alerts"
    ON public.price_alerts FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own price alerts" ON public.price_alerts;
CREATE POLICY "Users can insert own price alerts"
    ON public.price_alerts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own price alerts" ON public.price_alerts;
CREATE POLICY "Users can update own price alerts"
    ON public.price_alerts FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own price alerts" ON public.price_alerts;
CREATE POLICY "Users can delete own price alerts"
    ON public.price_alerts FOR DELETE
    USING (auth.uid() = user_id);
