-- #1: serve REAL NSE option strikes (from instruments) instead of synthetic
-- ones. Returns the near-ATM strikes for the nearest expiries; the client
-- prices them with the same Black-Scholes estimator used by the fill engine so
-- the displayed price always matches the fill/position price.
create or replace function public.get_option_chain_strikes(
  p_underlying text,
  p_spot numeric,
  p_strike_count int default 25
)
returns table(expiry_date date, strike_price numeric, lot_size int)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with base as (
    select i.expiry_date::date as ed, i.strike_price, i.lot_size
    from public.instruments i
    where i.instrument_type = 'OPTION'
      and i.symbol ~ ('^NSE:' || p_underlying || '[0-9]')
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
$$;

revoke all on function public.get_option_chain_strikes(text, numeric, int) from public;
grant execute on function public.get_option_chain_strikes(text, numeric, int) to authenticated, anon;
