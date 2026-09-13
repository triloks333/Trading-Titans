-- Notes, assignable todos, workspace notifications, compressed uploads and
-- richer shared-content classification.

create table if not exists public.kv_notes (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null default '',
  scope      text not null default 'company' check (scope in ('company','personal')),
  owner_id   uuid references auth.users(id) on delete cascade,
  category   text not null default 'General',
  tags       text[] not null default '{}',
  is_pinned  boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint kv_notes_scope_owner check (
    (scope = 'company' and owner_id is null) or
    (scope = 'personal' and owner_id is not null))
);
create index if not exists kv_notes_created on public.kv_notes (created_at desc);
alter table public.kv_notes enable row level security;

drop policy if exists kv_notes_select on public.kv_notes;
create policy kv_notes_select on public.kv_notes for select to authenticated
  using (public.kv_is_member() and (scope = 'company' or owner_id = auth.uid() or public.kv_is_owner()));

drop policy if exists kv_notes_insert on public.kv_notes;
create policy kv_notes_insert on public.kv_notes for insert to authenticated
  with check (public.kv_can_write() and created_by = auth.uid()
    and (scope = 'company' or owner_id = auth.uid() or public.kv_is_owner()));

drop policy if exists kv_notes_update on public.kv_notes;
create policy kv_notes_update on public.kv_notes for update to authenticated
  using (public.kv_can_write() and (scope = 'company' or owner_id = auth.uid() or public.kv_is_owner()))
  with check (public.kv_can_write() and (scope = 'company' or owner_id = auth.uid() or public.kv_is_owner()));

drop policy if exists kv_notes_delete on public.kv_notes;
create policy kv_notes_delete on public.kv_notes for delete to authenticated
  using (created_by = auth.uid() or owner_id = auth.uid() or public.kv_is_owner()
    or (scope = 'company' and public.kv_is_admin()));

create table if not exists public.kv_todos (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  details      text,
  assigned_to  uuid not null references auth.users(id) on delete cascade,
  priority     text not null default 'Normal' check (priority in ('Low','Normal','High','Urgent')),
  status       text not null default 'open' check (status in ('open','in_progress','done')),
  due_date     date,
  created_by   uuid not null references auth.users(id),
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists kv_todos_assignee on public.kv_todos (assigned_to, status);
alter table public.kv_todos enable row level security;

-- Assignees and authors see their own work; owners see the whole board.
drop policy if exists kv_todos_select on public.kv_todos;
create policy kv_todos_select on public.kv_todos for select to authenticated
  using (public.kv_is_member()
    and (assigned_to = auth.uid() or created_by = auth.uid() or public.kv_is_owner()));

drop policy if exists kv_todos_insert on public.kv_todos;
create policy kv_todos_insert on public.kv_todos for insert to authenticated
  with check (public.kv_can_write() and created_by = auth.uid()
    and (assigned_to = auth.uid() or public.kv_is_admin()));

drop policy if exists kv_todos_update on public.kv_todos;
create policy kv_todos_update on public.kv_todos for update to authenticated
  using (public.kv_can_write()
    and (assigned_to = auth.uid() or created_by = auth.uid() or public.kv_is_owner()))
  with check (public.kv_can_write()
    and (assigned_to = auth.uid() or created_by = auth.uid() or public.kv_is_owner()));

drop policy if exists kv_todos_delete on public.kv_todos;
create policy kv_todos_delete on public.kv_todos for delete to authenticated
  using (created_by = auth.uid() or public.kv_is_owner());

-- Uploads are gzipped when that actually saves space; readers gunzip on open.
alter table public.kv_documents
  add column if not exists compressed boolean not null default false;

-- Broader shared-content classification: platform stays in `category`,
-- intent/theme lands in `theme`.
alter table public.kv_links
  add column if not exists theme text not null default 'Other';

-- ------------------------------------------------------- notifications ---
-- Fan out a workspace notification to every active member except the actor.
create or replace function public.kv_notify(
  p_title text, p_body text, p_kind text, p_entity uuid, p_exclude uuid
) returns void language sql security definer set search_path = public as $$
  insert into public.kv_notifications (user_id, title, body, kind, entity_id)
  select m.id, p_title, p_body, p_kind, p_entity
  from public.kv_members m
  where m.status = 'active' and m.id is distinct from p_exclude;
$$;
revoke all on function public.kv_notify(text, text, text, uuid, uuid)
  from public, anon, authenticated;

create or replace function public.kv_actor_label(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(full_name, ''), email, 'A team member')
  from public.kv_members where id = p_id;
$$;
revoke all on function public.kv_actor_label(uuid) from public, anon, authenticated;

create or replace function public.kv_notify_document()
returns trigger language plpgsql security definer set search_path = public as $$
declare actor text := public.kv_actor_label(new.created_by);
begin
  if new.scope = 'company' then
    perform public.kv_notify('New company document',
      actor || ' added ' || new.name, 'document', new.id, new.created_by);
  elsif new.owner_id is distinct from new.created_by then
    insert into public.kv_notifications (user_id, title, body, kind, entity_id)
    values (new.owner_id, 'Document added to your vault',
      actor || ' filed ' || new.name, 'document', new.id);
  end if;
  return null;
end $$;
drop trigger if exists kv_documents_notify on public.kv_documents;
create trigger kv_documents_notify after insert on public.kv_documents
for each row execute function public.kv_notify_document();

create or replace function public.kv_notify_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.kv_notify('New shared content',
    public.kv_actor_label(new.shared_by) || ' shared ' ||
    coalesce(nullif(new.title, ''), new.url), 'link', new.id, new.shared_by);
  return null;
end $$;
drop trigger if exists kv_links_notify on public.kv_links;
create trigger kv_links_notify after insert on public.kv_links
for each row execute function public.kv_notify_link();

create or replace function public.kv_notify_image()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.kv_notify('New shared image',
    public.kv_actor_label(new.uploaded_by) || ' uploaded ' || new.name,
    'image', new.id, new.uploaded_by);
  return null;
end $$;
drop trigger if exists kv_images_notify on public.kv_images;
create trigger kv_images_notify after insert on public.kv_images
for each row execute function public.kv_notify_image();

create or replace function public.kv_notify_note()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.scope = 'company' then
    perform public.kv_notify('New note',
      public.kv_actor_label(new.created_by) || ' posted “' || new.title || '”',
      'note', new.id, new.created_by);
  end if;
  return null;
end $$;
drop trigger if exists kv_notes_notify on public.kv_notes;
create trigger kv_notes_notify after insert on public.kv_notes
for each row execute function public.kv_notify_note();

-- Assignment is personal: only the assignee is told.
create or replace function public.kv_notify_todo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_to is distinct from new.created_by then
    insert into public.kv_notifications (user_id, title, body, kind, entity_id)
    values (new.assigned_to, 'New task assigned to you',
      public.kv_actor_label(new.created_by) || ' assigned “' || new.title || '”',
      'todo', new.id);
  end if;
  return null;
end $$;
drop trigger if exists kv_todos_notify on public.kv_todos;
create trigger kv_todos_notify after insert on public.kv_todos
for each row execute function public.kv_notify_todo();

do $$
declare t text;
begin
  foreach t in array array['kv_notes','kv_todos','kv_notifications']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Trigger functions are internal: they must not be reachable as RPCs.
revoke all on function public.kv_notify_document() from public, anon, authenticated;
revoke all on function public.kv_notify_link() from public, anon, authenticated;
revoke all on function public.kv_notify_image() from public, anon, authenticated;
revoke all on function public.kv_notify_note() from public, anon, authenticated;
revoke all on function public.kv_notify_todo() from public, anon, authenticated;
