/// Starts a checkout. Returns what Razorpay Checkout needs, nothing more.
///
/// The client tells us a SKU (and optionally the user's mobile number for
/// prefill/receipts); the server decides the price from `plan_catalogue`.
///
/// Nothing here grants anything. Access and cash are granted only by
/// razorpay-webhook, after a signature-verified payment event.
///
/// ONE-TIME & PREPAID SUBSCRIPTION ORDERS
/// By default, both top-ups and subscriptions (`pro_monthly`, `titan_monthly`,
/// `pro_annual`, `titan_annual`) create a standard 1-tap Razorpay Order
/// (`/v1/orders`) rather than forcing a 10-year UPI AutoPay e-Mandate
/// (`/v1/subscriptions`), which previously caused 97.5% of Indian UPI buyers to
/// drop off or time out. When the order is paid, `razorpay-webhook` activates the
/// user's subscription for 30 days (monthly) or 365 days (annual) and credits
/// their monthly stipend via `apply_subscription_charge`.
/// If a caller explicitly passes `recurring: true`, the `/v1/subscriptions`
/// mandate path remains available.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { Client as PgClient } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const RZP_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
const RZP_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const DB_URL = Deno.env.get("SUPABASE_DB_URL") ?? "";

const RZP_AUTH = "Basic " + btoa(`${RZP_KEY_ID}:${RZP_KEY_SECRET}`);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const TOTAL_COUNT: Record<string, number> = { monthly: 120, annual: 10 };
const TIER_RANK: Record<string, number> = { free: 0, pro: 1, titan: 2 };

const PAY_PAGE = Deno.env.get("PAY_PAGE_URL") ??
  "https://thetradingtitans.com/app/pay";

function payUrl(params: Record<string, string>): string {
  const url = new URL(PAY_PAGE);
  for (const [key, value] of Object.entries(params)) {
    if (value) url.searchParams.set(key, value);
  }
  return url.toString();
}

function normalizePhone(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const cleaned = raw.replace(/[^\d+]/g, "").trim();
  if (!cleaned) return "";
  // 10-digit Indian mobile number -> prefix +91
  if (/^[6-9]\d{9}$/.test(cleaned)) {
    return `+91${cleaned}`;
  }
  // 12-digit starting with 91 -> prefix +
  if (/^91[6-9]\d{9}$/.test(cleaned)) {
    return `+${cleaned}`;
  }
  if (/^\+?\d{8,15}$/.test(cleaned)) {
    return cleaned.startsWith("+") ? cleaned : `+${cleaned}`;
  }
  return "";
}

let schemaChecked = false;
async function ensurePhoneColumnsOnce() {
  if (schemaChecked || !DB_URL) return;
  schemaChecked = true;
  try {
    const client = new PgClient(DB_URL);
    await client.connect();
    await client.queryArray(`
      alter table public.profiles add column if not exists phone text;
      alter table public.payment_orders add column if not exists customer_phone text;
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
      notify pgrst, 'reload schema';
    `);
    await client.end();
  } catch (err) {
    console.warn("ensurePhoneColumnsOnce warning:", err);
  }
}

Deno.serve(async (req: Request) => {
  const pre = handleCors(req);
  if (pre) return pre;

  try {
    await ensurePhoneColumnsOnce();

    if (!RZP_KEY_ID || !RZP_KEY_SECRET) {
      return json({ error: "Payments are not configured yet." }, 503);
    }

    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing Authorization" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Invalid token" }, 401);
    const user = userData.user;

    if ((user as { is_anonymous?: boolean }).is_anonymous === true) {
      return json({ error: "Please create an account before purchasing." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const sku = typeof body.sku === "string" ? body.sku.trim() : "";
    if (!sku) return json({ error: "sku required" }, 400);
    const hosted = body.mode === "hosted";
    const useRecurringMandate = body.recurring === true;
    const submittedPhone = normalizePhone(body.contact ?? body.phone);

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    try {
      const { data: allowed } = await supabase.rpc("check_rate_limit", {
        p_key: `create-payment-order:${user.id}`, p_max: 15, p_window_seconds: 60,
      });
      if (allowed === false) {
        return json({ error: "Too many attempts. Please wait a moment." }, 429);
      }
    } catch (_) { /* fail open, as place-order does */ }

    const { data: plan } = await supabase
      .from("plan_catalogue")
      .select("sku, tier, kind, title, price_paise, price_usd_cents, billing_interval, razorpay_plan_id, razorpay_plan_id_usd, is_active")
      .eq("sku", sku).maybeSingle();

    if (!plan || plan.is_active !== true) {
      return json({ error: "That plan is not available." }, 404);
    }

    // ── Fetch user profile & resolve prefill details (email, name, phone) ─────
    const { data: prof } = await supabase
      .from("profiles")
      .select("location, email, name")
      .eq("id", user.id)
      .maybeSingle();

    let storedPhone = "";
    try {
      const { data: phoneRow } = await supabase
        .from("profiles")
        .select("phone")
        .eq("id", user.id)
        .maybeSingle();
      if (phoneRow && typeof (phoneRow as { phone?: string }).phone === "string") {
        storedPhone = normalizePhone((phoneRow as { phone?: string }).phone);
      }
    } catch (_) { /* column may still be reloading */ }

    const metaPhone = normalizePhone(
      (user.user_metadata as Record<string, unknown> | undefined)?.phone ?? user.phone,
    );
    const resolvedPhone = submittedPhone || storedPhone || metaPhone;
    const resolvedEmail = (prof?.email ?? user.email ?? "").trim();
    const resolvedName = (
      prof?.name ??
      ((user.user_metadata as Record<string, unknown> | undefined)?.name as string | undefined) ??
      ""
    ).trim();

    // Persist newly submitted phone number to auth.users metadata and profiles.phone
    if (submittedPhone && submittedPhone !== metaPhone) {
      try {
        await supabase.auth.admin.updateUserById(user.id, {
          user_metadata: { ...(user.user_metadata ?? {}), phone: submittedPhone },
        });
      } catch (_) { /* non-fatal */ }
    }
    if (resolvedPhone && resolvedPhone !== storedPhone) {
      try {
        await supabase.from("profiles").update({ phone: resolvedPhone }).eq("id", user.id);
      } catch (_) { /* non-fatal */ }
    }

    const usd = prof?.location === "outside_india";
    const currency = usd ? "USD" : "INR";

    const amount: number | null = usd ? plan.price_usd_cents : plan.price_paise;
    if (!amount || amount <= 0) {
      return json({ error: `That plan is not available in ${currency} yet.` }, 409);
    }

    const prefill = {
      email: resolvedEmail || undefined,
      name: resolvedName || undefined,
      contact: resolvedPhone || undefined,
    };

    if (plan.kind === "subscription") {
      // Only block if the user already has an ACTIVE or PENDING subscription of
      // the same or higher tier. Abandoned 'created' checkouts never lock the
      // user out of retrying, and Pro users can upgrade to Titan.
      const { data: live } = await supabase
        .from("subscriptions")
        .select("id, tier, status, current_period_end")
        .eq("user_id", user.id)
        .in("status", ["active", "pending"])
        .order("created_at", { ascending: false });

      const nowMs = Date.now();
      const targetRank = TIER_RANK[plan.tier] ?? 1;
      const blocking = (live ?? []).find((s: {
        tier: string;
        status: string;
        current_period_end: string | null;
      }) => {
        const notExpired = !s.current_period_end ||
          new Date(s.current_period_end).getTime() > nowMs;
        const rank = TIER_RANK[s.tier] ?? 0;
        return notExpired && rank >= targetRank;
      });

      if (blocking) {
        return json({
          error: `You already have an active ${blocking.tier.toUpperCase()} subscription.`,
        }, 409);
      }

      // Optional recurring mandate path if explicitly requested
      if (useRecurringMandate) {
        const providerPlanId: string | null = usd
          ? plan.razorpay_plan_id_usd
          : plan.razorpay_plan_id;
        if (!providerPlanId) {
          return json(
            { error: `That plan is not open for subscription in ${currency} yet.` },
            409,
          );
        }

        const rzpRes = await fetch("https://api.razorpay.com/v1/subscriptions", {
          method: "POST",
          headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
          body: JSON.stringify({
            plan_id: providerPlanId,
            total_count: TOTAL_COUNT[plan.billing_interval as string] ?? 12,
            customer_notify: 1,
            notes: {
              user_id: user.id,
              sku: plan.sku,
              ...(resolvedEmail ? { email: resolvedEmail } : {}),
              ...(resolvedName ? { name: resolvedName } : {}),
              ...(resolvedPhone ? { phone: resolvedPhone } : {}),
            },
          }),
        });
        const rzp = await rzpRes.json().catch(() => ({}));
        if (!rzpRes.ok || !rzp?.id) {
          return json({ error: rzp?.error?.description ?? "Could not start the subscription." }, 502);
        }

        const orderInsert: Record<string, unknown> = {
          user_id: user.id,
          sku: plan.sku,
          kind: "subscription",
          provider_subscription_id: rzp.id,
          amount_paise: amount,
          currency,
          status: "created",
        };
        if (resolvedPhone) orderInsert.customer_phone = resolvedPhone;
        const { error: insErr } = await supabase.from("payment_orders").insert(orderInsert);
        if (insErr && resolvedPhone) {
          delete orderInsert.customer_phone;
          await supabase.from("payment_orders").insert(orderInsert);
        }

        await supabase.from("subscriptions").insert({
          user_id: user.id,
          sku: plan.sku,
          tier: plan.tier,
          provider_subscription_id: rzp.id,
          status: "created",
        });

        return json({
          kind: "subscription",
          keyId: RZP_KEY_ID,
          subscriptionId: rzp.id,
          title: plan.title,
          currency,
          amountPaise: amount,
          prefill,
          url: hosted
            ? payUrl({
                key: RZP_KEY_ID,
                sub: rzp.id,
                amount: String(amount),
                currency,
                title: plan.title,
                email: resolvedEmail,
                name: resolvedName,
                contact: resolvedPhone,
              })
            : null,
        });
      }

      // ── Default Subscription Checkout: 1-Tap Prepaid Order (/v1/orders) ────
      const receipt = `tt_${plan.sku}_${Date.now()}`;
      const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
        body: JSON.stringify({
          amount,
          currency,
          receipt,
          notes: {
            user_id: user.id,
            sku: plan.sku,
            kind: "subscription",
            tier: plan.tier,
            billing_interval: plan.billing_interval ?? "monthly",
            ...(resolvedEmail ? { email: resolvedEmail } : {}),
            ...(resolvedName ? { name: resolvedName } : {}),
            ...(resolvedPhone ? { phone: resolvedPhone } : {}),
          },
        }),
      });
      const rzp = await rzpRes.json().catch(() => ({}));
      if (!rzpRes.ok || !rzp?.id) {
        return json({ error: rzp?.error?.description ?? "Could not start the payment." }, 502);
      }

      const subOrderInsert: Record<string, unknown> = {
        user_id: user.id,
        sku: plan.sku,
        kind: "subscription",
        provider_order_id: rzp.id,
        provider_subscription_id: rzp.id,
        amount_paise: amount,
        currency,
        status: "created",
      };
      if (resolvedPhone) subOrderInsert.customer_phone = resolvedPhone;
      const { error: subOrdErr } = await supabase.from("payment_orders").insert(subOrderInsert);
      if (subOrdErr && resolvedPhone) {
        delete subOrderInsert.customer_phone;
        await supabase.from("payment_orders").insert(subOrderInsert);
      }

      await supabase.from("subscriptions").insert({
        user_id: user.id,
        sku: plan.sku,
        tier: plan.tier,
        provider_subscription_id: rzp.id,
        status: "created",
      });

      return json({
        kind: "subscription",
        keyId: RZP_KEY_ID,
        orderId: rzp.id,
        subscriptionId: rzp.id,
        isPrepaidOrder: true,
        title: plan.title,
        currency,
        amountPaise: amount,
        prefill,
        url: hosted
          ? payUrl({
              key: RZP_KEY_ID,
              order: rzp.id,
              amount: String(amount),
              currency,
              title: plan.title,
              email: resolvedEmail,
              name: resolvedName,
              contact: resolvedPhone,
            })
          : null,
      });
    }

    // ── One-time top-up ──────────────────────────────────────────────────────
    const receipt = `tt_${plan.sku}_${Date.now()}`;

    const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount,
        currency,
        receipt,
        notes: {
          user_id: user.id,
          sku: plan.sku,
          kind: "one_time",
          ...(resolvedEmail ? { email: resolvedEmail } : {}),
          ...(resolvedName ? { name: resolvedName } : {}),
          ...(resolvedPhone ? { phone: resolvedPhone } : {}),
        },
      }),
    });
    const rzp = await rzpRes.json().catch(() => ({}));
    if (!rzpRes.ok || !rzp?.id) {
      return json({ error: rzp?.error?.description ?? "Could not start the payment." }, 502);
    }

    const topupInsert: Record<string, unknown> = {
      user_id: user.id,
      sku: plan.sku,
      kind: "one_time",
      provider_order_id: rzp.id,
      amount_paise: amount,
      currency,
      status: "created",
    };
    if (resolvedPhone) topupInsert.customer_phone = resolvedPhone;
    const { error: topupErr } = await supabase.from("payment_orders").insert(topupInsert);
    if (topupErr && resolvedPhone) {
      delete topupInsert.customer_phone;
      await supabase.from("payment_orders").insert(topupInsert);
    }

    return json({
      kind: "one_time",
      keyId: RZP_KEY_ID,
      orderId: rzp.id,
      title: plan.title,
      currency,
      amountPaise: amount,
      prefill,
      url: hosted
        ? payUrl({
            key: RZP_KEY_ID,
            order: rzp.id,
            amount: String(amount),
            currency,
            title: plan.title,
            email: resolvedEmail,
            name: resolvedName,
            contact: resolvedPhone,
          })
        : null,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
