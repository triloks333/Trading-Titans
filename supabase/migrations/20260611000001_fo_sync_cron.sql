SELECT cron.schedule(
  'sync_fo_instruments_daily',
  '30 2 * * 1-5',   -- Mon–Fri, 08:00 IST (02:30 UTC)
  $$ SELECT net.http_post(
       url := current_setting('app.supabase_functions_url') || '/sync-fo-instruments',
       headers := jsonb_build_object(
         'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
         'Content-Type', 'application/json'
       ),
       body := '{}'::jsonb
     ); $$
);
