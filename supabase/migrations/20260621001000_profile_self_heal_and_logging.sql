-- Observability + self-healing for profile provisioning.
-- Problem: profiles are created by a single trigger inside the auth signup
-- transaction. If it fails (or a row is later deleted), the user is left with
-- no profile and no record of why, which silently breaks login (e.g. the user
-- whose row was dropped by a June-20 maintenance op).

-- 1) Append-only log of every profile provisioning attempt.
create table if not exists public.profile_provisioning_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  email text,
  source text not null,    -- 'trigger' | 'self_heal' | 'manual'
  outcome text not null,   -- 'created' | 'already_existed' | 'error'
  detail text,
  created_at timestamptz not null default now()
);

alter table public.profile_provisioning_log enable row level security;

drop policy if exists "admins read provisioning log" on public.profile_provisioning_log;
create policy "admins read provisioning log"
  on public.profile_provisioning_log
  for select
  using (public.is_admin());

-- 2) Self-heal RPC: ensures the caller has a profile, creating one if missing.
create or replace function public.ensure_profile()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  v_email text;
  v_name text;
  v_created boolean := false;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from public.profiles where id = uid) then
    return false; -- already healthy, nothing to do
  end if;

  select email, raw_user_meta_data->>'name'
    into v_email, v_name
  from auth.users where id = uid;

  v_email := coalesce(v_email, uid::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(v_name, ''),
                     nullif(split_part(coalesce(v_email, ''), '@', 1), ''),
                     'Titan');

  begin
    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan, total_realized_pnl)
    values
      (uid, v_email, v_name, 11000.0, true, 'free_starter', 0.0)
    on conflict (id) do nothing;

    v_created := true;
    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (uid, v_email, 'self_heal', 'created');
  exception when others then
    insert into public.profile_provisioning_log(user_id, email, source, outcome, detail)
    values (uid, v_email, 'self_heal', 'error', sqlerrm);
    raise;
  end;

  return v_created;
end;
$$;

revoke all on function public.ensure_profile() from public, anon;
grant execute on function public.ensure_profile() to authenticated;

-- 3) Harden the signup trigger: log every outcome and NEVER block signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ref_by uuid;
  initial_bal numeric := 11000.0;
  v_email text;
  v_name text;
begin
  begin
    ref_by := nullif(new.raw_user_meta_data->>'referred_by', '')::uuid;
  exception when others then
    ref_by := null;
  end;

  v_email := coalesce(new.email, new.id::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(new.raw_user_meta_data->>'name', ''),
                     nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
                     'Guest Titan');

  begin
    if ref_by is not null then
      initial_bal := initial_bal + 5000.0;
      update public.profiles
        set wallet_balance = wallet_balance + 5000.0
        where id = ref_by;
    end if;

    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan, total_realized_pnl, referred_by)
    values
      (new.id, v_email, v_name, initial_bal, true, 'free_starter', 0.0, ref_by);

    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (new.id, v_email, 'trigger', 'created');
  exception when others then
    -- Never abort the auth signup. Record the failure so it is visible, and
    -- the client's ensure_profile() self-heal recovers the user on next login.
    insert into public.profile_provisioning_log(user_id, email, source, outcome, detail)
    values (new.id, v_email, 'trigger', 'error', sqlerrm);
  end;

  return new;
end;
$$;
