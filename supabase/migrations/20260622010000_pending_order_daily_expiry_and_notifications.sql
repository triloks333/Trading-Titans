-- #2 + #5: Indian-market (non-crypto) pending orders must not carry overnight.
-- Cancel them at 3:40 PM IST and notify the user; also warn shortly before.

-- Cancel all non-crypto pending orders and notify each affected user.
create or replace function public.expire_pending_stock_orders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  with cancelled as (
    update public.orders
       set status = 'cancelled'
     where status in ('pending', 'executing')
       and coalesce(market, 'stock') <> 'crypto'
    returning user_id, symbol, side
  ),
  notif as (
    insert into public.notifications (user_id, title, body, is_read, action_type, action_data)
    select user_id,
           'Order expired',
           'Your pending ' || upper(side) || ' order for ' || symbol ||
           ' was cancelled at market close (3:40 PM). You can place it again tomorrow.',
           false, 'order',
           jsonb_build_object('symbol', symbol, 'view', 'orders')
    from cancelled
    returning 1
  )
  select count(*) into v_count from cancelled;
  return v_count;
end;
$$;

-- Pre-close heads-up: one notification per user who still has pending orders.
create or replace function public.notify_pending_orders_expiring_soon()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  with pend as (
    select user_id, count(*) as cnt
    from public.orders
    where status = 'pending' and coalesce(market, 'stock') <> 'crypto'
    group by user_id
  ),
  notif as (
    insert into public.notifications (user_id, title, body, is_read, action_type, action_data)
    select user_id,
           'Pending orders expiring soon',
           'You have ' || cnt || ' pending order' || (case when cnt > 1 then 's' else '' end) ||
           ' that will be cancelled at 3:40 PM if not executed. Tap to review.',
           false, 'order',
           jsonb_build_object('view', 'orders')
    from pend
    returning 1
  )
  select count(*) into v_count from pend;
  return v_count;
end;
$$;

revoke all on function public.expire_pending_stock_orders() from public, anon, authenticated;
revoke all on function public.notify_pending_orders_expiring_soon() from public, anon, authenticated;

-- Schedule (IST = UTC+5:30): warn at 3:25 PM IST (09:55 UTC), expire at 3:40 PM IST (10:10 UTC), weekdays.
select cron.schedule('notify-pending-expiring-soon', '55 9 * * 1-5', $cron$ select public.notify_pending_orders_expiring_soon(); $cron$);
select cron.schedule('expire-pending-stock-orders', '10 10 * * 1-5', $cron$ select public.expire_pending_stock_orders(); $cron$);
