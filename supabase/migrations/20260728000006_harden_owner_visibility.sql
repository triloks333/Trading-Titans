-- Keep the four declared owners authoritative and make document changes live.
create or replace function public.kv_bootstrap_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  canonical_email text;
  invited_role text;
begin
  select lower(email) into canonical_email from auth.users where id = new.id;
  if canonical_email is null then
    raise exception 'Authenticated account not found';
  end if;

  new.email := canonical_email;
  new.status := 'active';
  if canonical_email = any (array[
    'pawan.2u2@gmail.com', 'triloks34@gmail.com',
    'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com'
  ]) then
    new.role := 'owner';
    return new;
  end if;

  select role into invited_role
  from public.kv_invites
  where lower(email) = canonical_email and accepted_at is null
  order by created_at desc limit 1 for update;
  if invited_role is null then
    raise exception 'This account has not been invited to KASHIVWEALTH VAULT';
  end if;

  new.role := invited_role;
  update public.kv_invites set accepted_at = now()
  where lower(email) = canonical_email and accepted_at is null;
  return new;
end
$$;

revoke all on function public.kv_bootstrap_member() from public, anon, authenticated;
create or replace function public.kv_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when lower(u.email) = any (array[
      'pawan.2u2@gmail.com', 'triloks34@gmail.com',
      'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com'
    ]) then 'owner'
    else m.role
  end
  from public.kv_members m
  join auth.users u on u.id = m.id
  where m.id = auth.uid()
    and (m.status = 'active' or lower(u.email) = any (array[
      'pawan.2u2@gmail.com', 'triloks34@gmail.com',
      'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com'
    ]))
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

revoke all on function public.kv_role() from public, anon;
grant execute on function public.kv_role() to authenticated, service_role;

create or replace function public.kv_guard_member_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare canonical_email text;
begin
  select lower(email) into canonical_email from auth.users where id = new.id;
  if canonical_email is null then
    raise exception 'Authenticated account not found';
  end if;

  if new.id = auth.uid() and public.kv_role() <> 'owner'
     and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'Only an owner can change member roles or status';
  end if;

  new.email := canonical_email;
  if canonical_email = any (array[
    'pawan.2u2@gmail.com', 'triloks34@gmail.com',
    'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com'
  ]) then
    new.role := 'owner';
    new.status := 'active';
  end if;
  return new;
end
$$;

revoke all on function public.kv_guard_member_identity() from public, anon, authenticated;
drop trigger if exists kv_members_guard_identity on public.kv_members;
create trigger kv_members_guard_identity before update on public.kv_members
for each row execute function public.kv_guard_member_identity();

insert into public.kv_members (id, email, full_name, role, status)
select id, lower(email),
       coalesce(raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name'),
       'owner', 'active'
from auth.users
where lower(email) = any (array[
  'pawan.2u2@gmail.com', 'triloks34@gmail.com',
  'mr.engineer5000@gmail.com', 'manavagg2003@gmail.com'
])
on conflict (id) do update
set email = excluded.email, role = 'owner', status = 'active';

drop policy if exists kv_members_update on public.kv_members;
create policy kv_members_update on public.kv_members for update to authenticated
  using (public.kv_is_owner() or (id = auth.uid() and public.kv_is_member()))
  with check (public.kv_is_owner() or (id = auth.uid() and public.kv_is_member()));

drop policy if exists kv_invites_insert on public.kv_invites;
create policy kv_invites_insert on public.kv_invites for insert to authenticated
  with check (invited_by = auth.uid() and (
    public.kv_is_owner() or (public.kv_role() = 'admin' and role <> 'owner')
  ));

drop policy if exists kv_invites_update on public.kv_invites;
create policy kv_invites_update on public.kv_invites for update to authenticated
  using (public.kv_is_owner() or (public.kv_role() = 'admin' and role <> 'owner'))
  with check (public.kv_is_owner() or (public.kv_role() = 'admin' and role <> 'owner'));

drop policy if exists kv_invites_delete on public.kv_invites;
create policy kv_invites_delete on public.kv_invites for delete to authenticated
  using (public.kv_is_owner() or (public.kv_role() = 'admin' and role <> 'owner'));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'kv_documents'
  ) then
    alter publication supabase_realtime add table public.kv_documents;
  end if;
end
$$;