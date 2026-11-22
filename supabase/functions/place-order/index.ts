import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { COMMODITY_MARKET, US_MARKET } from "../_shared/us_market.ts";
// Shared session window: the old inline copy closed at 15:15, so orders placed in
// the last 15 minutes of the session were routed to pending instead of filling.
import { isStockOpen } from "../_shared/market_hours.ts";
import { blackScholes, calculateFuturePrice, getDaysToExpiry } from "../_shared/fo_pricing.ts";

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
    if (qty > 10000000) return json({ error: "Quantity exceeds maximum allowable order size (10,000,000)" }, 400);
    if (!["EQUITY", "FUTURE", "OPTION"].includes(instrumentType)) return json({ error: "invalid instrumentType" }, 400);
    if (!["stock", "crypto", US_MARKET, COMMODITY_MARKET, "pakistan_stock", "italy_stock"].includes(market)) return json({ error: "invalid market" }, 400);
    // There is no international derivatives support: no contract master, no lot sizes.
    if ((market === US_MARKET || market === COMMODITY_MARKET || market === "pakistan_stock" || market === "italy_stock") && instrumentType !== "EQUITY") {
      return json({ error: `${market} derivatives are not supported yet` }, 400);
    }
    if (!isMarket && (!Number.isFinite(limitPrice) || limitPrice <= 0)) return json({ error: "limit price must be > 0" }, 400);
    if (instrumentType === "OPTION") {
      if (optionType !== "CE" && optionType !== "PE") return json({ error: "optionType must be CE or PE" }, 400);
      if (!Number.isFinite(Number(strikePrice)) || Number(strikePrice) <= 0) return json({ error: "strikePrice required" }, 400);
      if (!expiryDate) return json({ error: "expiryDate required" }, 400);
    }
    if (instrumentType === "FUTURE" && !expiryDate) return json({ error: "expiryDate required" }, 400);

    // --- Validate exit orders against real positions ---
    if (isExitOrder) {
      if (instrumentType === "EQUITY") {
        const { data: held } = await supabase
          .from("holdings")
          .select("quantity")
          .eq("user_id", userId)
          .eq("symbol", symbol)
          .eq("market", market)
          .maybeSingle();
        if (!held || Number(held.quantity) === 0) {
          return json({ error: `No open position in ${symbol} to exit` }, 400);
        }
        const openQty = Number(held.quantity);
        const maxExitQty = Math.abs(openQty);
        if (qty > maxExitQty + 1e-6) {
          return json({ error: `Exit quantity (${qty}) exceeds your open position size of ${maxExitQty}` }, 400);
        }
        if (openQty > 0 && side !== "sell") {
          return json({ error: "Cannot buy to exit a long position; side must be sell" }, 400);
        }
        if (openQty < 0 && side !== "buy") {
          return json({ error: "Cannot sell to exit a short position; side must be buy" }, 400);
        }
      } else {
        const { data: foPos } = await supabase
          .from("fo_positions")
          .select("net_qty, lot_size")
          .eq("user_id", userId)
          .eq("symbol", symbol)
          .eq("instrument_type", instrumentType)
          .eq("option_type", optionType ?? "")
          .eq("strike_price", strikePrice ?? 0)
          .eq("expiry_date", expiryDate ?? "")
          .eq("is_settled", false)
          .maybeSingle();
        if (!foPos || Number(foPos.net_qty) === 0) {
          return json({ error: `No open derivative position in ${symbol} to exit` }, 400);
        }
        const netLots = Number(foPos.net_qty);
        const lotSize = (Number(foPos.lot_size) > 0) ? Number(foPos.lot_size) : 1;
        const maxExitLots = Math.abs(netLots);
        const orderLots = Math.trunc(qty / lotSize);
        if (orderLots > maxExitLots) {
          return json({ error: `Exit quantity (${orderLots} lots) exceeds open position of ${maxExitLots} lots` }, 400);
        }
        if (netLots > 0 && side !== "sell") {
          return json({ error: "Cannot buy to exit a long position; side must be sell" }, 400);
        }
        if (netLots < 0 && side !== "buy") {
          return json({ error: "Cannot sell to exit a short position; side must be buy" }, 400);
        }
      }
    }

    // --- F&O plan allowance -------------------------------------------------
    // Opening F&O orders are metered per calendar month (IST): free 3, Pro 25,
    // Titan unlimited. The numbers live in public.plan_limit(); this only asks.
    // Exit orders are never metered or blocked, so nobody is trapped in a position.
    // Off entirely while app_flags.monetization_enabled is false (user_limit
    // returns null then). A metering failure fails OPEN: a database hiccup must
    // not stop people trading.
    let foUsageId: number | null = null;
    if (!isExitOrder && (instrumentType === "FUTURE" || instrumentType === "OPTION")) {
      try {
        const { data: use, error: useErr } = await supabase.rpc("consume_feature", { p_user: userId, p_feature: "fo_trades_month", p_ref: null });
        if (!useErr && use && use.allowed === false) {
          const next = use.tier === "pro" ? "Titan for unlimited" : "Pro for 25 a month or Titan for unlimited";
          return json({
            error: `You've used all ${use.limit} F&O trades on your ${String(use.tier).toUpperCase()} plan this month. Upgrade to ${next}. You can still exit your open positions.`,
            code: "plan_limit",
            feature: "fo_trades_month",
            used: use.used,
            limit: use.limit,
            tier: use.tier,
          }, 403);
        }
        if (use && typeof use.usage_id === "number") foUsageId = use.usage_id;
      } catch (_) { /* fail open */ }
    }
    const refundFo = async () => {
      if (foUsageId == null) return;
      try { await supabase.rpc("refund_feature", { p_usage_id: foUsageId }); } catch (_) { /* ignore */ }
      foUsageId = null;
    };

    // --- Warm a trusted price into quotes_cache so the engine can price immediately ---
    // US tickers are already bare (AAPL), so extractUnderlying would only ever
    // damage them — it truncates at the first digit and splits on "-".
    const underlyingKey = (market === "crypto" || market === US_MARKET || market === COMMODITY_MARKET || market === "pakistan_stock" || market === "italy_stock") ? symbol.toUpperCase() : extractUnderlying(symbol);
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

    // Stored price on the pending row:
    // - For an OPTION: the contract price is the option premium (NOT the underlying stock price).
    //   If limitPrice is passed (client LTP or requested limit), use it. Otherwise, compute from refPrice via Black-Scholes.
    // - For a FUTURE: futurePrice with cost of carry (or limitPrice).
    // - For EQUITY: limitPrice (limit) or refPrice (market).
    let storedPrice = 0;
    if (instrumentType === "OPTION") {
      if (limitPrice > 0) {
        storedPrice = limitPrice;
      } else if (refPrice > 0 && strikePrice && optionType && expiryDate) {
        const days = getDaysToExpiry(expiryDate);
        storedPrice = blackScholes(refPrice, strikePrice, days / 365, optionType as "CE" | "PE");
      }
    } else if (instrumentType === "FUTURE") {
      if (limitPrice > 0) {
        storedPrice = limitPrice;
      } else if (refPrice > 0 && expiryDate) {
        storedPrice = calculateFuturePrice(refPrice, getDaysToExpiry(expiryDate));
      } else if (refPrice > 0) {
        storedPrice = refPrice;
      }
    } else {
      storedPrice = isMarket ? (refPrice > 0 ? refPrice : limitPrice) : limitPrice;
    }

    if (!Number.isFinite(storedPrice) || storedPrice <= 0) {
      await refundFo();
      return json({ error: "Could not determine a price; quote unavailable. Please try again." }, 422);
    }

    // --- Wallet balance pre-check for non-exit orders ---
    if (!isExitOrder) {
      const { data: prof } = await supabase
        .from("profiles")
        .select("wallet_balance")
        .eq("id", userId)
        .maybeSingle();
      const currentWallet = Number(prof?.wallet_balance ?? 0);

      let requiredCapital = 0;
      if (instrumentType === "OPTION") {
        if (side === "buy") {
          // Option BUY: buyer pays 100% of the option premium. Risk is capped at premium.
          requiredCapital = storedPrice * qty;
        } else {
          // Option SELL (Writing): requires initial margin (~15%).
          requiredCapital = storedPrice * qty * 0.15;
        }
      } else if (instrumentType === "FUTURE") {
        // Futures: 15% initial margin.
        requiredCapital = storedPrice * qty * 0.15;
      } else {
        // Equity: 100% full value (or short intraday).
        requiredCapital = storedPrice * qty;
      }

      if (currentWallet < requiredCapital) {
        await refundFo();
        return json({
          error: `Insufficient wallet balance. Required: ₹${requiredCapital.toFixed(2)}, Available: ₹${currentWallet.toFixed(2)}`,
        }, 400);
      }
    }

    const nseContractDate = new Date().toISOString().split("T")[0];
    const name = instrumentType === "OPTION" ? `${symbol} ${expiryDate} ${strikePrice} ${optionType}` : symbol;

    // --- Insert the validated pending order. The server is the only writer of money. ---
    // A pending US row carries USD in `price`/`total`; the engine overwrites both
    // with INR at fill and keeps the USD figure in native_price. Stamping
    // native_currency now means the app can tell "this is a dollar number" at
    // both stages instead of guessing from the market alone.
    const nativeCols = (market === US_MARKET || market === COMMODITY_MARKET)
      ? { native_price: storedPrice, native_currency: "USD" }
      : market === "pakistan_stock"
      ? { native_price: storedPrice, native_currency: "PKR" }
      : market === "italy_stock"
      ? { native_price: storedPrice, native_currency: "EUR" }
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
    if (ins.error || !ins.data) { await refundFo(); return json({ error: ins.error?.message ?? "Could not place order" }, 500); }
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
    // The engine turned it down: it was never a trade, so give the slot back.
    if (resultStatus === "rejected" || resultStatus === "failed") await refundFo();

    // Pending-notification parity with the client placeOrder.
    if (resultStatus === "pending") {
      try {
        // International prices are quoted in their native currency.
        const ccy = (market === US_MARKET || market === COMMODITY_MARKET) ? "$" : market === "pakistan_stock" ? "Rs " : market === "italy_stock" ? "€" : "\u20b9";
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
