/// The only place in the system that grants paid access or paid cash.
///
/// Everything else — the checkout page, the app, the success redirect — is
/// cosmetic. A user who fakes a "payment succeeded" screen, replays a URL, or
/// closes the tab at the wrong moment gets nothing, because nothing is granted
/// until Razorpay itself tells us here, over a signed request.
///
/// Deployed with verify_jwt: false. Razorpay cannot mint a Supabase JWT, so the
/// authentication is the X-Razorpay-Signature HMAC over the exact raw body. No
/// signature, no effect. That check is the door; treat it as such.
///
/// Delivery is at-least-once, so every path below has to be safe to run twice:
///   - the event row is keyed on Razorpay's own event id
///   - a completed event is recognised by handled_at and short-circuits
///   - apply_paid_topup refuses a second credit via payment_orders.credited_at
///   - apply_subscription_charge pays a stipend once per calendar month
/// Transient failure returns 500 on purpose: Razorpay retries, and the guards
/// above make that retry harmless.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import {
  epochToIso,
  sha256Hex,
  verifyRazorpaySignature,
} from "../_shared/razorpay_signature.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";

const SUB_STATUS: Record<string, string> = {
  "subscription.pending": "pending",
  "subscription.halted": "halted",
  "subscription.paused": "halted",
  "subscription.cancelled": "cancelled",
  "subscription.completed": "expired",
  "subscription.expired": "expired",
};

class Unresolvable extends Error {}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!WEBHOOK_SECRET) {
    return new Response("Webhook not configured", { status: 503 });
  }

  const raw = await req.text();
  const signature = req.headers.get("X-Razorpay-Signature");
  if (!(await verifyRazorpaySignature(raw, signature, WEBHOOK_SECRET))) {
    return new Response("Invalid signature", { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const eventType = String(body.event ?? "");
  const eventId = req.headers.get("X-Razorpay-Event-Id") ??
    `sha:${await sha256Hex(raw)}`;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  const { data: event, error: claimErr } = await supabase
    .from("payment_events")
    .upsert(
      { provider_event_id: eventId, event_type: eventType, payload: body },
      { onConflict: "provider_event_id" },
    )
    .select("id, handled_at")
    .single();

  if (claimErr || !event) {
    return new Response("Could not record event", { status: 500 });
  }
  if (event.handled_at) {
    return new Response(JSON.stringify({ ok: true, duplicate: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    await handle(supabase, eventType, body, event.id);
    await supabase.from("payment_events")
      .update({ handled_at: new Date().toISOString(), handler_error: null })
      .eq("id", event.id);
    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    const permanent = e instanceof Unresolvable;
    await supabase.from("payment_events")
      .update({
        handler_error: message,
        handled_at: permanent ? new Date().toISOString() : null,
      })
      .eq("id", event.id);
    return new Response(JSON.stringify({ ok: permanent, error: message }), {
      status: permanent ? 200 : 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// deno-lint-ignore no-explicit-any
async function recordCustomerContact(supabase: any, payload: Record<string, any>) {
  try {
    const payment = payload.payment?.entity;
    const order = payload.order?.entity;
    const sub = payload.subscription?.entity;
    const link = payload.payment_link?.entity;

    const rawContact = payment?.contact ?? link?.customer?.contact;
    const contact = typeof rawContact === "string" ? rawContact.trim() : "";
    if (!contact) return;

    const providerOrderId: string | undefined = order?.id ?? payment?.order_id;
    let userId: string | undefined =
      payment?.notes?.user_id ??
      order?.notes?.user_id ??
      sub?.notes?.user_id ??
      link?.notes?.user_id;

    if (providerOrderId) {
      try {
        await supabase
          .from("payment_orders")
          .update({ customer_phone: contact })
          .eq("provider_order_id", providerOrderId);
      } catch (_) { /* non-fatal */ }

      if (!userId) {
        const { data: ordRow } = await supabase
          .from("payment_orders")
          .select("user_id")
          .eq("provider_order_id", providerOrderId)
          .maybeSingle();
        if (ordRow?.user_id) userId = ordRow.user_id;
      }
    }

    if (!userId && typeof payment?.email === "string" && payment.email.trim()) {
      const { data: profRow } = await supabase
        .from("profiles")
        .select("id")
        .ilike("email", payment.email.trim())
        .maybeSingle();
      if (profRow?.id) userId = profRow.id;
    }

    if (userId) {
      try {
        await supabase
          .from("profiles")
          .update({ phone: contact })
          .eq("id", userId);
      } catch (_) { /* non-fatal */ }
      try {
        const { data: u } = await supabase.auth.admin.getUserById(userId);
        const existingMeta = u?.user?.user_metadata ?? {};
        if (existingMeta.phone !== contact) {
          await supabase.auth.admin.updateUserById(userId, {
            user_metadata: { ...existingMeta, phone: contact },
          });
        }
      } catch (_) { /* non-fatal */ }
    }
  } catch (_) {
    // Contact persistence must never block payment fulfillment
  }
}

// deno-lint-ignore no-explicit-any
async function handle(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  eventType: string,
  body: Record<string, unknown>,
  eventRowId: string,
): Promise<void> {
  // deno-lint-ignore no-explicit-any
  const payload = (body.payload ?? {}) as Record<string, any>;

  // Always capture customer mobile number on every payment event (including payment.failed)
  await recordCustomerContact(supabase, payload);

  if (eventType === "order.paid" || eventType === "payment.captured") {
    const order = payload.order?.entity;
    const payment = payload.payment?.entity;
    const providerOrderId: string | undefined = order?.id ?? payment?.order_id;
    if (!providerOrderId) throw new Unresolvable("no order id in payload");

    const { data: row, error } = await supabase
      .from("payment_orders")
      .select("id, user_id, sku, kind, status, amount_paise, currency, credited_at, provider_subscription_id")
      .eq("provider_order_id", providerOrderId)
      .maybeSingle();
    if (error) throw new Error(error.message);

    // Subscription invoices and orders created by a Payment Link are handled by
    // subscription.charged / payment_link.paid if no direct order row exists.
    if (!row) return;

    await supabase.from("payment_events")
      .update({ order_id: row.id }).eq("id", eventRowId);

    const paidMinor = Number(order?.amount_paid ?? payment?.amount ?? 0);
    const paidCurrency = order?.currency ?? payment?.currency ?? null;

    if (row.kind === "subscription") {
      await creditSubscriptionOrder(
        supabase,
        row,
        paidMinor,
        paidCurrency,
        providerOrderId,
      );
    } else {
      await creditTopup(
        supabase,
        row,
        paidMinor,
        paidCurrency,
        providerOrderId,
      );
    }
    return;
  }

  if (eventType === "payment_link.paid") {
    const link = payload.payment_link?.entity;
    const payment = payload.payment?.entity;
    if (!link?.id) throw new Unresolvable("no payment link id in payload");

    let { data: row, error } = await supabase
      .from("payment_orders")
      .select("id, user_id, sku, kind, status, amount_paise, currency, credited_at, provider_subscription_id")
      .eq("provider_payment_link_id", link.id)
      .maybeSingle();
    if (error) throw new Error(error.message);

    if (!row) {
      row = await ensurePaymentLinkOrderRow(supabase, link, payment);
    }
    if (!row) throw new Unresolvable(`payment link ${link.id} was not created here`);

    await supabase.from("payment_events")
      .update({ order_id: row.id }).eq("id", eventRowId);

    const paidMinor = Number(link.amount_paid ?? payment?.amount ?? 0);
    const paidCurrency = link.currency ?? payment?.currency ?? null;

    if (row.kind === "subscription") {
      await creditSubscriptionOrder(
        supabase,
        row,
        paidMinor,
        paidCurrency,
        link.id,
      );
    } else {
      await creditTopup(
        supabase,
        row,
        paidMinor,
        paidCurrency,
        link.id,
      );
    }
    return;
  }

  if (
    eventType === "subscription.activated" ||
    eventType === "subscription.charged"
  ) {
    const sub = payload.subscription?.entity;
    const subId: string | undefined = sub?.id;
    if (!subId) throw new Unresolvable("no subscription id in payload");

    await ensureSubscriptionRow(supabase, sub);

    const { error } = await supabase.rpc("apply_subscription_charge", {
      p_provider_subscription_id: subId,
      p_period_start: epochToIso(sub?.current_start),
      p_period_end: epochToIso(sub?.current_end),
    });
    if (error) throw new Error(error.message);
    return;
  }

  const mapped = SUB_STATUS[eventType];
  if (mapped) {
    const sub = payload.subscription?.entity;
    if (!sub?.id) throw new Unresolvable("no subscription id in payload");
    const { error } = await supabase.from("subscriptions")
      .update({
        status: mapped,
        current_period_end: epochToIso(sub.current_end),
        cancel_at_period_end: eventType === "subscription.cancelled",
        updated_at: new Date().toISOString(),
      })
      .eq("provider_subscription_id", sub.id);
    if (error) throw new Error(error.message);
    return;
  }
}

// deno-lint-ignore no-explicit-any
async function creditTopup(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  row: { id: string; user_id?: string; status: string; amount_paise: number; currency: string | null },
  paidMinor: number,
  paidCurrency: string | null,
  ref: string,
): Promise<void> {
  const expected = (row.currency ?? "INR").toUpperCase();
  if (paidCurrency && paidCurrency.toUpperCase() !== expected) {
    throw new Unresolvable(
      `currency mismatch on ${ref}: paid ${paidCurrency}, order is ${expected}`,
    );
  }

  if (paidMinor < Number(row.amount_paise)) {
    throw new Unresolvable(
      `underpaid: ${paidMinor} < ${row.amount_paise} for ${ref}`,
    );
  }

  if (row.status === "created") {
    const { error } = await supabase.from("payment_orders")
      .update({ status: "paid", paid_at: new Date().toISOString() })
      .eq("id", row.id).eq("status", "created");
    if (error) throw new Error(error.message);
  }

  const { error } = await supabase.rpc("apply_paid_topup", { p_order_id: row.id });
  if (error) throw new Error(error.message);

  if (row.user_id) {
    try {
      await supabase
        .from("winback_reminder_log")
        .update({ completed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("user_id", row.user_id);
    } catch (_) { /* non-fatal */ }
  }
}

/// Activates a prepaid subscription order (30 days for monthly, 365 days for annual)
/// and credits the plan's monthly stipend via `apply_subscription_charge`.
// deno-lint-ignore no-explicit-any
async function creditSubscriptionOrder(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  row: {
    id: string;
    user_id: string;
    sku: string;
    status: string;
    amount_paise: number;
    currency: string | null;
    credited_at?: string | null;
    provider_subscription_id?: string | null;
  },
  paidMinor: number,
  paidCurrency: string | null,
  ref: string,
): Promise<void> {
  const expected = (row.currency ?? "INR").toUpperCase();
  if (paidCurrency && paidCurrency.toUpperCase() !== expected) {
    throw new Unresolvable(
      `currency mismatch on ${ref}: paid ${paidCurrency}, order is ${expected}`,
    );
  }

  if (paidMinor < Number(row.amount_paise)) {
    throw new Unresolvable(
      `underpaid: ${paidMinor} < ${row.amount_paise} for ${ref}`,
    );
  }

  // Idempotency guard if already credited
  if (row.credited_at) return;

  const { data: plan } = await supabase
    .from("plan_catalogue")
    .select("tier, billing_interval")
    .eq("sku", row.sku)
    .maybeSingle();
  if (!plan) throw new Unresolvable(`unknown sku ${row.sku}`);

  const subId = row.provider_subscription_id ?? ref;

  const { data: existingSub } = await supabase
    .from("subscriptions")
    .select("id")
    .eq("provider_subscription_id", subId)
    .maybeSingle();

  if (!existingSub) {
    const { error: subInsErr } = await supabase.from("subscriptions").insert({
      user_id: row.user_id,
      sku: row.sku,
      tier: plan.tier,
      provider_subscription_id: subId,
      status: "created",
    });
    if (subInsErr && !String(subInsErr.message).includes("duplicate key")) {
      throw new Error(subInsErr.message);
    }
  }

  const now = new Date();
  const durationDays = plan.billing_interval === "annual" ? 365 : 30;
  const periodEnd = new Date(now.getTime() + durationDays * 24 * 60 * 60 * 1000);

  const { error: chargeErr } = await supabase.rpc("apply_subscription_charge", {
    p_provider_subscription_id: subId,
    p_period_start: now.toISOString(),
    p_period_end: periodEnd.toISOString(),
  });
  if (chargeErr) throw new Error(chargeErr.message);

  const nowIso = now.toISOString();
  const { error: updErr } = await supabase
    .from("payment_orders")
    .update({ status: "paid", paid_at: nowIso, credited_at: nowIso })
    .eq("id", row.id);
  if (updErr) throw new Error(updErr.message);

  try {
    await supabase
      .from("winback_reminder_log")
      .update({ completed_at: nowIso, updated_at: nowIso })
      .eq("user_id", row.user_id);
  } catch (_) { /* non-fatal */ }
}

/// Auto-attributes a Payment Link created via Razorpay MCP or Dashboard when
/// `notes.user_id` and `notes.sku` are attached to the link.
// deno-lint-ignore no-explicit-any
async function ensurePaymentLinkOrderRow(supabase: any, link: any, payment: any) {
  const userId: string | undefined = link?.notes?.user_id ?? payment?.notes?.user_id;
  const sku: string | undefined = link?.notes?.sku ?? payment?.notes?.sku;
  if (!userId || !sku) return null;

  const { data: plan } = await supabase
    .from("plan_catalogue")
    .select("sku, tier, kind, price_paise, price_usd_cents")
    .eq("sku", sku)
    .maybeSingle();
  if (!plan) throw new Unresolvable(`unknown sku ${sku}`);

  const currency = String(link?.currency ?? payment?.currency ?? "INR").toUpperCase();
  const expectedAmount = currency === "USD"
    ? Number(plan.price_usd_cents ?? link?.amount ?? 0)
    : Number(plan.price_paise ?? link?.amount ?? 0);

  const insertPayload: Record<string, unknown> = {
    user_id: userId,
    sku: plan.sku,
    kind: plan.kind,
    provider_payment_link_id: link.id,
    provider_subscription_id: plan.kind === "subscription" ? link.id : null,
    amount_paise: expectedAmount,
    currency,
    status: "created",
  };

  const { data: created, error } = await supabase
    .from("payment_orders")
    .insert(insertPayload)
    .select("id, user_id, sku, kind, status, amount_paise, currency, credited_at, provider_subscription_id")
    .single();

  if (error) {
    const { data: retry } = await supabase
      .from("payment_orders")
      .select("id, user_id, sku, kind, status, amount_paise, currency, credited_at, provider_subscription_id")
      .eq("provider_payment_link_id", link.id)
      .maybeSingle();
    return retry;
  }
  return created;
}

// deno-lint-ignore no-explicit-any
async function ensureSubscriptionRow(supabase: any, sub: any): Promise<void> {
  const { data: existing } = await supabase.from("subscriptions")
    .select("id").eq("provider_subscription_id", sub.id).maybeSingle();
  if (existing) return;

  const userId: string | undefined = sub?.notes?.user_id;
  const sku: string | undefined = sub?.notes?.sku;
  if (!userId || !sku) {
    throw new Unresolvable(
      `subscription ${sub.id} has no user_id/sku in notes; cannot attribute`,
    );
  }

  const { data: plan } = await supabase.from("plan_catalogue")
    .select("tier").eq("sku", sku).maybeSingle();
  if (!plan) throw new Unresolvable(`unknown sku ${sku}`);

  const { error } = await supabase.from("subscriptions").insert({
    user_id: userId,
    sku,
    tier: plan.tier,
    provider_subscription_id: sub.id,
    status: "created",
  });
  if (error && !String(error.message).includes("duplicate key")) {
    throw new Error(error.message);
  }
}
