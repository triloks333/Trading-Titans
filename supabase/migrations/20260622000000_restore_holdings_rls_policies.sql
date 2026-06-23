-- URGENT FIX: the holdings table had only a SELECT policy left after a prior
-- maintenance op dropped its write policies, so every buy order failed with
-- "new row violates row-level security policy for table holdings" (42501).
-- Restore the owner-only INSERT/UPDATE/DELETE policies to match the backup and
-- the equivalent (working) policies on public.orders / public.watchlist.

drop policy if exists "Users can insert own holdings" on public.holdings;
create policy "Users can insert own holdings"
  on public.holdings
  for insert
  with check (auth_uid() = user_id);

drop policy if exists "Users can update own holdings" on public.holdings;
create policy "Users can update own holdings"
  on public.holdings
  for update
  using (auth_uid() = user_id);

drop policy if exists "Users can delete own holdings" on public.holdings;
create policy "Users can delete own holdings"
  on public.holdings
  for delete
  using (auth_uid() = user_id);
