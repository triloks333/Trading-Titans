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
  const { data, error } = await supabase.from("nse_fo_bhavcopy")
    .select("settle_price, close_price, trading_date, expiry_date")
    .eq("symbol", underlying).eq("option_type", "XX").lte("trading_date", expiry)
    .order("trading_date", { ascending: false }).order("expiry_date", { ascending: true }).limit(1);
  if (error || !data || data.length === 0) { console.error(`No bhavcopy settle price for ${underlying} (expiry ${expiry}).`); return null; }
  const px = Number(data[0].settle_price ?? data[0].close_price);
  return Number.isFinite(px) && px > 0 ? px : null;
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
