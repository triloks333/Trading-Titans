-- Create charge configurations table
CREATE TABLE IF NOT EXISTS public.charge_configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    config JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS for charge_configurations
ALTER TABLE public.charge_configurations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read charge configurations"
    ON public.charge_configurations FOR SELECT
    USING (auth.uid() IS NOT NULL);

CREATE POLICY "Only admins can modify configurations"
    ON public.charge_configurations FOR ALL
    USING ((SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true);

-- Add charge-tracking columns to orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS charge_config_id UUID REFERENCES public.charge_configurations(id) ON DELETE RESTRICT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS brokerage NUMERIC NOT NULL DEFAULT 0.0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS stamp_duty NUMERIC NOT NULL DEFAULT 0.0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_charges NUMERIC NOT NULL DEFAULT 0.0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_charges NUMERIC NOT NULL DEFAULT 0.0;

-- Insert initial charge configuration
INSERT INTO public.charge_configurations (config) VALUES (
    '{
        "equity_brokerage_rate": 0.0005,
        "equity_brokerage_max": 20.00,
        "fo_brokerage_flat": 20.00,
        "stamp_duty_delivery": 0.00015,
        "stamp_duty_intraday": 0.00003,
        "stamp_duty_options": 0.00003,
        "stamp_duty_futures": 0.00002,
        "stt_delivery": 0.001,
        "stt_intraday_sell": 0.00025,
        "stt_options_sell": 0.000625,
        "stt_futures_sell": 0.000125,
        "exchange_delivery": 0.0000322,
        "exchange_options": 0.00053,
        "exchange_futures": 0.000019,
        "gst_rate": 0.18
    }'::jsonb
);
