-- Real expiries for BSE index options (SENSEX, BANKEX).
--
-- sync-instruments now also loads the Fyers BSE_FO master, so SENSEX and BANKEX
-- contracts land in `instruments` as `BSE:SENSEX...`. This RPC only matched
-- `^NSE:`, so SENSEX had no strikes, the app fell back to the market-options
-- estimate, and users saw three made-up "last Thursday" monthlies instead of
-- the real weekly Thursday expiries. Only the exchange prefix changes.
--
-- Also retires the weekly `fo-expiry-update` cron. Its function looked up
-- `instruments.name = 'NIFTY'`, but names are like 'NIFTY 25 Jan 27 30850 CE',
-- so it never matched a row and `fo_expiry_config` has stayed empty; nothing
-- reads that table.

create or replace function public.get_option_chain_strikes(
  p_underlying text,
  p_spot numeric,
  p_strike_count integer default 25
)
returns table(expiry_date date, strike_price numeric, lot_size integer)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with und as (
    select public.fo_contract_underlying(p_underlying) as u
  ),
  base as (
    select i.expiry_date::date as ed, i.strike_price, i.lot_size
    from public.instruments i
    cross join und
    where i.instrument_type = 'OPTION'
      and i.symbol ~ ('^(NSE|BSE):' || und.u || '[0-9]')
      and i.expiry_date::date >= current_date
  ),
  exps as (
    select distinct ed from base order by ed limit 4
  ),
  ranked as (
    select b.ed, b.strike_price, max(b.lot_size) as lot_size,
           row_number() over (
             partition by b.ed order by abs(b.strike_price - coalesce(p_spot, 0))
           ) as rn
    from base b
    join exps e on e.ed = b.ed
    group by b.ed, b.strike_price
  )
  select ed as expiry_date, strike_price, lot_size
  from ranked
  where rn <= greatest(coalesce(p_strike_count, 25), 1)
  order by ed, strike_price;
$function$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'fo-expiry-update') then
    perform cron.unschedule('fo-expiry-update');
  end if;
end $$;
