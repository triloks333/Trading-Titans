import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { US_MARKET } from "../_shared/us_market.ts";
// Shared session window: the old inline copy closed at 15:15, so orders placed in
// the last 15 minutes of the session were routed to pending instead of filling.
import { isStockOpen } from "../_shared/market_hours.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
};

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }

function extractUnderlying(symbolRaw: string): string {
  let s = (symbolRaw || "").toUpperCase().trim();
  if (s.startsWith("NSE:")) s = s.slice(4);
  if (s.startsWith("BSE:")) s = s.slice(4);
  s = s.replace("-EQ-", "-");
  if (s.endsWith("-EQ")) s = s.slice(0, -3);
  if (s.includes(" ")) s = s.split(" ")[0];
  if (s.includes("-")) s = s.split("-")[0];
  if (s === "^NSEI" || s === "NSEI" || s === "NIFTY50") return "NIFTY";
  if (s === "^NSEBANK" || s === "NSEBANK") return "BANKNIFTY";
  if (s === "^BSESN" || s === "SENSEX") return "SENSEX";
  const m = s.match(/\d/); if (m && (m.index ?? 0) > 0) s = s.slice(0, m.index);
  return s;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";

    // --- Authenticate: derive the user from their JWT. NEVER trust a body user_id. ---
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing Authorization" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Invalid token" }, 401);
    const userId = userData.user.id;

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // --- Rate limit order placement per user (fail-open). ---
    try {
      const { data: allowed } = await supabase.rpc("check_rate_limit", { p_key: `place-order:${userId}`, p_max: 30, p_window_seconds: 60 });
      if (allowed === false) return json({ error: "Too many orders in a short time. Please wait a moment and try again." }, 429);
    } catch (_) { /* fail open */ }

    const body = await req.json().catch(() => ({}));

    let symbol = typeof body.symbol === "string" ? body.symbol.trim() : "";
    let market = (typeof body.market === "string" && body.market.trim()) ? body.market.trim().toLowerCase() : "stock";
    let side = typeof body.side === "string" ? body.side.trim().toLowerCase() : "";
    let instrumentType = (typeof body.instrumentType === "string" && body.instrumentType.trim()) ? body.instrumentType.trim().toUpperCase() : "EQUITY";
    const isMarket = body.isMarket !== false; // default true
    const isExitOrder = body.isExitOrder === true;
    const qty = Number(body.quantity);
    const limitPrice = body.price != null ? Number(body.price) : 0;
    const optionType = typeof body.optionType === "string" ? body.optionType.trim().toUpperCase() : null;
    const strikePrice = body.strikePrice != null ? Number(body.strikePrice) : null;
    const expiryDate = (typeof body.expiryDate === "string" && body.expiryDate.trim()) ? body.expiryDate.trim() : null;

    // --- Validate request shape ---
    if (!symbol) return json({ error: "symbol required" }, 400);
    if (side !== "buy" && side !== "sell") return json({ error: "side must be buy or sell" }, 400);
    if (!Number.isFinite(qty) || qty <= 0) return json({ error: "quantity must be > 0" }, 400);
    if (!["EQUITY", "FUTURE", "OPTION"].includes(instrumentType)) return json({ error: "invalid instrumentType" }, 400);
    if (!["stock", "crypto", US_MARKET].includes(market)) return json({ error: "invalid market" }, 400);
    // There is no US derivatives support: no contract master, no lot sizes, and
    // the option pricing model assumes an Indian risk-free rate.
    if (market === US_MARKET && instrumentType !== "EQUITY") {
      return json({ error: "US derivatives are not supported yet" }, 400);
    }
    if (!isMarket && (!Number.isFinite(limitPrice) || limitPrice <= 0)) return json({ error: "limit price must be > 0" }, 400);
    if (instrumentType === "OPTION") {
      if (optionType !== "CE" && optionType !== "PE") return json({ error: "optionType must be CE or PE" }, 400);
      if (!Number.isFinite(Number(strikePrice)) || Number(strikePrice) <= 0) return json({ error: "strikePrice required" }, 400);
      if (!expiryDate) return json({ error: "expiryDate required" }, 400);
    }
    if (instrumentType === "FUTURE" && !expiryDate) return json({ error: "expiryDate required" }, 400);

    // --- Warm a trusted price into quotes_cache so the engine can price immediately ---
    // US tickers are already bare (AAPL), so extractUnderlying would only ever
    // damage them — it truncates at the first digit and splits on "-".
    const underlyingKey = (market === "crypto" || market === US_MARKET) ? symbol.toUpperCase() : extractUnderlying(symbol);
    let refPrice = 0;
    try {
      const qurl = `${SUPABASE_URL}/functions/v1/market-quote?symbol=${encodeURIComponent(underlyingKey)}&market=${encodeURIComponent(market)}`;
      const r = await fetch(qurl, { headers: { Authorization: `Bearer ${ANON}`, apikey: ANON } });
      if (r.ok) {
        const q = await r.json();
        if (q && typeof q.price === "number" && q.price > 0) {
          refPrice = q.price;
          await supabase.from("quotes_cache").upsert([{ symbol: underlyingKey, market, price: q.price, previous_close: q.previous_close ?? null, name: q.name ?? underlyingKey, change: q.change ?? null, change_pct: q.change_pct ?? null, day_low: q.day_low ?? null, day_high: q.day_high ?? null, open: q.open ?? null, source: q.source ?? null, updated_at: new Date().toISOString() }], { onConflict: "symbol,market" });
        }
      }
    } catch (_) { /* ignore */ }

    // Stored price on the pending row: limit -> trigger threshold; market -> informational (engine reprices from cache).
    const storedPrice = isMarket ? (refPrice > 0 ? refPrice : limitPrice) : limitPrice;
    if (!Number.isFinite(storedPrice) || storedPrice <= 0) {
      return json({ error: "Could not determine a price; quote unavailable. Please try again." }, 422);
    }

    const nseContractDate = new Date().toISOString().split("T")[0];
    const name = instrumentType === "OPTION" ? `${symbol} ${expiryDate} ${strikePrice} ${optionType}` : symbol;

    // --- Insert the validated pending order. The server is the only writer of money. ---
    // A pending US row carries USD in `price`/`total`; the engine overwrites both
    // with INR at fill and keeps the USD figure in native_price. Stamping
    // native_currency now means the app can tell "this is a dollar number" at
    // both stages instead of guessing from the market alone.
    const nativeCols = market === US_MARKET
      ? { native_price: storedPrice, native_currency: "USD" }
      : {};

    const ins = await supabase.from("orders").insert({
      user_id: userId, symbol, name, market, side, quantity: qty, price: storedPrice, total: storedPrice * qty, realized_pnl: 0.0, ...nativeCols,
      // The requested limit, kept separate because the engine overwrites `price`
      // with the fill price at execution. NULL for a market order, which has no
      // requested price to preserve.
      limit_price: isMarket ? null : limitPrice,
      status: "pending", order_type: isMarket ? "market" : "limit", instrument_type: instrumentType,
      strike_price: instrumentType === "EQUITY" ? null : strikePrice, option_type: instrumentType === "OPTION" ? optionType : null,
      expiry_date: instrumentType === "EQUITY" ? null : expiryDate, execution_price_source: "SERVER_PLACE_ORDER",
      execution_reference_price: refPrice > 0 ? refPrice : storedPrice, nse_contract_date: nseContractDate, is_exit: isExitOrder,
    }).select().maybeSingle();
    if (ins.error || !ins.data) return json({ error: ins.error?.message ?? "Could not place order" }, 500);
    const orderId = ins.data.id;

    // --- Hand off to the audited execution engine (all money math lives there) ---
    let engineReport: unknown = null;
    try {
      const eurl = `${SUPABASE_URL}/functions/v1/execute-pending-orders?user=${encodeURIComponent(userId)}&commit=1${force ? "&force=1" : ""}`;
      const er = await fetch(eurl, { method: "POST", headers: { Authorization: `Bearer ${ANON}`, apikey: ANON } });
      engineReport = await er.json().catch(() => null);
    } catch (e) { engineReport = { error: e instanceof Error ? e.message : String(e) }; }

    // --- Read back the resulting state of THIS order ---
    let resultStatus = "pending";
    const after = await supabase.from("orders").select("id, status").eq("id", orderId).maybeSingle();
    if (!after.data) resultStatus = "executed"; // FO executed path deletes the pending row and inserts a fresh executed order
    else resultStatus = after.data.status;

    // Pending-notification parity with the client placeOrder.
    if (resultStatus === "pending") {
      try {
        // US prices are quoted in USD, so the notification must not say "₹".
        const ccy = market === US_MARKET ? "$" : "\u20b9";
        // action_type "order_pending" (not "order"): channelFor() in
        // push-notification maps "order" to the ORDER EXECUTED channel, so a
        // pending order was arriving with the executed sound. The app's
        // notifications screen treats both values as tappable order alerts.
        await supabase.from("notifications").insert({ user_id: userId, title: "Order Pending", body: `${side.toUpperCase()} ${market === "crypto" ? qty.toFixed(4) : qty.toFixed(0)} ${symbol} placed at ${ccy}${storedPrice.toFixed(2)}`, is_read: false, action_type: "order_pending", action_data: { symbol, market } });
      } catch (_) { /* ignore */ }
    }

    return json({ ok: true, order_id: orderId, status: resultStatus, engine: engineReport });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
