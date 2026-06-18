-- Enable cron extension if not already present
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove existing schedules if they exist to prevent duplicates
SELECT cron.unschedule('sync_nse_contract_daily');
SELECT cron.unschedule('sync_nse_bhavcopy_daily');

-- Sync NSE Contract daily at 08:30 AM IST (03:00 UTC) before market opens
SELECT cron.schedule(
  'sync_nse_contract_daily',
  '0 3 * * 1-5',   -- Mon–Fri, 03:00 UTC (08:30 IST)
  $$ SELECT net.http_post(
       url := current_setting('app.supabase_functions_url') || '/functions/v1/sync-nse-contract',
       headers := jsonb_build_object(
         'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
         'Content-Type', 'application/json'
       ),
       body := '{}'::jsonb
     ); $$
);

-- Sync NSE Bhavcopy daily at 06:30 PM IST (13:00 UTC) after market close and files are generated
SELECT cron.schedule(
  'sync_nse_bhavcopy_daily',
  '30 13 * * 1-5',  -- Mon–Fri, 13:30 UTC (19:00 IST)
  $$ SELECT net.http_post(
       url := current_setting('app.supabase_functions_url') || '/functions/v1/sync-nse-bhavcopy',
       headers := jsonb_build_object(
         'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
         'Content-Type', 'application/json'
       ),
       body := '{}'::jsonb
     ); $$
);
