-- Policy helpers are internal implementation details, not public RPCs.
revoke all on function public.kv_is_member() from public, anon;
revoke all on function public.kv_is_owner() from public, anon;
revoke all on function public.kv_is_admin() from public, anon;
revoke all on function public.kv_can_write() from public, anon;
grant execute on function public.kv_is_member() to authenticated, service_role;
grant execute on function public.kv_is_owner() to authenticated, service_role;
grant execute on function public.kv_is_admin() to authenticated, service_role;
grant execute on function public.kv_can_write() to authenticated, service_role;
