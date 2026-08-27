-- Give SENSEX derivatives a real lot size. They were resolving to 1 against a
-- true BSE lot of 20.
--
-- WHY IT WAS BROKEN
-- Both lot-size resolvers look the contract up in `instruments` with
--   LIKE 'NSE:<underlying>%' AND instrument_type IN ('OPTION','FUTURE')
-- and `extractUnderlying` maps '^BSESN' -> 'SENSEX'. But SENSEX is a BSE index and
-- is absent from the Fyers NSE_FO.csv feed that sync-instruments loads, so there
-- are ZERO Sensex derivative rows. The eight existing '%SENSEX%' rows are all
-- ETFs (NSE:SENSEXETF-EQ and friends) with instrument_type EQUITY, which the
-- OPTION/FUTURE filter correctly excludes. With no rows matched, both resolvers
-- fall through to their `return 1` default.
--
-- This is NOT theoretical. Sensex derivatives are reachable because the option
-- chain for indices is generated synthetically rather than from `instruments`,
-- and they have been traded:
--   * 2 executed '^BSESN JUN FUT' orders (Jun 2026)
--   * 1 executed '^BSESN-2026-08-27-77600-CE' order, still OPEN, carrying
--     lot_size 1
--
-- BSE raised the Sensex lot from 10 to 20 (and Bankex 15 to 30); Sensex remains
-- 20 through 2026.
--
-- WHY A REFERENCE ROW RATHER THAN A CODE FIX
-- The Flutter client carries its own copy of this lookup at
-- fo_instruments_service.dart and cannot be changed without an app release. If
-- only the server-side resolver were corrected the two would disagree: the app
-- would offer a quantity in units of 1 while the engine priced in units of 20, and
-- `trunc(quantity / lotSize)` would silently resize the order. Putting the lot
-- size in the data fixes BOTH resolvers at once, with no update.
--
-- The row is safe to add:
--   * tradeable = false keeps it out of market-search, which filters on tradeable.
--   * getAvailableExpiries / getAvailableStrikes are the only other readers of
--     this list in the app and both are dead code -- defined, never called -- so
--     no expiry or strike picker can be polluted by it.
--   * sync-instruments loads the NSE feed only, which never contains SENSEX, so it
--     will neither overwrite nor delete this row.
--   * The symbol keeps a digit immediately after the underlying so the new exact
--     boundary filter in _shared/lot_size.ts retains it while still excluding the
--     SENSEX*-EQ ETFs.
--
-- ponytail: one row, not a BSE contract-master integration. The ceiling is that
-- it carries a single lot size for every Sensex expiry -- correct today, since BSE
-- uses a uniform 20 -- and that it must be updated by hand if BSE revises it. The
-- upgrade path is a real BSE contract feed in sync-instruments. Do NOT delete this
-- row without also fixing both resolvers, or Sensex silently returns to lot 1.
--
-- BANKEX is deliberately NOT added: nothing in the app maps an underlying to
-- BANKEX, no order or position has ever referenced it, so it is unreachable.
--
-- ROLLBACK: delete from public.instruments where symbol = 'NSE:SENSEX26SEPFUT';
insert into public.instruments
  (fyers_token, symbol, name, market, instrument_type, expiry_date,
   strike_price, option_type, lot_size, tradeable)
values
  ('bse-sensex-lotref', 'NSE:SENSEX26SEPFUT',
   'BSE SENSEX - lot size reference (not tradeable)',
   'stock', 'FUTURE', '2026-09-29', null, null, 20, false)
-- `instruments` is keyed on fyers_token (there is no unique index on symbol), so
-- the fixed sentinel token is what makes this migration idempotent.
on conflict (fyers_token) do update
  set symbol = excluded.symbol,
      lot_size = excluded.lot_size,
      name = excluded.name,
      tradeable = excluded.tradeable;
