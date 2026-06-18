-- Feature: notification-sounds-and-forced-update (Requirement 11.2)
-- Seed the version-gating keys into the existing app_config (key text, value text)
-- key/value table. Initial values are intentionally non-gating (fail-open safe):
-- min_supported_version and latest_version are 1.0.0, below the current app
-- version (1.0.5), so no user is gated until these are raised. maintenance_mode
-- is off. Idempotent upsert so re-running is safe.
--
-- update_url uses the real applicationId from android/app/build.gradle.kts
-- (com.kwm.tradingtitans). Raise min_supported_version / latest_version here (or
-- via the dashboard) to activate hard/soft update prompts for older clients.
INSERT INTO public.app_config (key, value) VALUES
  ('min_supported_version', '1.0.0'),
  ('latest_version',        '1.0.0'),
  ('update_url',            'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans'),
  ('latest_version_notes',  ''),
  ('maintenance_mode',      'false'),
  ('maintenance_message',   '')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
