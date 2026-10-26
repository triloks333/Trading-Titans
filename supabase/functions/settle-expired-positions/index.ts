import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Settlement price comes from the authoritative NSE bhavcopy synced daily
// (nse_fo_bhavcopy.settle_price), NOT live broker quotes. Pushes are NOT sent
// here: inserting the notification row fires the `notifications` AFTER INSERT
// trigger, which sends the FCM push centrally (see push-notification fn).

const INDEX_MAP: Record<string, string> = {
  NSEI: "NIFTY", NSEBANK: "BANKNIFTY", BANKNIFTY: "BANKNIFTY", NSEFIN: "FINNIFTY",
  FINNIFTY: "FINNIFTY", NIFTY: "NIFTY", SENSEX: "SENSEX", BANKEX: "BANKEX",
};

function computeIntrinsicValue(optionType: string, strike: number, spot: number): number {
  if (optionType === "CE") return Math.max(0, spot - strike);
  if (optionType === "PE") return Math.max(0, strike - spot);
  return 0;
}

// deno-lint-ignore no-explicit-any
async function getSettlementPrice(supabase: any, pos: any): Promise<number | null> {
  const raw = String(pos.symbol ?? "").toUpperCase().trim();
  let u = raw.startsWith("^") ? raw.slice(1) : raw;
  u = u.split(" ")[0].split("-")[0].split("_")[0];
  const underlying = INDEX_MAP[u] ?? u;
  const expiry = pos.expiry_date;
  if (!underlying || !expiry) return null;

  // Maximum allowable lookback: 5 calendar days before expiry (handles 3-day weekends / holidays).
  // A price from weeks or months ago MUST NEVER be used as a settlement price.
  const expiryDate = new Date(expiry);
  const minDate = new Date(expiryDate.getTime() - 5 * 86400000).toISOString().split("T")[0];

  // 1. Primary: Search nse_fo_bhavcopy for matching futures/underlying near expiry date.
  // Handles both legacy format (option_type="XX") and modern format (strike_price=0, option_type="" or "FUT").
  const { data, error } = await supabase.from("nse_fo_bhavcopy")
    .select("settle_price, close_price, trading_date, expiry_date")
    .eq("symbol", underlying)
    .or("strike_price.eq.0,option_type.eq.XX,option_type.eq.,option_type.eq.FUT")
    .gte("trading_date", minDate)
    .lte("trading_date", expiry)
    .order("trading_date", { ascending: false })
    .order("expiry_date", { ascending: true })
    .limit(1);

  if (!error && data && data.length > 0) {
    const px = Number(data[0].settle_price ?? data[0].close_price);
    if (Number.isFinite(px) && px > 0) {
      console.log(`Found authoritative bhavcopy settlement price for ${underlying} (${data[0].trading_date}): ${px}`);
      return px;
    }
  }

  // 2. Secondary fallback: check quotes_cache for fresh underlying spot price
  const { data: cacheRow } = await supabase
    .from("quotes_cache")
    .select("price, updated_at")
    .in("symbol", [underlying, `^${underlying}`, "^NSEI", "^NSEBANK"])
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (cacheRow && Number(cacheRow.price) > 0) {
    const updatedAt = cacheRow.updated_at ? new Date(cacheRow.updated_at).getTime() : 0;
    const expiryMidnight = new Date(`${expiry}T23:59:59+05:30`).getTime();
    const expiryStart = new Date(`${expiry}T00:00:00+05:30`).getTime() - (2 * 86400000);
    if (updatedAt >= expiryStart && updatedAt <= expiryMidnight + 86400000) {
      const cachePx = Number(cacheRow.price);
      console.log(`Using fresh quotes_cache fallback for ${underlying} settlement: ${cachePx}`);
      return cachePx;
    }
  }

  console.error(`No fresh settlement price found for ${underlying} near expiry ${expiry} (Bhavcopy and quotes_cache both stale/missing). Position settlement postponed.`);
  return null;
}

serve(async (_req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);
  try {
    const today = new Date().toISOString().split("T")[0];
    const { data: expiredPositions, error: fetchError } = await supabase
      .from("fo_positions").select("*").lte("expiry_date", today).eq("is_settled", false);
    if (fetchError) throw fetchError;
    if (!expiredPositions || expiredPositions.length === 0) {
      return new Response(JSON.stringify({ success: true, settled: 0, message: "No expired positions to settle." }), { headers: { "Content-Type": "application/json" } });
    }
    let settledCount = 0; let skipped = 0;
    for (const pos of expiredPositions) {
      if (String(pos.expiry_date) === "PERPETUAL") { skipped++; continue; }
      const settlementPrice = await getSettlementPrice(supabase, pos);
      if (settlementPrice === null) { skipped++; continue; }
      const totalUnits = Math.abs(pos.net_qty) * pos.lot_size;
      const { data: profile, error: profileError } = await supabase.from("profiles").select("wallet_balance, total_realized_pnl").eq("id", pos.user_id).single();
      if (profileError || !profile) { skipped++; continue; }
      let settlementPnl = 0; let walletCredit = 0; let walletDebit = 0; let notifTitle = ""; let notifBody = "";
      if (pos.instrument_type === "OPTION") {
        const iv = computeIntrinsicValue(pos.option_type, Number(pos.strike_price), settlementPrice);
        if (pos.net_qty > 0) { settlementPnl = (iv - Number(pos.avg_entry_price)) * totalUnits; walletCredit = iv * totalUnits; }
        else { walletCredit = Number(pos.margin_blocked); const payout = iv * totalUnits; walletDebit = payout; settlementPnl = Number(pos.avg_entry_price) * totalUnits - payout; }
        const itm = iv > 0;
        notifTitle = itm ? "Option Exercised (ITM)" : "Option Expired (OTM)";
        notifBody = `${pos.symbol} expired ${itm ? "ITM" : "worthless (OTM)"}. Settlement P&L: ${settlementPnl.toFixed(2)}.`;
      } else {
        settlementPnl = (pos.net_qty > 0) ? (settlementPrice - Number(pos.avg_entry_price)) * totalUnits : (Number(pos.avg_entry_price) - settlementPrice) * totalUnits;
        walletCredit = Number(pos.margin_blocked) + (settlementPnl >= 0 ? settlementPnl : 0);
        if (settlementPnl < 0) walletDebit = Math.abs(settlementPnl);
        notifTitle = "Futures Expired";
        notifBody = `${pos.symbol} expired and settled at ${settlementPrice}. Settlement P&L: ${settlementPnl.toFixed(2)}. Margin released to your wallet.`;
      }

      // Circuit Breaker: Halt settlement if an extreme anomaly / glitch is detected
      // (e.g. entry price <= 1.0 with intrinsic >= 50.0, or payout > 100x entry cost yielding > 50,000 INR)
      const costBasis = Number(pos.avg_entry_price) * totalUnits;
      const isExtremeGain = (pos.net_qty > 0 && settlementPnl > 50000 && (settlementPnl / Math.max(1, costBasis)) > 100);
      const isExtremeIntrinsic = (pos.instrument_type === "OPTION" && Number(pos.avg_entry_price) <= 1.0 && computeIntrinsicValue(pos.option_type, Number(pos.strike_price), settlementPrice) >= 50.0);

      if (isExtremeGain || isExtremeIntrinsic) {
        console.error(`CIRCUIT BREAKER TRIGGERED: User ${pos.user_id}, Position ${pos.id}, symbol ${pos.symbol}, entry ${pos.avg_entry_price}, settle ${settlementPrice}, PnL ${settlementPnl}. Holding for admin review.`);
        await supabase.from("notifications").insert({
          user_id: pos.user_id,
          title: "Settlement Held for Audit Review",
          body: `Position ${pos.symbol} settlement resulted in an extreme pricing variance (${settlementPnl > 0 ? "+" : ""}${settlementPnl.toFixed(2)}). Settlement has been put on hold for security audit.`,
          is_read: false,
          action_type: "audit_hold",
        });
        skipped++;
        continue;
      }
      const newWallet = Number(profile.wallet_balance) + walletCredit - walletDebit;
      const newRealized = Number(profile.total_realized_pnl) + settlementPnl;
      const { error: upProfile } = await supabase.from("profiles").update({ wallet_balance: newWallet, total_realized_pnl: newRealized }).eq("id", pos.user_id);
      if (upProfile) { skipped++; continue; }
      const { error: upPos } = await supabase.from("fo_positions").update({ is_settled: true, settlement_price: settlementPrice, realized_pnl: settlementPnl, settled_at: new Date().toISOString() }).eq("id", pos.id).eq("is_settled", false);
      if (upPos) { continue; }
      await supabase.from("realized_pnl_log").insert({ user_id: pos.user_id, position_id: pos.id, pnl_amount: settlementPnl, pnl_type: "expiry_settlement" });
      // Insert notification -> AFTER INSERT trigger sends the FCM push centrally.
      await supabase.from("notifications").insert({ user_id: pos.user_id, title: notifTitle, body: notifBody, is_read: false, action_type: "expiry" });
      settledCount++;
    }
    return new Response(JSON.stringify({ success: true, settled: settledCount, skipped }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("Settlement crashed:", err);
    return new Response(JSON.stringify({ success: false, error: String(err) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
