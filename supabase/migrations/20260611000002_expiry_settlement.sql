SELECT cron.schedule(
  'expire_fo_positions_post_market',
  '5 10 * * 2,4',  -- Tuesdays and Thursdays 15:35 IST (10:05 UTC)
  $$ SELECT net.http_post(
       url := current_setting('app.supabase_functions_url') || '/settle-expired-positions',
       headers := jsonb_build_object(
         'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
         'Content-Type', 'application/json'
       ),
       body := '{}'::jsonb
     ); $$
);
