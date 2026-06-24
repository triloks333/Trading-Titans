-- Option A: serve REAL open interest + REAL end-of-day close per strike from the
-- daily NSE F&O bhavcopy. The client keeps the tradeable LTP on the live-spot
-- Black-Scholes model (so it moves intraday and matches the fill engine), but
-- shows genuine OI (real PCR/Max-Pain/OI bars) and a real prior-close anchor.
create or replace function public.get_option_chain_quotes(
  p_underlying text,
  p_spot numeric,
  p_strike_count int default 25
)
returns table(
  expiry_date date,
  strike_price numeric,
  lot_size int,
  ce_oi bigint,
  ce_close numeric,
  pe_oi bigint,
  pe_close numeric
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with latest as (
    select max(trading_date) as d
    from public.nse_fo_bhavcopy
    where symbol = p_underlying
  ),
  base as (
    select b.expiry_date::date as ed,
           b.strike_price,
           max(b.lot_size) as lot_size,
           max(case when b.option_type = 'CE' then b.open_interest end) as ce_oi,
           max(case when b.option_type = 'CE' then b.close_price end)   as ce_close,
           max(case when b.option_type = 'PE' then b.open_interest end) as pe_oi,
           max(case when b.option_type = 'PE' then b.close_price end)   as pe_close
    from public.nse_fo_bhavcopy b
    cross join latest
    where b.symbol = p_underlying
      and b.trading_date = latest.d
      and b.option_type in ('CE', 'PE')
      and b.expiry_date::date >= current_date
    group by b.expiry_date::date, b.strike_price
  ),
  exps as (
    select distinct ed from base order by ed limit 4
  ),
  ranked as (
    select base.*,
           row_number() over (
             partition by base.ed order by abs(base.strike_price - coalesce(p_spot, 0))
           ) as rn
    from base
    join exps on exps.ed = base.ed
  )
  select ed, strike_price, lot_size, ce_oi, ce_close, pe_oi, pe_close
  from ranked
  where rn <= greatest(coalesce(p_strike_count, 25), 1)
  order by ed, strike_price;
$$;

revoke all on function public.get_option_chain_quotes(text, numeric, int) from public;
grant execute on function public.get_option_chain_quotes(text, numeric, int) to authenticated, anon;
