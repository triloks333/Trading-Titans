-- Bug 1 (order-notifications-and-runaway-lots-fix): the notify_order_executed()
-- trigger remains the SINGLE canonical source of the executed-fill notification.
-- The redundant client-side Dart "Order Executed" notifications inserts were
-- removed in the app (supabase_service.dart F&O/equity placeOrder + both pending
-- paths), so each executed-order write now produces exactly one feed row from
-- this trigger.
--
-- This migration ONLY trims the trailing space in the notification titles for
-- clean, consistent wording. The firing condition (status change to
-- 'filled'/'executed') and the body are unchanged, so every executed-order write
-- still produces exactly one feed row (Req 3.2 preserved). Additive/idempotent
-- (CREATE OR REPLACE); search_path is kept pinned to 'public'.
CREATE OR REPLACE FUNCTION public.notify_order_executed()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only trigger on status change to 'filled' or 'executed'
  IF NEW.status IN ('filled', 'executed') AND (OLD.status IS NULL OR OLD.status != NEW.status) THEN
    INSERT INTO public.notifications (user_id, title, body, action_type, action_data)
    VALUES (
      NEW.user_id,
      CASE NEW.side
        WHEN 'buy' THEN 'Buy Order Executed'
        WHEN 'sell' THEN 'Sell Order Executed'
        ELSE 'Order Executed'
      END,
      'Your ' || NEW.side || ' order for ' || COALESCE(NEW.quantity::text, '0') || ' ' ||
      COALESCE(REPLACE(REPLACE(NEW.symbol, 'NSE:', ''), '-EQ', ''), 'Unknown') ||
      ' at ₹' || COALESCE(NEW.price::text, '0') || ' has been executed.',
      'order',
      jsonb_build_object('order_id', NEW.id, 'symbol', NEW.symbol, 'side', NEW.side)
    );
  END IF;
  RETURN NEW;
END;
$function$;
