-- Provision the four declared founders from the shared auth tenant. This uses
-- stable emails rather than generated user IDs and does not touch profiles or
-- balances in the Trading Titans domain.
insert into public.kv_members (id, email, full_name, role)
select
  id,
  email,
  coalesce(raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name'),
  'owner'
from auth.users
where lower(email) = any (array[
  'pawan.2u2@gmail.com',
  'triloks34@gmail.com',
  'mr.engineer5000@gmail.com',
  'manavagg2003@gmail.com'
])
on conflict (id) do update set role = 'owner', status = 'active';
