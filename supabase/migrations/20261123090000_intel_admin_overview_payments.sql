-- Admin Intelligence: show real payments, not only client telemetry.
--
-- The "Purchase succeeded" funnel row was built only from the app's
-- paywall_step telemetry. A purchase from an app build without telemetry, or
-- one finished in the browser, never sent that event, so a real paid order
-- (payment_orders.status = 'paid', settled by razorpay-webhook) did not show.
-- This adds server-truth payment numbers and a recent-payments list to the
-- overview the admin screen already polls every 30 s.
create or replace function public.intel_admin_overview()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp stable
as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return jsonb_build_object(
    'users_active_5m',  (select count(distinct user_id) from public.intel_events where created_at > now() - interval '5 minutes'),
    'users_active_24h', (select count(distinct user_id) from public.intel_events where created_at > now() - interval '24 hours'),
    'users_with_state', (select count(*) from public.intel_user_state),
    'events_1h',  (select count(*) from public.intel_events where created_at > now() - interval '1 hour'),
    'events_24h', (select count(*) from public.intel_events where created_at > now() - interval '24 hours'),
    'apologies_7d', (select count(*) from public.intel_apology_credits where created_at > now() - interval '7 days'),
    'reactions_delivered_24h', (select count(*) from public.intel_reaction_firings where delivered and created_at > now() - interval '24 hours'),
    'reactions_suppressed_24h', (select count(*) from public.intel_reaction_firings where not delivered and created_at > now() - interval '24 hours'),
    'events_by_name_24h', (select coalesce(jsonb_object_agg(name, n), '{}') from (
        select name, count(*) n from public.intel_events
        where created_at > now() - interval '24 hours' group by name order by n desc limit 40) e),
    'events_per_minute_60m', (select coalesce(jsonb_agg(jsonb_build_array(m, n) order by m), '[]') from (
        select date_trunc('minute', created_at) m, count(*) n from public.intel_events
        where created_at > now() - interval '60 minutes' group by 1) t),
    'payments_paid_24h', (select count(*) from public.payment_orders
        where status = 'paid' and coalesce(paid_at, created_at) > now() - interval '24 hours'),
    'payments_paid_30d', (select count(*) from public.payment_orders
        where status = 'paid' and coalesce(paid_at, created_at) > now() - interval '30 days'),
    'payments_revenue_paise_30d', (select coalesce(sum(amount_paise), 0) from public.payment_orders
        where status = 'paid' and currency = 'INR' and coalesce(paid_at, created_at) > now() - interval '30 days'),
    'payments_failed_30d', (select count(*) from public.payment_orders
        where status = 'failed' and created_at > now() - interval '30 days'),
    'payments_checkouts_30d', (select count(*) from public.payment_orders
        where created_at > now() - interval '30 days'),
    'payments_recent', (select coalesce(jsonb_agg(r order by r.at desc), '[]') from (
        select o.user_id, o.sku, o.kind, o.amount_paise, o.currency,
               coalesce(o.paid_at, o.created_at) as at, o.credited_at is not null as credited,
               coalesce(nullif(trim(p.name), ''), p.email) as name
        from public.payment_orders o left join public.profiles p on p.id = o.user_id
        where o.status = 'paid'
        order by coalesce(o.paid_at, o.created_at) desc limit 20) r)
  );
end $$;
revoke all on function public.intel_admin_overview() from public, anon;
grant execute on function public.intel_admin_overview() to authenticated;
