-- Store customer mobile phone numbers on profiles and payment_orders
-- ============================================================================
-- Captures the mobile/WhatsApp number for every user who initiates or completes
-- a payment (both at checkout start and from Razorpay webhook payloads).

alter table public.profiles
  add column if not exists phone text;

comment on column public.profiles.phone is
  'User mobile/WhatsApp number captured at checkout or from Razorpay payment webhooks.';

alter table public.payment_orders
  add column if not exists customer_phone text;

comment on column public.payment_orders.customer_phone is
  'Customer phone number attached to this payment order (from prefill or Razorpay payment entity).';

-- Backfill customer_phone on payment_orders and phone on profiles from existing payment_events
do $$
declare
  rec record;
  v_phone text;
  v_uid uuid;
  v_ord text;
begin
  for rec in
    select payload
      from public.payment_events
     where payload->'payload'->'payment'->'entity'->>'contact' is not null
     order by received_at asc
  loop
    v_phone := trim(rec.payload->'payload'->'payment'->'entity'->>'contact');
    v_ord   := rec.payload->'payload'->'payment'->'entity'->>'order_id';
    begin
      v_uid := (rec.payload->'payload'->'payment'->'entity'->'notes'->>'user_id')::uuid;
    exception when others then
      v_uid := null;
    end;

    if v_phone is not null and v_phone <> '' then
      if v_ord is not null then
        update public.payment_orders
           set customer_phone = v_phone
         where provider_order_id = v_ord
           and (customer_phone is null or customer_phone = '');

        if v_uid is null then
          select user_id into v_uid
            from public.payment_orders
           where provider_order_id = v_ord
           limit 1;
        end if;
      end if;

      if v_uid is not null then
        update public.profiles
           set phone = v_phone
         where id = v_uid
           and (phone is null or phone = '');
      end if;
    end if;
  end loop;
end;
$$;
