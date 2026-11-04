-- Diwali sale: every pack 50% off, rupees and dollars, until 10 Nov 2026 23:59 IST.
--
-- HOW A SALE WORKS
-- `price_paise` / `price_usd_cents` stay the one source of what is charged:
-- create-payment-order reads them, so halving them IS the sale and needs no code
-- change server-side. The old prices move to `compare_at_*`, which the app and
-- web show struck through. A row is "on sale" exactly when `compare_at_paise` is
-- not null, so the strikethrough can never disagree with the amount charged.
--
-- Sale prices round DOWN to a whole rupee / cent (₹149 → ₹74, $2.49 → $1.24), so
-- every price is at least 50% off and nothing shows paise.
--
-- `end_price_sale()` puts every price back and clears the sale. pg_cron runs it
-- once at 18:29 UTC on 10 Nov (23:59 IST) and then unschedules itself. It is
-- safe to run by hand at any time, and running it twice changes nothing.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.plan_catalogue.compare_at_paise      new column
--   public.plan_catalogue.compare_at_usd_cents  new column
--   public.plan_catalogue.sale_ends_at          new column
--   public.end_price_sale()                     new function
--   cron job 'end-diwali-sale-2026'             new, one-shot
--   plan_catalogue prices                       halved for active rows
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Additive columns. Apps before 1.2.14 just show the lower price with no
-- strikethrough and no banner, and are charged the same lower price.
--
-- ── RISK ───────────────────────────────────────────────────────────────────
-- A Razorpay payment LINK created during the sale and paid after it ends is
-- recorded against the full price by razorpay-webhook's ensurePaymentLinkOrderRow
-- and flagged as underpaid. Only links made by hand (MCP or Dashboard) take that
-- path; app checkouts store their own amount when the order is created.
--
-- ── ROLLBACK (= end the sale now) ──────────────────────────────────────────
--   select public.end_price_sale();

alter table public.plan_catalogue
  add column if not exists compare_at_paise integer,
  add column if not exists compare_at_usd_cents integer,
  add column if not exists sale_ends_at timestamptz;

create or replace function public.end_price_sale()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.plan_catalogue
     set price_paise = compare_at_paise,
         price_usd_cents = coalesce(compare_at_usd_cents, price_usd_cents),
         compare_at_paise = null,
         compare_at_usd_cents = null,
         sale_ends_at = null
   where compare_at_paise is not null;

  perform cron.unschedule(jobid) from cron.job where jobname = 'end-diwali-sale-2026';
end;
$$;

revoke all on function public.end_price_sale() from public, anon, authenticated;

-- Start the sale. The `compare_at_paise is null` guard makes a re-run a no-op
-- instead of halving prices twice.
update public.plan_catalogue
   set compare_at_paise = price_paise,
       compare_at_usd_cents = price_usd_cents,
       price_paise = (price_paise / 200) * 100,
       price_usd_cents = case when price_usd_cents is null then null else price_usd_cents / 2 end,
       sale_ends_at = '2026-11-10 23:59:59+05:30'
 where is_active
   and compare_at_paise is null;

select cron.schedule('end-diwali-sale-2026', '29 18 10 11 *', 'select public.end_price_sale()');
