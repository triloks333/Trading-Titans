-- Owners can file personal documents for any vault member selected in the UI.
drop policy if exists kv_documents_insert on public.kv_documents;
create policy kv_documents_insert on public.kv_documents for insert to authenticated
  with check (
    public.kv_can_write()
    and created_by = auth.uid()
    and (
      scope = 'company'
      or (scope = 'personal' and (
        owner_id = auth.uid() or public.kv_is_owner()
      ))
    )
  );

drop policy if exists kv_activity_insert on public.kv_activity;
create policy kv_activity_insert on public.kv_activity for insert to authenticated
  with check (
    actor_id = auth.uid()
    and (
      scope = 'company'
      or owner_id = auth.uid()
      or public.kv_is_owner()
    )
  );

drop policy if exists kv_storage_insert on storage.objects;
create policy kv_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id in ('kv-documents','kv-signatures','kv-images')
    and public.kv_can_write()
    and (
      name like 'company/%'
      or (
        name like 'personal/%'
        and (
          split_part(name, '/', 2) = auth.uid()::text
          or (bucket_id = 'kv-documents' and public.kv_is_owner())
        )
      )
    )
  );
