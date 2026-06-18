-- SQL Migration: Add App Version and Maintenance Configs to app_config table

INSERT INTO app_config (key, value) VALUES
  ('min_supported_version', '1.0.0'),
  ('latest_version', '1.0.2'),
  ('latest_version_notes', '• Standardized option calculations and portfolio metrics using Black-Scholes\n• Uniform metrics showing Avg, Invested, P&L, and Day P&L\n• Added support for password recovery reset page'),
  ('update_url', 'https://play.google.com/store/apps/details?id=io.supabase.tradingtitans'),
  ('maintenance_mode', 'false'),
  ('maintenance_message', 'We are currently performing system upgrades. We will be back online shortly!')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Enable RLS on app_config for safety and allow public read-only select
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_config_read_public"
  ON app_config FOR SELECT
  TO public
  USING (true);
