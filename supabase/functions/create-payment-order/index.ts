/// Starts a checkout. Returns what Razorpay Checkout needs, nothing more.
///
/// The browser tells us a SKU; the server decides the price. That direction
/// matters: if the client sent an amount, a user could buy ₹10,00,000 of virtual
/// cash for ₹1 by editing one number. Prices come from `plan_catalogue`.
///
/// Nothing here grants anything. Access and cash are granted only by
/// razorpay-webhook, after a signature-verified payment event. A user who closes
/// the browser mid-payment, or fakes a success redirect, gets nothing.
///
/// TWO CALLERS, ONE ORDER
/// The web app runs Razorpay Checkout in its own page, so it needs the ids to hand
/// the SDK. The Android app has no web session and should not need one — making
/// someone sign in a second time just to buy something was losing purchases — so
/// it passes `mode: "hosted"` and gets back a URL for the standalone checkout page
/// at /app/pay, which runs the same SDK with no login.
///
/// The Razorpay order or subscription is created identically either way. Only the
/// response differs, which is deliberate: it means the two clients cannot end up
/// charging different amounts for the same SKU.
///
/// Razorpay Payment Links were tried first and abandoned. This account has
/// customer contact as a required field on links, and we hold no phone number for
/// any of the 206 accounts, so every link creation failed with "customer contact
/// is required". `payment_orders.provider_payment_link_id` and the webhook's
/// `payment_link.paid` handler remain for that path in case the setting is ever
/// relaxed; nothing here writes them today.
///
/// CURRENCY
/// Chosen here, from `profiles.location`, and never accepted from the client. See
/// the note at the resolution site for why residency rather than display
/// preference.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const RZP_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
const RZP_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;

const RZP_AUTH = "Basic " + btoa(`${RZP_KEY_ID}:${RZP_KEY_SECRET}`);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// Billing cycles to authorise up front. Razorpay requires a finite total_count,
/// so "until cancelled" is expressed as a long horizon: 10 years either way.
/// ponytail: when a subscription runs past this it simply ends and the user
/// re-subscribes. The ceiling is a decade; the upgrade path is a cron that tops
/// total_count up before it runs out.
const TOTAL_COUNT: Record<string, number> = { monthly: 120, annual: 10 };

/// The standalone checkout page the app opens. Overridable so the domain can move
/// without a redeploy; the fallback has to be right on its own, because a shipped
/// APK cannot be corrected if this is wrong.
const PAY_PAGE = Deno.env.get("PAY_PAGE_URL") ??
  "https://thetradingtitans.com/app/pay";

/// Builds the checkout-page URL. Every value here is an opaque provider id or a
/// price Razorpay already holds — no session, token or user id is ever put in a
/// URL, because a URL ends up in browser history, Referer headers and proxy logs.
function payUrl(params: Record<string, string>): string {
  const url = new URL(PAY_PAGE);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

Deno.serve(async (req: Request) => {
  const pre = handleCors(req);
  if (pre) return pre;

  try {
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

    // A guest has no durable account, so anything bought would evaporate on
    // sign-out. Refuse before taking money, not after.
    if ((user as { is_anonymous?: boolean }).is_anonymous === true) {
      return json({ error: "Please create an account before purchasing." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const sku = typeof body.sku === "string" ? body.sku.trim() : "";
    if (!sku) return json({ error: "sku required" }, 400);
    // Only affects how the user reaches Razorpay, never what they are charged, so
    // it is safe to take from the client.
    const hosted = body.mode === "hosted";

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    try {
      const { data: allowed } = await supabase.rpc("check_rate_limit", {
        p_key: `create-payment-order:${user.id}`, p_max: 10, p_window_seconds: 60,
      });
      if (allowed === false) {
        return json({ error: "Too many attempts. Please wait a moment." }, 429);
      }
    } catch (_) { /* fail open, as place-order does */ }

    const { data: plan } = await supabase
      .from("plan_catalogue")
      // One line on purpose: supabase-js infers the row type from this string as a
      // literal, and splitting it across a concatenation degrades every field to
      // `GenericStringError`.
      .select("sku, tier, kind, title, price_paise, price_usd_cents, billing_interval, razorpay_plan_id, razorpay_plan_id_usd, is_active")
      .eq("sku", sku).maybeSingle();

    if (!plan || plan.is_active !== true) return json({ error: "That plan is not available." }, 404);

    // ── Which currency this account is billed in ─────────────────────────────
    //
    // Residency, NOT `display_currency`. Eight accounts sit in India with a
    // dollar display; that setting is cosmetic and must not decide what Razorpay
    // charges, or a rupee customer gets billed in dollars because they liked the
    // look of it. A NULL location predates the question and is treated as India,
    // which is where all but 23 accounts are.
    const { data: prof } = await supabase
      .from("profiles").select("location").eq("id", user.id).maybeSingle();
    const usd = prof?.location === "outside_india";
    const currency = usd ? "USD" : "INR";

    // Minor units of `currency`: paise for INR, cents for USD. The two prices are
    // independent price points, each matching a Razorpay plan exactly — never a
    // conversion of the other, because a plan's amount is immutable and a
    // converted figure would quote one price and charge another.
    const amount: number | null = usd ? plan.price_usd_cents : plan.price_paise;
    if (!amount || amount <= 0) {
      return json({ error: `That plan is not available in ${currency} yet.` }, 409);
    }

    if (plan.kind === "subscription") {
      // A subscription SKU with no plan id is not sellable — that NULL is how we
      // avoid selling something Razorpay cannot actually bill. There is one per
      // currency, and the USD half was added later, so both are checked.
      const providerPlanId: string | null = usd
        ? plan.razorpay_plan_id_usd
        : plan.razorpay_plan_id;
      if (!providerPlanId) {
        return json(
          { error: `That plan is not open for subscription in ${currency} yet.` },
          409,
        );
      }

      // One live subscription per user. Without this, two tabs produce two
      // mandates and the user is charged twice for the same thing.
      //
      // 'created' counts too, for a bounded window: that row is a checkout the
      // user may be halfway through authorising, and authorising two is exactly
      // the double-charge we are preventing. The window expires so an abandoned
      // checkout does not lock someone out of buying — no cleanup job needed.
      const CHECKOUT_WINDOW_MS = 20 * 60 * 1000;
      const { data: live } = await supabase
        .from("subscriptions").select("id, tier, status, created_at")
        .eq("user_id", user.id)
        .in("status", ["active", "pending", "created"])
        .order("created_at", { ascending: false });

      const existing = (live ?? []).find((s: { status: string; created_at: string }) =>
        s.status !== "created" ||
        Date.now() - new Date(s.created_at).getTime() < CHECKOUT_WINDOW_MS
      );
      if (existing) {
        return json({
          error: existing.status === "created"
            ? "You have a checkout in progress. Finish or close it, then try again."
            : `You already have an active ${existing.tier} subscription. `
              + `Cancel it before starting a new one.`,
        }, 409);
      }

      const rzpRes = await fetch("https://api.razorpay.com/v1/subscriptions", {
        method: "POST",
        headers: { Authorization: RZP_AUTH, "Content-Type": "application/json" },
        body: JSON.stringify({
          plan_id: providerPlanId,
          total_count: TOTAL_COUNT[plan.billing_interval as string] ?? 12,
          customer_notify: 1,
          // Echoed back on every webhook, which is how a renewal two years from
          // now is still attributable to this account.
          notes: { user_id: user.id, sku: plan.sku },
        }),
      });
      const rzp = await rzpRes.json().catch(() => ({}));
      if (!rzpRes.ok || !rzp?.id) {
        return json({ error: rzp?.error?.description ?? "Could not start the subscription." }, 502);
      }

      await supabase.from("payment_orders").insert({
        user_id: user.id, sku: plan.sku, kind: "subscription",
        provider_subscription_id: rzp.id, amount_paise: amount, currency, status: "created",
      });
      await supabase.from("subscriptions").insert({
        user_id: user.id, sku: plan.sku, tier: plan.tier,
        provider_subscription_id: rzp.id, status: "created",
      });

      return json({
        kind: "subscription",
        keyId: RZP_KEY_ID,
        subscriptionId: rzp.id,
        title: plan.title,
        currency,
        // Minor units of `currency`. The name is inherited from the INR-only
        // version and kept deliberately: the web app in production reads
        // `amountPaise`, and renaming it would have broken every checkout in the
        // window between deploying this function and deploying the web app.
        amountPaise: amount,
        // Only the app opens this; the web app has the SDK in the page already.
        url: hosted
          ? payUrl({
            key: RZP_KEY_ID,
            sub: rzp.id,
            amount: String(amount),
            currency,
            title: plan.title,
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
        amount, currency, receipt,
        notes: { user_id: user.id, sku: plan.sku },
      }),
    });
    const rzp = await rzpRes.json().catch(() => ({}));
    if (!rzpRes.ok || !rzp?.id) {
      return json({ error: rzp?.error?.description ?? "Could not start the payment." }, 502);
    }

    await supabase.from("payment_orders").insert({
      user_id: user.id, sku: plan.sku, kind: "one_time",
      provider_order_id: rzp.id, amount_paise: amount, currency, status: "created",
    });

    return json({
      kind: "one_time",
      keyId: RZP_KEY_ID,
      orderId: rzp.id,
      title: plan.title,
      currency,
      amountPaise: amount,
      url: hosted
        ? payUrl({
          key: RZP_KEY_ID,
          order: rzp.id,
          amount: String(amount),
          currency,
          title: plan.title,
        })
        : null,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
