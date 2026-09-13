-- Prevent personal-vault filenames and comments leaking through collaboration
-- tables. Owners retain disclosed oversight; normal members see only their own.

alter table public.kv_activity
  add column if not exists scope text not null default 'company'
    check (scope in ('company','personal')),
  add column if not exists owner_id uuid references auth.users(id) on delete cascade;

alter table public.kv_activity drop constraint if exists kv_activity_scope_owner;
alter table public.kv_activity add constraint kv_activity_scope_owner check (
  (scope = 'company' and owner_id is null) or
  (scope = 'personal' and owner_id is not null)
);

drop policy if exists kv_activity_select on public.kv_activity;
create policy kv_activity_select on public.kv_activity for select to authenticated
  using (public.kv_is_member() and (
    scope = 'company' or owner_id = auth.uid() or public.kv_is_owner()
  ));

drop policy if exists kv_activity_insert on public.kv_activity;
create policy kv_activity_insert on public.kv_activity for insert to authenticated
  with check (actor_id = auth.uid() and (
    scope = 'company' or owner_id = auth.uid()
  ));

drop policy if exists kv_comments_select on public.kv_comments;
create policy kv_comments_select on public.kv_comments for select to authenticated
  using (public.kv_is_member() and (
    entity_type <> 'document' or exists (
      select 1 from public.kv_documents d where d.id = entity_id
    )
  ));

drop policy if exists kv_comments_insert on public.kv_comments;
create policy kv_comments_insert on public.kv_comments for insert to authenticated
  with check (public.kv_can_write() and author_id = auth.uid() and (
    entity_type <> 'document' or exists (
      select 1 from public.kv_documents d where d.id = entity_id
    )
  ));
