-- KASHIVWEALTH MANAGEMENT VAULT storage buckets + object policies.
-- Path convention:
--   company/<docId>/<filename>
--   personal/<userId>/<docId>/<filename>
-- so the second path segment is the owning user for every personal object.

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('kv-documents',  'kv-documents',  false, 209715200),
  ('kv-signatures', 'kv-signatures', false, 10485760),
  ('kv-images',     'kv-images',     false, 52428800)
on conflict (id) do nothing;

drop policy if exists kv_storage_select on storage.objects;
create policy kv_storage_select on storage.objects for select to authenticated
using (
  bucket_id in ('kv-documents','kv-signatures','kv-images')
  and public.kv_is_member()
  and (name like 'company/%' or split_part(name, '/', 2) = auth.uid()::text
       or public.kv_is_owner())
);

drop policy if exists kv_storage_insert on storage.objects;
create policy kv_storage_insert on storage.objects for insert to authenticated
with check (
  bucket_id in ('kv-documents','kv-signatures','kv-images')
  and public.kv_can_write()
  and (name like 'company/%'
       or (name like 'personal/%' and split_part(name, '/', 2) = auth.uid()::text))
);

drop policy if exists kv_storage_update on storage.objects;
create policy kv_storage_update on storage.objects for update to authenticated
using (
  bucket_id in ('kv-documents','kv-signatures','kv-images')
  and public.kv_can_write()
  and (name like 'company/%' or split_part(name, '/', 2) = auth.uid()::text
       or public.kv_is_owner())
);

drop policy if exists kv_storage_delete on storage.objects;
create policy kv_storage_delete on storage.objects for delete to authenticated
using (
  bucket_id in ('kv-documents','kv-signatures','kv-images')
  and (
    (name like 'company/%' and public.kv_is_admin())
    or split_part(name, '/', 2) = auth.uid()::text
    or public.kv_is_owner()
  )
);
