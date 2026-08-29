-- A derivative CONTRACT symbol was reaching the option-chain RPCs verbatim.
--
-- Tapping through from a futures contract passed `ONGC26OCTFUT` as the
-- underlying. `get_option_chain_strikes` matches `^NSE:<underlying>[0-9]`, so
-- that matched no strikes, the client fell through to `market-options`, and
-- because the Fyers and Zerodha providers have no live credentials the user was
-- shown "Verify Fyers/Zerodha auth" over a ₹0.00 spot -- an auth error for what
-- is really a symbol-shape bug.
--
-- Normalising inside the RPC rather than in the client is deliberate: it fixes
-- the already-shipped app with no release.

-- Deliberately NOT the same thing as the app's `extractUnderlying`, which splits
-- on the first hyphen and truncates at the first digit. That is too aggressive
-- for a general normaliser: it turns the real NSE underlying `BAJAJ-AUTO` into
-- `BAJAJ`. This only rewrites a symbol that is unambiguously a contract --
-- letters, then digits, then a FUT/CE/PE tail -- and returns everything else
-- untouched, so `BAJAJ-AUTO`, `RELIANCE` and `360ONE` all pass through.
create or replace function public.fo_contract_underlying(p_symbol text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select regexp_replace(
           upper(btrim(coalesce(p_symbol, ''))),
           '^([A-Z][A-Z&-]*?)[0-9].*(FUT|CE|PE)$',
           '\1'
         );
$$;

comment on function public.fo_contract_underlying(text) is
  'Maps a derivative contract symbol (ONGC26OCTFUT, NIFTY26SEP24000CE) to its underlying. Returns non-contract symbols unchanged.';

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
      and i.symbol ~ ('^NSE:' || und.u || '[0-9]')
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

create or replace function public.get_option_chain_quotes(
  p_underlying text,
  p_spot numeric,
  p_strike_count integer default 25
)
returns table(
  expiry_date date, strike_price numeric, lot_size integer,
  ce_oi bigint, ce_close numeric, pe_oi bigint, pe_close numeric
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with und as (
    select public.fo_contract_underlying(p_underlying) as u
  ),
  latest as (
    select max(b.trading_date) as d
    from public.nse_fo_bhavcopy b
    cross join und
    where b.symbol = und.u
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
    cross join und
    where b.symbol = und.u
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
$function$;
