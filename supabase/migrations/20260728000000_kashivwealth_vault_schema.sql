-- KASHIVWEALTH MANAGEMENT VAULT
-- Lives in the existing Trading Titans Supabase project, fully namespaced with
-- a `kv_` prefix so no existing table, policy or trigger is touched.

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------- members ---
create table if not exists public.kv_members (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  full_name     text,
  avatar_url    text,
  role          text not null default 'member'
                check (role in ('owner','admin','member','viewer')),
  status        text not null default 'active'
                check (status in ('active','suspended')),
  pin_hash      text,
  biometric_on  boolean not null default false,
  last_login_at timestamptz,
  created_at    timestamptz not null default now()
);

-- Known founders are owners on first sign-in; otherwise the very first member
-- of an empty vault bootstraps itself as owner.
create or replace function public.kv_bootstrap_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) = any (array[
       'pawan.2u2@gmail.com','triloks34@gmail.com',
       'mr.engineer5000@gmail.com','manavagg2003@gmail.com'])
     or not exists (select 1 from public.kv_members where role = 'owner') then
    new.role := 'owner';
  end if;
  return new;
end $$;

drop trigger if exists kv_members_bootstrap on public.kv_members;
create trigger kv_members_bootstrap before insert on public.kv_members
for each row execute function public.kv_bootstrap_member();

-- ------------------------------------------------------- role predicates ---
create or replace function public.kv_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.kv_members where id = auth.uid() and status = 'active'
$$;

create or replace function public.kv_is_member() returns boolean
language sql stable as $$ select public.kv_role() is not null $$;

-- Owners have unrestricted visibility over EVERY vault item, including other
-- members' personal documents and passwords (explicit product requirement).
create or replace function public.kv_is_owner() returns boolean
language sql stable as $$ select public.kv_role() = 'owner' $$;

create or replace function public.kv_is_admin() returns boolean
language sql stable as $$ select public.kv_role() in ('owner','admin') $$;

create or replace function public.kv_can_write() returns boolean
language sql stable as $$ select public.kv_role() in ('owner','admin','member') $$;

-- ---------------------------------------------------------------- folders ---
create table if not exists public.kv_folders (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  parent_id  uuid references public.kv_folders(id) on delete cascade,
  scope      text not null default 'company' check (scope in ('company','personal')),
  category   text,
  owner_id   uuid references auth.users(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint kv_folders_scope_owner check (
    (scope = 'company' and owner_id is null) or
    (scope = 'personal' and owner_id is not null))
);

-- -------------------------------------------------------------- documents ---
create table if not exists public.kv_documents (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  folder_id    uuid references public.kv_folders(id) on delete set null,
  scope        text not null default 'company' check (scope in ('company','personal')),
  category     text not null default 'Other',
  owner_id     uuid references auth.users(id) on delete cascade,
  storage_path text not null,
  mime_type    text,
  size_bytes   bigint not null default 0,
  tags         text[] not null default '{}',
  is_favorite  boolean not null default false,
  expires_at   date,
  version      int not null default 1,
  ocr_text     text,
  notes        text,
  created_by   uuid not null references auth.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint kv_documents_scope_owner check (
    (scope = 'company' and owner_id is null) or
    (scope = 'personal' and owner_id is not null))
);
create index if not exists kv_documents_name_trgm on public.kv_documents using gin (name gin_trgm_ops);
create index if not exists kv_documents_folder on public.kv_documents (folder_id);
create index if not exists kv_documents_expiry on public.kv_documents (expires_at) where expires_at is not null;

create table if not exists public.kv_document_versions (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.kv_documents(id) on delete cascade,
  version      int not null,
  storage_path text not null,
  size_bytes   bigint not null default 0,
  created_by   uuid not null references auth.users(id),
  created_at   timestamptz not null default now(),
  unique (document_id, version)
);

create table if not exists public.kv_comments (
  id          uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('document','link','image')),
  entity_id   uuid not null,
  author_id   uuid not null references auth.users(id) on delete cascade,
  body        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists kv_comments_entity on public.kv_comments (entity_type, entity_id);

-- ------------------------------------------------------------- signatures ---
create table if not exists public.kv_signatures (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  scope        text not null default 'personal' check (scope in ('company','personal')),
  owner_id     uuid references auth.users(id) on delete cascade,
  storage_path text not null,
  created_by   uuid not null references auth.users(id),
  created_at   timestamptz not null default now(),
  constraint kv_signatures_scope_owner check (
    (scope = 'company' and owner_id is null) or
    (scope = 'personal' and owner_id is not null))
);

-- --------------------------------------------------------------- passwords ---
create table if not exists public.kv_passwords (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  website     text,
  url         text,
  username    text,
  email       text,
  secret      text not null,
  notes       text,
  scope       text not null default 'company' check (scope in ('company','personal')),
  owner_id    uuid references auth.users(id) on delete cascade,
  folder      text,
  tags        text[] not null default '{}',
  is_favorite boolean not null default false,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint kv_passwords_scope_owner check (
    (scope = 'company' and owner_id is null) or
    (scope = 'personal' and owner_id is not null))
);
create index if not exists kv_passwords_title_trgm on public.kv_passwords using gin (title gin_trgm_ops);

-- ------------------------------------------------------------------- links ---
create table if not exists public.kv_links (
  id          uuid primary key default gen_random_uuid(),
  url         text not null,
  title       text,
  description text,
  image_url   text,
  category    text not null default 'Website',
  tags        text[] not null default '{}',
  summary     text,
  is_favorite boolean not null default false,
  save_later  boolean not null default false,
  shared_by   uuid not null references auth.users(id),
  created_at  timestamptz not null default now()
);
create index if not exists kv_links_title_trgm on public.kv_links using gin ((coalesce(title,'')) gin_trgm_ops);

-- ------------------------------------------------------------------ images ---
create table if not exists public.kv_images (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  album        text not null default 'General',
  storage_path text not null,
  tags         text[] not null default '{}',
  size_bytes   bigint not null default 0,
  is_favorite  boolean not null default false,
  version      int not null default 1,
  uploaded_by  uuid not null references auth.users(id),
  created_at   timestamptz not null default now()
);
create index if not exists kv_images_name_trgm on public.kv_images using gin (name gin_trgm_ops);

-- ------------------------------------------------- activity/notifications ---
create table if not exists public.kv_activity (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references auth.users(id) on delete set null,
  action      text not null,
  entity_type text,
  entity_id   uuid,
  entity_name text,
  meta        jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index if not exists kv_activity_created on public.kv_activity (created_at desc);

create table if not exists public.kv_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  title      text not null,
  body       text,
  kind       text not null default 'general',
  entity_id  uuid,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists kv_notifications_user on public.kv_notifications (user_id, is_read);

create table if not exists public.kv_devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  device_label  text not null,
  platform      text,
  fcm_token     text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  unique (user_id, device_label)
);

-- -------------------------------------------------------------------- RLS ---
alter table public.kv_members            enable row level security;
alter table public.kv_folders            enable row level security;
alter table public.kv_documents          enable row level security;
alter table public.kv_document_versions  enable row level security;
alter table public.kv_comments           enable row level security;
alter table public.kv_signatures         enable row level security;
alter table public.kv_passwords          enable row level security;
alter table public.kv_links              enable row level security;
alter table public.kv_images             enable row level security;
alter table public.kv_activity           enable row level security;
alter table public.kv_notifications      enable row level security;
alter table public.kv_devices            enable row level security;

-- members: everyone in the vault can see the roster; you may edit yourself,
-- admins may edit anyone.
drop policy if exists kv_members_select on public.kv_members;
create policy kv_members_select on public.kv_members for select to authenticated
  using (id = auth.uid() or public.kv_is_member());

drop policy if exists kv_members_insert_self on public.kv_members;
create policy kv_members_insert_self on public.kv_members for insert to authenticated
  with check (id = auth.uid());

drop policy if exists kv_members_update on public.kv_members;
create policy kv_members_update on public.kv_members for update to authenticated
  using (id = auth.uid() or public.kv_is_admin())
  with check (id = auth.uid() or public.kv_is_admin());

drop policy if exists kv_members_delete on public.kv_members;
create policy kv_members_delete on public.kv_members for delete to authenticated
  using (public.kv_is_owner() and id <> auth.uid());

-- Shared scope pattern applied to folders / documents / signatures / passwords:
--   read   : company items -> any member; personal items -> the owner, plus
--            vault owners (full-power requirement)
--   write  : member+ for company items and for your own personal items
--   delete : admins for company items, the owner for personal items
do $$
declare t text;
begin
  foreach t in array array['kv_folders','kv_documents','kv_signatures','kv_passwords']
  loop
    execute format($f$
      drop policy if exists %1$s_select on public.%1$s;
      create policy %1$s_select on public.%1$s for select to authenticated
        using (public.kv_is_member() and (scope = 'company'
               or owner_id = auth.uid() or public.kv_is_owner()));

      drop policy if exists %1$s_insert on public.%1$s;
      create policy %1$s_insert on public.%1$s for insert to authenticated
        with check (public.kv_can_write() and created_by = auth.uid()
               and (scope = 'company' or owner_id = auth.uid()));

      drop policy if exists %1$s_update on public.%1$s;
      create policy %1$s_update on public.%1$s for update to authenticated
        using (public.kv_can_write() and (scope = 'company'
               or owner_id = auth.uid() or public.kv_is_owner()))
        with check (public.kv_can_write() and (scope = 'company'
               or owner_id = auth.uid() or public.kv_is_owner()));

      drop policy if exists %1$s_delete on public.%1$s;
      create policy %1$s_delete on public.%1$s for delete to authenticated
        using ((scope = 'company' and public.kv_is_admin())
               or owner_id = auth.uid() or public.kv_is_owner());
    $f$, t);
  end loop;
end $$;

-- document versions follow their parent document
drop policy if exists kv_document_versions_select on public.kv_document_versions;
create policy kv_document_versions_select on public.kv_document_versions for select to authenticated
  using (exists (select 1 from public.kv_documents d where d.id = document_id));

drop policy if exists kv_document_versions_insert on public.kv_document_versions;
create policy kv_document_versions_insert on public.kv_document_versions for insert to authenticated
  with check (public.kv_can_write() and created_by = auth.uid()
              and exists (select 1 from public.kv_documents d where d.id = document_id));

-- comments
drop policy if exists kv_comments_select on public.kv_comments;
create policy kv_comments_select on public.kv_comments for select to authenticated
  using (public.kv_is_member());

drop policy if exists kv_comments_insert on public.kv_comments;
create policy kv_comments_insert on public.kv_comments for insert to authenticated
  with check (public.kv_can_write() and author_id = auth.uid());

drop policy if exists kv_comments_delete on public.kv_comments;
create policy kv_comments_delete on public.kv_comments for delete to authenticated
  using (author_id = auth.uid() or public.kv_is_admin());

-- shared links & images: any member reads, member+ writes, admin/uploader deletes
drop policy if exists kv_links_select on public.kv_links;
create policy kv_links_select on public.kv_links for select to authenticated using (public.kv_is_member());
drop policy if exists kv_links_insert on public.kv_links;
create policy kv_links_insert on public.kv_links for insert to authenticated
  with check (public.kv_can_write() and shared_by = auth.uid());
drop policy if exists kv_links_update on public.kv_links;
create policy kv_links_update on public.kv_links for update to authenticated
  using (public.kv_can_write()) with check (public.kv_can_write());
drop policy if exists kv_links_delete on public.kv_links;
create policy kv_links_delete on public.kv_links for delete to authenticated
  using (shared_by = auth.uid() or public.kv_is_admin());

drop policy if exists kv_images_select on public.kv_images;
create policy kv_images_select on public.kv_images for select to authenticated using (public.kv_is_member());
drop policy if exists kv_images_insert on public.kv_images;
create policy kv_images_insert on public.kv_images for insert to authenticated
  with check (public.kv_can_write() and uploaded_by = auth.uid());
drop policy if exists kv_images_update on public.kv_images;
create policy kv_images_update on public.kv_images for update to authenticated
  using (public.kv_can_write()) with check (public.kv_can_write());
drop policy if exists kv_images_delete on public.kv_images;
create policy kv_images_delete on public.kv_images for delete to authenticated
  using (uploaded_by = auth.uid() or public.kv_is_admin());

-- activity log: append-only, visible to the team, never editable
drop policy if exists kv_activity_select on public.kv_activity;
create policy kv_activity_select on public.kv_activity for select to authenticated using (public.kv_is_member());
drop policy if exists kv_activity_insert on public.kv_activity;
create policy kv_activity_insert on public.kv_activity for insert to authenticated
  with check (actor_id = auth.uid());

-- personal notifications & devices
drop policy if exists kv_notifications_rw on public.kv_notifications;
create policy kv_notifications_rw on public.kv_notifications for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists kv_devices_rw on public.kv_devices;
create policy kv_devices_rw on public.kv_devices for all to authenticated
  using (user_id = auth.uid() or public.kv_is_admin())
  with check (user_id = auth.uid());
