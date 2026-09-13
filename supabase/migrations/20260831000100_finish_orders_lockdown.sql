-- DO NOT APPLY YET.
--
-- Second half of the orders write-lockdown. Removes the last client write path
-- (status pending -> cancelled) so cancel-order becomes the only way to cancel.
--
-- PRECONDITION: release adoption. 20260831000000 deliberately kept the narrow
-- cancel path alive because the Android app ships through Play and cannot be
-- force-updated, so an already-installed build would otherwise lose Cancel for
-- good. Apply this only once the release that routes Cancel through cancel-order
-- has reached effectively all active users.
--
-- Check adoption before applying. `min_supported_version` in app_config is the
-- hard gate; once it is at or above the release carrying cancel-order, no client
-- that needs this policy can still be running:
--
--     select key, value from app_config
--      where key in ('min_supported_version', 'latest_version');
--
-- After applying, a client's only remaining privilege on `orders` is SELECT.

drop policy if exists "orders_owner_may_cancel_only" on public.orders;
revoke update (status) on public.orders from authenticated;

comment on table public.orders is
  'Server-written. Clients may only SELECT their own rows; every mutation goes '
  'through the place-order, modify-order and cancel-order edge functions.';
