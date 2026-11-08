-- Two-stage downshift offers (book 2, honest version).
-- A user who views a bigger pack, steps down to a cheaper one and doesn't buy
-- gets a real discount on the cheaper pack: 50% for 48 hours, then 75% for 48
-- more hours, then it expires. create-payment-order charges the discounted
-- amount; razorpay-webhook already checks paid >= payment_orders.amount_paise.
-- No device, network or "pursuit ping" targeting. Every grant, suppression,
-- stage change and redemption is logged to intel_reaction_firings.

create table if not exists public.intel_offer_grants (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  sku                 text not null,
  from_sku            text not null,
  granted_at          timestamptz not null default now(),
  stage2_at           timestamptz not null default now() + interval '48 hours',
  expires_at          timestamptz not null default now() + interval '96 hours',
  stage2_notified_at  timestamptz,
  redeemed_at         timestamptz,
  redeemed_order_id   uuid
);
create index if not exists intel_offer_grants_user_idx on public.intel_offer_grants (user_id, granted_at desc);
create index if not exists intel_offer_grants_open_idx on public.intel_offer_grants (stage2_at) where redeemed_at is null;
alter table public.intel_offer_grants enable row level security;
drop policy if exists "intel_offer_grants read own or admin" on public.intel_offer_grants;
create policy "intel_offer_grants read own or admin" on public.intel_offer_grants
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke all on public.intel_offer_grants from anon, authenticated;
grant select on public.intel_offer_grants to authenticated;

alter table public.payment_orders add column if not exists intel_offer_grant_id uuid references public.intel_offer_grants(id);

-- Percent off right now: 50 in stage 1, 75 in stage 2, 0 once expired or redeemed.
create or replace function public.intel_offer_pct(g public.intel_offer_grants)
returns integer language sql stable set search_path = public, pg_temp as $$
  select case
    when g.redeemed_at is not null or now() >= g.expires_at then 0
    when now() >= g.stage2_at then 75
    else 50 end;
$$;

-- Grant as the app shows it: real prices from the catalogue right now.
create or replace function public.intel_offer_json(g public.intel_offer_grants)
returns jsonb language sql stable set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'id', g.id, 'sku', g.sku, 'title', p.title, 'pct', public.intel_offer_pct(g),
    'list_paise', p.price_paise,
    'price_paise', round(p.price_paise * (100 - public.intel_offer_pct(g)) / 100.0),
    'list_usd_cents', p.price_usd_cents,
    'price_usd_cents', case when p.price_usd_cents is null then null
                            else round(p.price_usd_cents * (100 - public.intel_offer_pct(g)) / 100.0) end,
    'stage2_at', g.stage2_at, 'expires_at', g.expires_at)
  from public.plan_catalogue p where p.sku = g.sku;
$$;

-- Called by the app when it sees a downshift. Returns the grant, or null.
create or replace function public.intel_request_offer(p_from text, p_to text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  g public.intel_offer_grants;
  reason text;
begin
  if uid is null then raise exception 'Not authenticated'; end if;
  if (p_from, p_to) not in (('topup_max', 'topup_plus'), ('topup_plus', 'topup_boost'),
                            ('titan_annual', 'titan_monthly'), ('titan_monthly', 'pro_monthly')) then
    return null;
  end if;
  -- An open grant for this pack (or one from the last 30 days) is returned as is.
  select * into g from public.intel_offer_grants
   where user_id = uid and sku = p_to and granted_at > now() - interval '30 days'
   order by granted_at desc limit 1;
  if found then
    return case when public.intel_offer_pct(g) > 0 then public.intel_offer_json(g) else null end;
  end if;

  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    reason := 'guest_account';
  elsif exists (select 1 from public.payment_orders where user_id = uid and status = 'paid') then
    reason := 'already_a_customer'; -- first-time offer only
  elsif (select wallet_balance from public.profiles where id = uid) < 1000 then
    reason := 'wallet_under_1000';
  elsif exists (
    select 1 from public.intel_events l
      join public.intel_events o on o.user_id = l.user_id and o.name = 'trade_placed'
       and o.props->>'sym' = l.props->>'sym'
       and o.client_ts between l.client_ts and l.client_ts + interval '120 seconds'
     where l.user_id = uid and l.name = 'trade_closed' and (l.props->>'pnl')::numeric < 0
       and l.created_at > now() - interval '24 hours') then
    reason := 'revenge_reentry_120s';
  end if;

  if reason is not null then
    insert into public.intel_reaction_firings (user_id, reaction, delivered, reason, props)
    values (uid, 'offer_stage1', false, reason, jsonb_build_object('sku', p_to, 'from', p_from));
    return null;
  end if;

  insert into public.intel_offer_grants (user_id, sku, from_sku) values (uid, p_to, p_from) returning * into g;
  insert into public.intel_reaction_firings (user_id, reaction, delivered, reason, props)
  values (uid, 'offer_stage1', true, 'downshift_' || p_from || '_to_' || p_to, jsonb_build_object('sku', p_to, 'grant', g.id));
  return public.intel_offer_json(g);
end $$;
revoke all on function public.intel_request_offer(text, text) from public, anon;
grant execute on function public.intel_request_offer(text, text) to authenticated;

-- The caller's open offers.
create or replace function public.intel_my_offers()
returns jsonb
language sql security definer set search_path = public, pg_temp stable
as $$
  select coalesce(jsonb_agg(public.intel_offer_json(g) order by g.granted_at desc), '[]'::jsonb)
  from public.intel_offer_grants g
  where g.user_id = auth.uid() and g.redeemed_at is null and g.expires_at > now();
$$;
revoke all on function public.intel_my_offers() from public, anon;
grant execute on function public.intel_my_offers() to authenticated;

-- For create-payment-order (service role only): the open grant and its percent.
create or replace function public.intel_offer_for_checkout(p_user uuid, p_sku text)
returns table (grant_id uuid, pct integer)
language sql security definer set search_path = public, pg_temp stable
as $$
  select g.id, public.intel_offer_pct(g)
  from public.intel_offer_grants g
  where g.user_id = p_user and g.sku = p_sku and g.redeemed_at is null and g.expires_at > now()
  order by g.granted_at desc limit 1;
$$;
revoke all on function public.intel_offer_for_checkout(uuid, text) from public, anon, authenticated;

-- A paid order that used a grant redeems it.
create or replace function public.intel_offer_redeem_on_paid()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' and new.intel_offer_grant_id is not null then
    update public.intel_offer_grants set redeemed_at = now(), redeemed_order_id = new.id
     where id = new.intel_offer_grant_id and redeemed_at is null;
    insert into public.intel_reaction_firings (user_id, reaction, delivered, reason, props)
    values (new.user_id, 'offer_redeemed', true, 'paid',
            jsonb_build_object('sku', new.sku, 'amount_paise', new.amount_paise, 'currency', new.currency, 'grant', new.intel_offer_grant_id));
  end if;
  return new;
end $$;
drop trigger if exists trg_intel_offer_redeem on public.payment_orders;
create trigger trg_intel_offer_redeem after update of status on public.payment_orders
  for each row execute function public.intel_offer_redeem_on_paid();

-- Stage 2 starts: one notification with the real price and the real end time.
create or replace function public.intel_offer_stage2_notify()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n integer := 0;
  r record;
begin
  for r in
    select g.*, p.title, p.price_paise, pr.location
      from public.intel_offer_grants g
      join public.plan_catalogue p on p.sku = g.sku
      left join public.profiles pr on pr.id = g.user_id
     where g.redeemed_at is null and g.stage2_notified_at is null
       and now() >= g.stage2_at and now() < g.expires_at
  loop
    insert into public.notifications (user_id, title, body, action_type, action_data)
    values (r.user_id,
            'Your ' || r.title || ' offer is now 75% off',
            '₹' || to_char(round(r.price_paise * 0.25) / 100.0, 'FM999990.00') || ' (was ₹' ||
              to_char(r.price_paise / 100.0, 'FM999990.00') || ') until ' ||
              to_char(r.expires_at at time zone 'Asia/Kolkata', 'FMDy DD Mon, FMHH12:MI AM') || ' IST.',
            'general', jsonb_build_object('cta_route', 'subscribe'));
    update public.intel_offer_grants set stage2_notified_at = now() where id = r.id;
    insert into public.intel_reaction_firings (user_id, reaction, delivered, reason, props)
    values (r.user_id, 'offer_stage2', true, 'stage1_not_redeemed_48h', jsonb_build_object('sku', r.sku, 'grant', r.id));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.intel_offer_stage2_notify() from public, anon, authenticated;
select cron.unschedule('intel-offer-stage2') where exists (select 1 from cron.job where jobname = 'intel-offer-stage2');
select cron.schedule('intel-offer-stage2', '7 * * * *', $$select public.intel_offer_stage2_notify()$$);

-- Admin: offer pipeline summary.
create or replace function public.intel_admin_offers()
returns jsonb language plpgsql security definer set search_path = public, pg_temp stable as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return jsonb_build_object(
    'issued_30d',   (select count(*) from public.intel_offer_grants where granted_at > now() - interval '30 days'),
    'active',       (select count(*) from public.intel_offer_grants where redeemed_at is null and expires_at > now()),
    'redeemed_30d', (select count(*) from public.intel_offer_grants where redeemed_at > now() - interval '30 days'),
    'redeemed_stage2_30d', (select count(*) from public.intel_offer_grants where redeemed_at > now() - interval '30 days' and redeemed_at >= stage2_at),
    'expired_30d',  (select count(*) from public.intel_offer_grants where redeemed_at is null and expires_at < now() and expires_at > now() - interval '30 days'),
    'revenue_paise_30d', (select coalesce(sum(amount_paise), 0) from public.payment_orders
                          where intel_offer_grant_id is not null and status = 'paid' and currency = 'INR'
                            and created_at > now() - interval '30 days'),
    'suppressed_30d', (select coalesce(jsonb_object_agg(reason, n), '{}') from (
        select reason, count(*) n from public.intel_reaction_firings
        where reaction = 'offer_stage1' and not delivered and created_at > now() - interval '30 days' group by 1) s)
  );
end $$;
revoke all on function public.intel_admin_offers() from public, anon;
grant execute on function public.intel_admin_offers() to authenticated;

do $$
begin
  begin alter publication supabase_realtime add table public.intel_offer_grants; exception when duplicate_object then null; end;
end $$;
