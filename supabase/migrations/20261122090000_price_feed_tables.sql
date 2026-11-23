-- Fast price feed (price-feed edge function): state, browsed symbols.
--
-- price_feed_state  one row. Holds the lease of the run currently looping (so two
--                   overlapping cron runs never both fetch) and its heartbeat:
--                   last tick time, rows written, symbols missed, errors.
-- hot_symbols       symbols someone opened in the app recently that nobody holds
--                   or watches. price-feed adds them to its universe for 10 min,
--                   so a browsed stock moves live instead of waiting for a
--                   per-symbol fetch. Written only through note_hot_symbol().
--
-- Reversible: drop function public.note_hot_symbol(text, text);
--             drop table public.hot_symbols, public.price_feed_state;

create table if not exists public.price_feed_state (
  id             int primary key default 1 check (id = 1),
  run_id         uuid,
  run_started_at timestamptz,
  last_tick_at   timestamptz,
  last_tick_ms   int,
  last_rows      int,
  last_missing   text[],
  last_errors    text[],
  yahoo_ms       int,
  crypto_ms      int,
  ticks          int
);
alter table public.price_feed_state enable row level security;
-- Heartbeat is readable by the app (to show "prices delayed"); writes are
-- service-role only (no policy).
drop policy if exists "Price feed heartbeat: read" on public.price_feed_state;
create policy "Price feed heartbeat: read" on public.price_feed_state
  for select to anon, authenticated using (true);
insert into public.price_feed_state (id) values (1) on conflict (id) do nothing;

create table if not exists public.hot_symbols (
  symbol  text not null check (char_length(symbol) between 1 and 40),
  market  text not null check (char_length(market) between 1 and 20),
  seen_at timestamptz not null default now(),
  primary key (symbol, market)
);
create index if not exists hot_symbols_seen_at_idx on public.hot_symbols (seen_at desc);
alter table public.hot_symbols enable row level security;
revoke all on public.hot_symbols from anon, authenticated;

create or replace function public.note_hot_symbol(p_symbol text, p_market text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.hot_symbols (symbol, market, seen_at)
  select upper(trim(p_symbol)), lower(trim(p_market)), now()
  where char_length(trim(coalesce(p_symbol, ''))) between 1 and 40
    and lower(trim(coalesce(p_market, ''))) in
        ('stock', 'crypto', 'us_stock', 'commodity', 'pakistan_stock', 'italy_stock')
  on conflict (symbol, market) do update set seen_at = excluded.seen_at;
$$;
revoke all on function public.note_hot_symbol(text, text) from public, anon;
grant execute on function public.note_hot_symbol(text, text) to authenticated;
