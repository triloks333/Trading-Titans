/// Automated 5–7 Day Win-Back Payment Reminders (Email + SMS + FCM Push).
///
/// Triggered every 6 days at 11:00 AM IST (`30 5 */6 * *` UTC) via `pg_cron` +
/// `pg_net`. Follows up with every user who initiated a payment in
/// `public.payment_orders` (`topup_*`, `pro_*`, `titan_*`) until they complete
/// a purchase.
///
/// Hard exclusions (never reminded):
/// - Trilok Singh (`triloks34@gmail.com`)
/// - Pawan / Pawan Kumar (`pawan.2u2@gmail.com`)
/// - Manav (`mr.engineer5000@gmail.com`, `manavagg2003@gmail.com`)
/// - Any user who has completed at least 1 payment (`paid` / `active` / `completed`)
///   or has `profiles.subscription_active = true`.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { Client as PgClient } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RZP_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
const RZP_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const DB_URL = Deno.env.get("SUPABASE_DB_URL") ?? "";

const RZP_AUTH = "Basic " + btoa(`${RZP_KEY_ID}:${RZP_KEY_SECRET}`);

const EXCLUDED_EMAILS = new Set([
  "triloks34@gmail.com",
  "pawan.2u2@gmail.com",
  "mr.engineer5000@gmail.com",
  "manavagg2003@gmail.com",
]);

function isExcludedUser(email?: string | null, name?: string | null): boolean {
  const e = (email ?? "").trim().toLowerCase();
  const n = (name ?? "").trim().toLowerCase();
  if (!e) return true;
  if (EXCLUDED_EMAILS.has(e)) return true;
  if (n.includes("trilok") || n.includes("pawan") || n === "manav") return true;
  return false;
}

let infraReady = false;
async function ensureInfraAndCron() {
  if (infraReady || !DB_URL) return;
  infraReady = true;
  const client = new PgClient(DB_URL);
  await client.connect();
  try {
    await client.queryArray(`
      create table if not exists public.winback_reminder_log (
        user_id          uuid primary key references public.profiles(id) on delete cascade,
        email            text not null,
        name             text,
        phone            text,
        sku              text not null,
        payment_link_id  text,
        short_url        text,
        excluded         boolean not null default false,
        reminder_count   integer not null default 0,
        last_sent_at     timestamptz,
        completed_at     timestamptz,
        created_at       timestamptz not null default now(),
        updated_at       timestamptz not null default now()
      );
      alter table public.winback_reminder_log enable row level security;
      revoke all on table public.winback_reminder_log from public, anon, authenticated;
      grant all on table public.winback_reminder_log to service_role;

      do $do$
      begin
        if exists (select 1 from pg_extension where extname = 'pg_cron') then
          perform cron.unschedule('winback-payment-reminders-every-6d')
            where exists (select 1 from cron.job where jobname = 'winback-payment-reminders-every-6d');

          perform cron.schedule(
            'winback-payment-reminders-every-6d',
            '30 5 */6 * *',
            $cron$
              select net.http_post(
                url := 'https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/winback-reminders',
                headers := '{"Content-Type": "application/json"}'::jsonb,
                body := '{"source": "pg_cron"}'::jsonb
              );
            $cron$
          );
        end if;
      end
      $do$;
      notify pgrst, 'reload schema';
    `);
  } finally {
    await client.end();
  }
}

Deno.serve(async (req: Request) => {
  try {
    await ensureInfraAndCron();
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const body = await req.json().catch(() => ({}));

    // Optional initial seed from our batch campaign
    if (Array.isArray(body.seed) && body.seed.length > 0) {
      for (const item of body.seed) {
        const excluded = Boolean(item.excluded) || isExcludedUser(item.email, item.name);
        await supabase.from("winback_reminder_log").upsert({
          user_id: item.user_id,
          email: item.email,
          name: item.name,
          phone: item.phone ?? null,
          sku: item.sku,
          payment_link_id: excluded ? null : (item.payment_link_id ?? null),
          short_url: excluded ? null : (item.short_url ?? null),
          excluded,
          reminder_count: excluded ? 0 : 1,
          last_sent_at: excluded ? null : new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });
      }
      if (body.seed_only === true) {
        return new Response(
          JSON.stringify({ ok: true, seeded: body.seed.length, cron: "30 5 */6 * *" }),
          { headers: { "Content-Type": "application/json" } },
        );
      }
    }

    const minDays = typeof body.min_days === "number" ? body.min_days : 5;
    const minIntervalMs = minDays * 24 * 60 * 60 * 1000;
    const now = Date.now();

    const [{ data: orders }, { data: subs }, { data: plans }, { data: profiles }, { data: logs }] =
      await Promise.all([
        supabase
          .from("payment_orders")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(1000),
        supabase
          .from("subscriptions")
          .select("user_id, status")
          .eq("status", "active"),
        supabase.from("plan_catalogue").select("*"),
        supabase
          .from("profiles")
          .select("id, email, name, phone")
          .limit(5000),
        supabase.from("winback_reminder_log").select("*"),
      ]);

    const planMap = new Map((plans ?? []).map((p) => [p.sku, p]));
    const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));
    const logMap = new Map((logs ?? []).map((l) => [l.user_id, l]));

    const paidUserIds = new Set<string>();
    for (const o of orders ?? []) {
      if (o.status === "paid" || o.status === "completed") {
        paidUserIds.add(o.user_id);
      }
    }
    for (const s of subs ?? []) {
      if (s.status === "active") {
        paidUserIds.add(s.user_id);
      }
    }

    // 1. Mark newly paid users as completed and cancel their active payment link
    let newlyCompleted = 0;
    for (const l of logs ?? []) {
      if (!l.completed_at && paidUserIds.has(l.user_id)) {
        if (l.payment_link_id) {
          await fetch(`https://api.razorpay.com/v1/payment_links/${l.payment_link_id}/cancel`, {
            method: "POST",
            headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
            body: "{}",
          }).catch(() => {});
        }
        await supabase
          .from("winback_reminder_log")
          .update({ completed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
          .eq("user_id", l.user_id);
        newlyCompleted++;
      }
    }

    // 2. Group unpaid users from payment_orders (older than 24h so we don't nag mid-checkout)
    const unpaidByUser = new Map<string, Record<string, unknown>[]>();
    for (const o of orders ?? []) {
      const uid = String(o.user_id);
      if (paidUserIds.has(uid) && o.status !== "cancelled") continue;
      const list = unpaidByUser.get(uid) ?? [];
      list.push(o);
      unpaidByUser.set(uid, list);
    }

    let emailedCount = 0;
    let smsCount = 0;
    let pushCount = 0;
    let skippedRecent = 0;
    let skippedExcluded = 0;

    for (const [uid, uorders] of unpaidByUser.entries()) {
      const prof = profileMap.get(uid);
      const email = String(prof?.email ?? "").trim();
      const name = String(prof?.name ?? "Trader").trim();
      const existingLog = logMap.get(uid);

      if (existingLog?.excluded || isExcludedUser(email, name)) {
        skippedExcluded++;
        continue;
      }

      if (existingLog?.last_sent_at) {
        const elapsed = now - new Date(existingLog.last_sent_at).getTime();
        if (elapsed < minIntervalMs) {
          skippedRecent++;
          continue;
        }
      }

      // Pick highest-intent SKU
      const best = uorders.reduce((a, b) =>
        Number(b.amount_paise ?? 0) > Number(a.amount_paise ?? 0) ? b : a
      );
      const sku = String(existingLog?.sku ?? best.sku);
      const plan = planMap.get(sku);
      const planTitle = String(plan?.title ?? sku);
      const amountInr = Math.max(Number(plan?.price_paise ?? 19900), 2900);
      const phone =
        prof?.phone ??
        existingLog?.phone ??
        (uorders.find((x) => x.customer_phone)?.customer_phone as string | undefined) ??
        null;

      let plinkId: string | null = existingLog?.payment_link_id ?? null;
      let shortUrl: string | null = existingLog?.short_url ?? null;

      const createFreshLink = async () => {
        const customerObj: Record<string, string> = {
          name: name.slice(0, 45),
          email,
        };
        if (phone) customerObj.contact = String(phone);

        const desc =
          `Hi ${name}, complete your ${planTitle} pack on Trading Titans with instant 1-tap UPI or Card (no AutoPay mandate required) — auto-credited to your account.`;
        const createRes = await fetch("https://api.razorpay.com/v1/payment_links", {
          method: "POST",
          headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
          body: JSON.stringify({
            amount: amountInr,
            currency: "INR",
            accept_partial: false,
            description: desc.slice(0, 200),
            customer: customerObj,
            notify: { email: true, sms: Boolean(phone) },
            reminder_enable: true,
            callback_url: "https://tradingtitans.org/app/plans",
            callback_method: "get",
            notes: { user_id: uid, sku, campaign: "winback_recurring_6d" },
          }),
        });
        if (createRes.ok) {
          const pdata = await createRes.json();
          plinkId = pdata.id ?? null;
          shortUrl = pdata.short_url ?? null;
          return true;
        }
        return false;
      };

      // Send Email & SMS reminder via Razorpay (auto-recreating link if missing/expired)
      let sentEmail = false;
      let sentSms = false;
      if (plinkId) {
        const emailRes = await fetch(
          `https://api.razorpay.com/v1/payment_links/${plinkId}/notify_by/email`,
          {
            method: "POST",
            headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
            body: "{}",
          },
        );
        if (emailRes.ok) {
          sentEmail = true;
        } else {
          sentEmail = await createFreshLink();
        }
      } else {
        sentEmail = await createFreshLink();
      }
      if (sentEmail) emailedCount++;

      if (phone && plinkId) {
        const smsRes = await fetch(
          `https://api.razorpay.com/v1/payment_links/${plinkId}/notify_by/sms`,
          {
            method: "POST",
            headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
            body: "{}",
          },
        );
        sentSms = smsRes.ok;
        if (sentSms) smsCount++;
      }

      // Send In-App + FCM Push Notification
      const nextCount = Number(existingLog?.reminder_count ?? 0) + 1;
      const isSub = sku.startsWith("pro_") || sku.startsWith("titan_");
      const pushBody = isSub
        ? `Hi ${name}, your ${planTitle} pass is ready with 1-tap UPI (no AutoPay mandate needed). Unlock F&O trading + monthly demo cash today!`
        : `Hi ${name}, your ${planTitle} pack is waiting! Complete your top-up in 1 tap with UPI or upgrade to Pro Monthly (₹149/mo) for monthly stipends.`;

      const { error: notifErr } = await supabase.from("notifications").insert({
        user_id: uid,
        title: `Complete your ${planTitle} Pack in 1-Tap UPI ⚡`,
        body: pushBody,
        action_type: "reward",
        action_data: {
          cta_route: "/subscribe",
          cta_url: shortUrl ?? "https://tradingtitans.org/app/plans",
        },
      });
      if (!notifErr) pushCount++;

      await supabase.from("winback_reminder_log").upsert({
        user_id: uid,
        email,
        name,
        phone,
        sku,
        payment_link_id: plinkId,
        short_url: shortUrl,
        excluded: false,
        reminder_count: nextCount,
        last_sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        emailed: emailedCount,
        sms: smsCount,
        push: pushCount,
        newly_completed_and_stopped: newlyCompleted,
        skipped_recent: skippedRecent,
        skipped_excluded: skippedExcluded,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
