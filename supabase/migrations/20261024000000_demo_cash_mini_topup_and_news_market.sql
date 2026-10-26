-- Demo cash reduction to 1,100 INR, 29 INR Top-up pack for 11,000 INR demo capital,
-- and market category tagging on blog_posts for targeted in-app news.

-- 1. Update plan_catalogue with ₹29 pack (11,000 demo capital)
insert into public.plan_catalogue
  (sku, tier, kind, title, price_paise, price_usd_cents, billing_interval, cash_grant, monthly_stipend, sort_order)
values
  ('topup_mini', 'topup', 'one_time', 'Mini Boost', 2900, 49, null, 11000, 0, 5)
on conflict (sku) do update
  set title = excluded.title,
      price_paise = excluded.price_paise,
      price_usd_cents = excluded.price_usd_cents,
      cash_grant = excluded.cash_grant,
      sort_order = excluded.sort_order;

-- 2. Update default challenge_baseline_capital column default to 1100
alter table public.profiles
  alter column challenge_baseline_capital set default 1100;

-- 3. Update handle_new_user to assign ₹1,100 demo cash for new regular signups
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  ref_by uuid;
  is_guest boolean := coalesce(new.is_anonymous, false);
  initial_bal numeric := case when is_guest then 500.0 else 1100.0 end;
  baseline numeric := initial_bal;
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
      initial_bal := initial_bal + 500.0;
      update public.profiles
        set wallet_balance = wallet_balance + 500.0
        where id = ref_by;
    end if;

    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan,
       total_realized_pnl, referred_by, challenge_baseline_capital)
    values
      (new.id, v_email, v_name, initial_bal, true, 'free_starter', 0.0, ref_by,
       baseline);

    insert into public.profile_provisioning_log(user_id, email, source, outcome)
    values (new.id, v_email, 'trigger', 'created');
  exception when others then
    insert into public.profile_provisioning_log(user_id, email, source, outcome, detail)
    values (new.id, v_email, 'trigger', 'error', sqlerrm);
  end;

  return new;
end;
$$;

-- 4. Update ensure_profile() self-heal function
create or replace function public.ensure_profile()
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  uid uuid := auth.uid();
  v_email text;
  v_name text;
  v_guest boolean;
  v_bal numeric;
  v_created boolean := false;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from public.profiles where id = uid) then
    return false;
  end if;

  select email, raw_user_meta_data->>'name', coalesce(is_anonymous, false)
    into v_email, v_name, v_guest
  from auth.users where id = uid;

  v_email := coalesce(v_email, uid::text || '@guest.tradingtitans');
  v_name := coalesce(nullif(v_name, ''),
                     nullif(split_part(coalesce(v_email, ''), '@', 1), ''),
                     'Titan');
  v_bal := case when coalesce(v_guest, false) then 500.0 else 1100.0 end;

  begin
    insert into public.profiles
      (id, email, name, wallet_balance, subscription_active, plan,
       total_realized_pnl, challenge_baseline_capital)
    values
      (uid, v_email, v_name, v_bal, true, 'free_starter', 0.0, v_bal)
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

-- 5. Add market column to blog_posts for targeted market news
alter table public.blog_posts
  add column if not exists market text not null default 'all';

create index if not exists blog_posts_market_idx
  on public.blog_posts (market, published_at desc)
  where published_at is not null;
