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

/// Thrown for events that will never succeed no matter how often Razorpay
/// retries — an unattributable subscription, a payment for an order we never
/// created. Recorded and acknowledged, so the retry queue does not fill up with
/// something no retry can fix.
class Unresolvable extends Error {}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!WEBHOOK_SECRET) {
    // Better to reject and let Razorpay retry than to accept unverified money
    // events during a misconfiguration.
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
  // Razorpay's own event id is the idempotency key. If a delivery ever arrives
  // without one, fall back to a digest of the body so replays still collapse.
  const eventId = req.headers.get("X-Razorpay-Event-Id") ??
    `sha:${await sha256Hex(raw)}`;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

  // Claim the event. Upsert (not insert) so a retry hands back the row we
  // already have instead of failing, and handled_at survives because we do not
  // list it here.
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
        // Permanent failures are marked handled so Razorpay stops retrying;
        // handler_error is what makes them findable afterwards.
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
async function handle(
  supabase: any,
  eventType: string,
  body: Record<string, unknown>,
  eventRowId: string,
): Promise<void> {
  // deno-lint-ignore no-explicit-any
  const payload = (body.payload ?? {}) as Record<string, any>;

  if (eventType === "order.paid" || eventType === "payment.captured") {
    const order = payload.order?.entity;
    const payment = payload.payment?.entity;
    const providerOrderId: string | undefined = order?.id ?? payment?.order_id;
    if (!providerOrderId) throw new Unresolvable("no order id in payload");

    const { data: row, error } = await supabase
      .from("payment_orders")
      .select("id, status, amount_paise, currency, credited_at")
      .eq("provider_order_id", providerOrderId)
      .maybeSingle();
    if (error) throw new Error(error.message);

    // Subscription invoices, and the orders a Payment Link creates for itself,
    // are Razorpay orders we never made. Nothing to do here; the
    // subscription.charged and payment_link.paid deliveries carry that money.
    if (!row) return;

    await supabase.from("payment_events")
      .update({ order_id: row.id }).eq("id", eventRowId);

    await creditTopup(
      supabase,
      row,
      Number(order?.amount_paid ?? payment?.amount ?? 0),
      order?.currency ?? payment?.currency ?? null,
      providerOrderId,
    );
    return;
  }

  // The Android app's checkout. It opens a Razorpay-hosted Payment Link rather
  // than running the SDK, so this is the delivery that carries the money — the
  // order.paid that also fires belongs to an order Razorpay created for the link,
  // which we never inserted, so it finds no row and no-ops above.
  if (eventType === "payment_link.paid") {
    const link = payload.payment_link?.entity;
    const payment = payload.payment?.entity;
    if (!link?.id) throw new Unresolvable("no payment link id in payload");

    const { data: row, error } = await supabase
      .from("payment_orders")
      .select("id, status, amount_paise, currency, credited_at")
      .eq("provider_payment_link_id", link.id)
      .maybeSingle();
    if (error) throw new Error(error.message);
    // Unlike a stray order, a link we have no row for cannot be attributed to
    // anyone — recorded with an error so it is findable, and acknowledged so the
    // retry queue does not fill with something no retry can fix.
    if (!row) throw new Unresolvable(`payment link ${link.id} was not created here`);

    await supabase.from("payment_events")
      .update({ order_id: row.id }).eq("id", eventRowId);

    await creditTopup(
      supabase,
      row,
      Number(link.amount_paid ?? payment?.amount ?? 0),
      link.currency ?? payment?.currency ?? null,
      link.id,
    );
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

  // Anything else (authenticated, updated, payment.failed, refunds) is recorded
  // in payment_events and deliberately does nothing. Notably
  // subscription.authenticated means the mandate exists but no money has moved,
  // so granting there would hand out a paid tier for free.
}

/// Marks a one-time order paid and credits it, whichever way the money arrived.
///
/// Shared by `order.paid`/`payment.captured` (web Checkout) and
/// `payment_link.paid` (the app's hosted page) so the two guards below hold on
/// both routes, rather than only on the one that happened to be written first.
// deno-lint-ignore no-explicit-any
async function creditTopup(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  row: { id: string; status: string; amount_paise: number; currency: string | null },
  paidMinor: number,
  paidCurrency: string | null,
  ref: string,
): Promise<void> {
  // `amount_paise` is minor units of the ORDER's currency — paise for INR, cents
  // for USD — so comparing it against an amount in another currency is
  // meaningless. Worse, it is meaningless in the dangerous direction: 19900 paise
  // against a 249-cent order reads as a generous overpayment and would sail
  // through the check below. Reject the mismatch before comparing, not after.
  const expected = (row.currency ?? "INR").toUpperCase();
  if (paidCurrency && paidCurrency.toUpperCase() !== expected) {
    throw new Unresolvable(
      `currency mismatch on ${ref}: paid ${paidCurrency}, order is ${expected}`,
    );
  }

  // Underpayment must never buy the full grant. Razorpay only marks things paid
  // at the full amount, so this is a belt on top of a brace — but it is the belt
  // that holds if a partial-payment flag is ever switched on.
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
}

/// A subscription created through our own checkout already has a row. One
/// created straight from the Razorpay dashboard does not, and would otherwise
/// fail forever. The notes we attach at creation are what make it recoverable.
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
  // A concurrent delivery may have inserted it first; that is fine.
  if (error && !String(error.message).includes("duplicate key")) {
    throw new Error(error.message);
  }
}
