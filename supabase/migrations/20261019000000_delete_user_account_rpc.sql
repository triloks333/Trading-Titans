-- Enables in-app account deletion for Apple App Store Review Guideline 5.1.1(v).
-- Allows an authenticated user to permanently delete their own account and cascade
-- all associated user records (profiles, orders, holdings, transactions).

create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Delete from auth.users; cascade constraints handle profiles, orders, etc.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_user_account() from public;
grant execute on function public.delete_user_account() to authenticated;
