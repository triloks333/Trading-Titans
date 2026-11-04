-- Multiple watchlists, each with a name and colour, and sections inside a list.
--
-- Built on the existing `watchlist` table rather than replacing it, because every
-- shipped app upserts into it `on conflict (user_id, symbol, market)`. That
-- unique key stays, which is also the limit of this design: a stock sits in ONE
-- list at a time (adding it to another list moves it).
-- shortcut: lift that by changing the key to (watchlist_id, symbol, market) once
-- every app in use is 1.2.14+, since older apps' upserts need the old key.
--
-- A row with `watchlist_id` null belongs to the user's FIRST list. That is where
-- older apps, and the star button, put new stocks, so nothing needs backfilling.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.watchlists                 new table, own-rows RLS
--   public.watchlist.watchlist_id     new column, FK, cascade on list delete
--   public.watchlist.section          new column, a heading inside a list
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Additive. Older apps ignore both columns and keep working.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   alter table public.watchlist drop column if exists section;
--   alter table public.watchlist drop column if exists watchlist_id;
--   drop table if exists public.watchlists;

create table if not exists public.watchlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 30),
  color text not null default '#3B82F6' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists watchlists_user_idx on public.watchlists (user_id, sort_order);

alter table public.watchlists enable row level security;

drop policy if exists watchlists_own_select on public.watchlists;
create policy watchlists_own_select on public.watchlists
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists watchlists_own_insert on public.watchlists;
create policy watchlists_own_insert on public.watchlists
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists watchlists_own_update on public.watchlists;
create policy watchlists_own_update on public.watchlists
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists watchlists_own_delete on public.watchlists;
create policy watchlists_own_delete on public.watchlists
  for delete to authenticated using (auth.uid() = user_id);

grant select, insert, update, delete on public.watchlists to authenticated;

alter table public.watchlist
  add column if not exists watchlist_id uuid references public.watchlists(id) on delete cascade,
  add column if not exists section text check (section is null or char_length(section) <= 30);
