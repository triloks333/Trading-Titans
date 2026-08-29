-- The bhavcopy import died with "numeric field overflow".
--
-- Once the NSE download was fixed (see supabase/functions/sync-nse-bhavcopy), the
-- import got as far as Postgres and then failed on a value that did not fit.
-- `volume_value` was numeric(15,2), so it capped total turnover at ~₹1e13, and a
-- single heavily traded index option series clears that on a busy day.
--
-- These columns hold values from an external feed whose magnitude this project
-- does not control, so pinning a precision on them buys nothing and guarantees a
-- silent outage the first time NSE prints a bigger number. Unconstrained `numeric`
-- is the correct type here; the old precisions were arbitrary.
--
-- Widening only: no existing value can fail to fit, so this is safe on a populated
-- table and does not rewrite it (Postgres skips the rewrite when a numeric loses
-- its typmod).

alter table public.nse_fo_bhavcopy
  alter column strike_price  type numeric,
  alter column open_price    type numeric,
  alter column high_price    type numeric,
  alter column low_price     type numeric,
  alter column close_price   type numeric,
  alter column last_price    type numeric,
  alter column settle_price  type numeric,
  alter column prev_close    type numeric,
  alter column volume_value  type numeric;

comment on column public.nse_fo_bhavcopy.volume_value is
  'TtlTrfVal from the NSE UDiFF bhavcopy: total turnover in rupees. Deliberately unconstrained numeric -- a fixed precision here caused import failures.';
