-- A prior maintenance op dropped the INSERT/UPDATE/DELETE policies on the core
-- trading tables, leaving only SELECT. With RLS enabled this blocked all
-- writes (holdings insert failed with 42501; orders/profiles/fo_positions were
-- equally exposed). Restore the original owner-only write policies exactly as
-- captured in the June-20 policy backup.

-- orders: users insert/update their own
drop policy if exists "Users can insert own orders" on public.orders;
create policy "Users can insert own orders"
  on public.orders for insert
  with check (auth_uid() = user_id);

drop policy if exists "Users can update their own orders" on public.orders;
create policy "Users can update their own orders"
  on public.orders for update
  using (auth_uid() = user_id);

-- profiles: users update their own row (restores prior trusted behavior;
-- server-side money gating remains a separate, planned hardening task)
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  using (auth_uid() = id);

-- fo_positions: owner-only insert/update/delete (authenticated role)
drop policy if exists "Users can insert own fo_positions" on public.fo_positions;
create policy "Users can insert own fo_positions"
  on public.fo_positions for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own fo_positions" on public.fo_positions;
create policy "Users can update own fo_positions"
  on public.fo_positions for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own fo_positions" on public.fo_positions;
create policy "Users can delete own fo_positions"
  on public.fo_positions for delete to authenticated
  using ((select auth.uid()) = user_id);
