-- Harden shared-project onboarding: Trading Titans users must not automatically
-- gain access to KASHIVWEALTH company data. Only named owners or invited emails
-- can create a kv_members row.

create table if not exists public.kv_invites (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  role        text not null default 'member'
              check (role in ('owner','admin','member','viewer')),
  invited_by  uuid not null references auth.users(id),
  accepted_at timestamptz,
  created_at  timestamptz not null default now()
);
create unique index if not exists kv_invites_pending_email
  on public.kv_invites (lower(email)) where accepted_at is null;
alter table public.kv_invites enable row level security;

-- Replace first-user bootstrap: first login is not proof of ownership.
create or replace function public.kv_bootstrap_member()
returns trigger language plpgsql security definer set search_path = public as $$
declare invited_role text;
begin
  if lower(new.email) = any (array[
       'pawan.2u2@gmail.com','triloks34@gmail.com',
       'mr.engineer5000@gmail.com','manavagg2003@gmail.com']) then
    new.role := 'owner';
    return new;
  end if;

  select role into invited_role from public.kv_invites
  where lower(email) = lower(new.email) and accepted_at is null
  order by created_at desc limit 1 for update;
  if invited_role is null then
    raise exception 'This account has not been invited to KASHIVWEALTH VAULT';
  end if;

  new.role := invited_role;
  update public.kv_invites set accepted_at = now()
  where lower(email) = lower(new.email) and accepted_at is null;
  return new;
end $$;

-- Anonymous Supabase sessions use the authenticated Postgres role. Explicitly
-- reject them and pin every helper's search_path.
create or replace function public.kv_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.kv_members
  where id = auth.uid() and status = 'active'
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

create or replace function public.kv_is_member() returns boolean
language sql stable set search_path = public as $$ select public.kv_role() is not null $$;
create or replace function public.kv_is_owner() returns boolean
language sql stable set search_path = public as $$ select public.kv_role() = 'owner' $$;
create or replace function public.kv_is_admin() returns boolean
language sql stable set search_path = public as $$ select public.kv_role() in ('owner','admin') $$;
create or replace function public.kv_can_write() returns boolean
language sql stable set search_path = public as $$ select public.kv_role() in ('owner','admin','member') $$;

revoke all on function public.kv_bootstrap_member() from public, anon, authenticated;
revoke all on function public.kv_role() from public, anon;
grant execute on function public.kv_role() to authenticated, service_role;

drop policy if exists kv_invites_select on public.kv_invites;
create policy kv_invites_select on public.kv_invites for select to authenticated
  using (public.kv_is_admin() or lower(email) = lower(auth.jwt() ->> 'email'));
drop policy if exists kv_invites_insert on public.kv_invites;
create policy kv_invites_insert on public.kv_invites for insert to authenticated
  with check (public.kv_is_admin() and invited_by = auth.uid());
drop policy if exists kv_invites_update on public.kv_invites;
create policy kv_invites_update on public.kv_invites for update to authenticated
  using (public.kv_is_admin()) with check (public.kv_is_admin());
drop policy if exists kv_invites_delete on public.kv_invites;
create policy kv_invites_delete on public.kv_invites for delete to authenticated
  using (public.kv_is_admin());
