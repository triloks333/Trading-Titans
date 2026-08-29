-- Drop orphaned `quotes_cache` rows as part of the existing daily retention run.
--
-- `refresh-quotes` only rewrites symbols that are still in its universe (holdings
-- + watchlists + pending orders + alerts + the popular lists) AND whose market is
-- open. A symbol that leaves the universe keeps its last row forever, so the table
-- accumulates entries frozen at a price from weeks ago. Production had rows over
-- 1000 hours old, and that is what the engine tripped over when the AEROENTER
-- limit was never filled.
--
-- The engine now refuses a quote older than 10 minutes and fetches a live one
-- instead, so these rows are no longer dangerous — but they are still misleading
-- to anyone reading the table, and a missing row now takes the same live-fetch
-- path as a stale one, which makes deleting them strictly better than keeping
-- them. Folded into `run_data_retention()` rather than given its own cron: it
-- already runs daily at 20:00 UTC and this is the same kind of work.
--
-- 14 days, not 1: the window has to survive a long exchange holiday plus a
-- weekend without evicting a symbol somebody still holds.

create or replace function public.run_data_retention()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  archive_after  interval := interval '12 months';
  purge_after    interval := interval '18 months';
  notif_after    interval := interval '90 days';
  quote_after    interval := interval '14 days';
  archived_count int := 0;
  purged_orders  int := 0;
  purged_notifs  int := 0;
  purged_buckets int := 0;
  purged_quotes  int := 0;
begin
  with moved as (
    delete from public.orders o
    where o.created_at < now() - archive_after
      and o.status not in ('pending','executing')
    returning o.*
  )
  insert into public.orders_archive
  select m.*, now() as archived_at from moved m;
  get diagnostics archived_count = row_count;

  delete from public.orders_archive a
  where a.created_at < now() - purge_after;
  get diagnostics purged_orders = row_count;

  delete from public.notifications n
  where n.is_read = true
    and n.created_at < now() - notif_after;
  get diagnostics purged_notifs = row_count;

  -- Drop stale rate-limit buckets (anything not touched in the last day).
  delete from public.rate_limits
  where window_start < now() - interval '1 day';
  get diagnostics purged_buckets = row_count;

  -- Drop quote rows nothing has refreshed in a fortnight. Anything still in the
  -- refresh universe is rewritten every minute its market is open, so a row this
  -- old belongs to a symbol no user references any more.
  delete from public.quotes_cache q
  where q.updated_at < now() - quote_after;
  get diagnostics purged_quotes = row_count;

  return jsonb_build_object(
    'archived_orders', archived_count,
    'purged_archived_orders', purged_orders,
    'purged_read_notifications', purged_notifs,
    'purged_rate_buckets', purged_buckets,
    'purged_stale_quotes', purged_quotes,
    'ran_at', now()
  );
end;
$function$;
