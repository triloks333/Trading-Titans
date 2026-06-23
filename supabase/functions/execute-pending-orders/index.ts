import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }
function istNow(): Date { return new Date(Date.now() + 5.5 * 3600 * 1000); }
function isStockOpen(): boolean { const i = istNow(); const d = i.getUTCDay(); if (d === 0 || d === 6) return false; const m = i.getUTCHours() * 60 + i.getUTCMinutes(); return m >= 555 && m < 915; }
function isMarketOpen(market: string): boolean { return market === "crypto" ? true : isStockOpen(); }

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

function nCDF(x: number): number { const t = 1 / (1 + 0.2316419 * Math.abs(x)); const d = 0.3989422804 * Math.exp(-x * x / 2); const p = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429)))); return x >= 0 ? 1 - p : p; }
function bs(opt: string, spot: number, strike: number, T: number): number { if (spot <= 0 || strike <= 0) return 0.05; if (T <= 0) return opt === "CE" ? Math.max(0, spot - strike) : Math.max(0, strike - spot); const r = 0.065, sig = 0.25; const d1 = (Math.log(spot / strike) + (r + 0.5 * sig * sig) * T) / (sig * Math.sqrt(T)); const d2 = d1 - sig * Math.sqrt(T); let p; if (opt === "CE") p = spot * nCDF(d1) - strike * Math.exp(-r * T) * nCDF(d2); else p = strike * Math.exp(-r * T) * nCDF(-d2) - spot * nCDF(-d1); return Math.max(0.05, Math.round(p * 100) / 100); }
function optionPremium(opt: string, spot: number, strike: number, days: number): number { return bs(opt, spot, strike, Math.max(0.0001, days) / 365); }
function futurePrice(spot: number, days: number): number { if (spot <= 0 || days <= 0) return spot; return spot * (1 + 0.065 * (days / 365)); }
function daysToExpiry(e: string | null): number | null { if (!e || e === "PERPETUAL") return null; const ms = new Date(e).getTime() - Date.now(); return Number.isNaN(ms) ? null : ms / 86400000; }

function computeCharges(cfg: Record<string, number>, itype: string, side: string, quantity: number, price: number) {
  const g = (k: string, d: number) => (cfg && cfg[k] != null ? Number(cfg[k]) : d);
  const totalValue = price * quantity;
  let brokerage = 0, stampDuty = 0, stt = 0, exchange = 0;
  if (itype === "EQUITY") {
    brokerage = Math.min(totalValue * g("equity_brokerage_rate", 0.0005), g("equity_brokerage_max", 20));
    if (side === "buy") stampDuty = totalValue * g("stamp_duty_delivery", 0.00015);
    stt = totalValue * g("stt_delivery", 0.001);
    exchange = totalValue * g("exchange_delivery", 0.0000322);
  } else if (itype === "FUTURE") {
    brokerage = g("fo_brokerage_flat", 20);
    if (side === "buy") stampDuty = totalValue * g("stamp_duty_futures", 0.00002);
    if (side === "sell") stt = totalValue * g("stt_futures_sell", 0.000125);
    exchange = totalValue * g("exchange_futures", 0.000019);
  } else if (itype === "OPTION") {
    brokerage = g("fo_brokerage_flat", 20);
    if (side === "buy") stampDuty = totalValue * g("stamp_duty_options", 0.00003);
    if (side === "sell") stt = totalValue * g("stt_options_sell", 0.000625);
    exchange = totalValue * g("exchange_options", 0.00053);
  }
  const clearing = totalValue * g("clearing_fee_rate", 0.000002);
  const sebi = totalValue * g("sebi_regulatory_fee_rate", 0.000001);
  const turnover = totalValue * g("turnover_tax_rate", 0.000001);
  const dp = (itype === "EQUITY" && side === "sell") ? g("dp_charges_flat", 13.5) : 0;
  const otherFee = g("other_broker_fee_flat", 0);
  const gst = (brokerage + exchange + clearing + sebi + turnover + otherFee) * g("gst_rate", 0.18);
  const taxCharges = stt + exchange + gst + clearing + sebi + turnover;
  const totalCharges = brokerage + stampDuty + taxCharges + dp + otherFee;
  const r = (n: number) => Math.round(n * 100) / 100;
  return { brokerage: r(brokerage), stamp_duty: r(stampDuty), tax_charges: r(taxCharges), total_charges: r(totalCharges) };
}

// Resolve the contract lot size. Prefer the contract whose expiry matches the
// ORDER's expiry (exact date, then year-month) because an underlying can have
// multiple active expiries with DIFFERENT lot sizes (e.g. HDFCBANK Jun=550,
// Jul=650). Falling back to an arbitrary first row silently produced a wrong
// lot, which made trunc(qty/lot)=0 and dropped the whole position.
async function getLotSize(supabase: any, symbol: string, expiryDate?: string | null): Promise<number> {
  const underlying = extractUnderlying(symbol);
  const { data } = await supabase.from("instruments").select("symbol, expiry_date, lot_size").in("instrument_type", ["OPTION", "FUTURE"]).like("symbol", `NSE:${underlying}%`);
  if (!data || data.length === 0) return 1;
  if (expiryDate) {
    const ed = String(expiryDate);
    const exact = data.find((e: any) => String(e.expiry_date) === ed);
    if (exact) return Number(exact.lot_size) || 1;
    const ym = ed.slice(0, 7);
    const monthMatch = data.find((e: any) => String(e.expiry_date).startsWith(ym));
    if (monthMatch) return Number(monthMatch.lot_size) || 1;
  }
  const clean = symbol.toUpperCase().replace("NSE:", "").replace("-EQ-", "-");
  if (clean.includes("-")) {
    const parts = clean.split("-");
    if (parts.length >= 4) {
      const expiryStr = `${parts[1]}-${parts[2].padStart(2, "0")}-${parts[3].padStart(2, "0")}`;
      const match = data.find((e: any) => String(e.expiry_date).startsWith(expiryStr));
      if (match) return Number(match.lot_size) || 1;
    }
  }
  return Number(data[0].lot_size) || 1;
}

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";
    const commit = url.searchParams.get("commit") === "1";
    const onlyUser = url.searchParams.get("user");
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    const cfgRow = await supabase.from("charge_configurations").select("id, config").order("effective_from", { ascending: false }).limit(1).maybeSingle();
    const chargeConfigId = cfgRow.data?.id ?? null;
    const cfg = (cfgRow.data?.config ?? {}) as Record<string, number>;

    let q = supabase.from("orders").select("*").eq("status", "pending");
    if (onlyUser) q = q.eq("user_id", onlyUser);
    const { data: pending, error } = await q;
    if (error) return json({ error: error.message }, 500);
    if (!pending || pending.length === 0) return json({ pending: 0, executed: 0, report: [] });

    const { data: cacheRows } = await supabase.from("quotes_cache").select("symbol, market, price");
    const priceMap = new Map<string, number>();
    for (const r of (cacheRows ?? [])) priceMap.set(`${r.symbol}\u001f${r.market}`, Number(r.price));

    let executed = 0;
    const report: Record<string, unknown>[] = [];

    for (const o of pending) {
      const market = (o.market || "stock").toLowerCase();
      const itype = o.instrument_type || "EQUITY";
      const side = o.side;
      const quantity = Number(o.quantity);
      const orderType = o.order_type || "market";
      const limit = Number(o.price ?? 0);
      const isExit = o.is_exit === true;
      const userId = o.user_id;
      const isDerivative = itype === "FUTURE" || itype === "OPTION";

      if (!(isMarketOpen(market) || force)) { report.push({ id: o.id, skipped: "market_closed" }); continue; }

      const underlyingKey = market === "crypto" ? String(o.symbol).toUpperCase() : extractUnderlying(o.symbol);
      const spot = priceMap.get(`${underlyingKey}\u001f${market}`);
      if (spot == null) { report.push({ id: o.id, skipped: "no_cached_price" }); continue; }

      let execPrice: number;
      if (itype === "FUTURE") execPrice = futurePrice(spot, daysToExpiry(o.expiry_date) ?? 15);
      else if (itype === "OPTION") execPrice = optionPremium(o.option_type || "CE", spot, Number(o.strike_price ?? 0), daysToExpiry(o.expiry_date) ?? 7);
      else execPrice = spot;

      if (orderType === "limit") {
        if (side === "buy" && execPrice > limit) { report.push({ id: o.id, skipped: "limit_not_reached" }); continue; }
        if (side === "sell" && execPrice < limit) { report.push({ id: o.id, skipped: "limit_not_reached" }); continue; }
      }

      const total = execPrice * quantity;
      const marginPct = isDerivative ? 0.15 : 1.0;
      const marginRequired = total * marginPct;
      const charges = (market === "stock") ? computeCharges(cfg, itype, side, quantity, execPrice) : { brokerage: 0, stamp_duty: 0, tax_charges: 0, total_charges: 0 };
      const totalCharges = charges.total_charges;

      const profRes = await supabase.from("profiles").select("wallet_balance, total_realized_pnl").eq("id", userId).maybeSingle();
      if (!profRes.data) { report.push({ id: o.id, skipped: "no_profile" }); continue; }
      let walletBalance = Number(profRes.data.wallet_balance);
      const totalRealizedPnl = Number(profRes.data.total_realized_pnl ?? 0);

      const claim = async (): Promise<boolean> => {
        if (!commit) return true;
        const c = await supabase.from("orders").update({ status: "executing" }).eq("id", o.id).eq("status", "pending").select();
        return Array.isArray(c.data) && c.data.length > 0;
      };
      const name = o.name || o.symbol;
      let realizedPnl = 0;

      try {
        if (isDerivative) {
          const sign = side === "buy" ? 1 : -1;
          const exRes = await supabase.from("fo_positions").select("*").eq("user_id", userId).eq("symbol", o.symbol).eq("instrument_type", itype).eq("option_type", o.option_type ?? "").eq("strike_price", o.strike_price ?? 0).eq("expiry_date", o.expiry_date ?? "").eq("is_settled", false).maybeSingle();
          const ex = exRes.data;
          // Prefer the lot size the position was opened with; otherwise resolve
          // by the order's expiry (an underlying can have multiple expiries with
          // different lot sizes). Re-deriving blindly broke the close/open math.
          const lotSize = (ex && Number(ex.lot_size) > 0) ? Number(ex.lot_size) : await getLotSize(supabase, o.symbol, o.expiry_date);
          let tradeQtyLots = Math.trunc(quantity / lotSize);
          if (tradeQtyLots < 1) tradeQtyLots = 1; // never silently drop a real order to 0 lots
          const existingQty = ex ? Number(ex.net_qty) : 0;
          const existingAvg = ex ? Number(ex.avg_entry_price) : 0;
          const oldMargin = ex ? Number(ex.margin_blocked) : 0;
          if (isExit && existingQty !== 0 && existingQty * sign < 0) tradeQtyLots = Math.min(Math.abs(tradeQtyLots), Math.abs(existingQty));
          const newNetQty = existingQty + tradeQtyLots * sign;
          let newAvg = 0, walletDebit = 0, walletCredit = 0, marginBlocked = 0;

          if (existingQty === 0 || existingQty * sign > 0) {
            newAvg = existingQty === 0 ? execPrice : ((existingAvg * Math.abs(existingQty)) + (execPrice * tradeQtyLots)) / (Math.abs(existingQty) + tradeQtyLots);
            if (itype === "OPTION" && newNetQty > 0) { marginBlocked = 0; walletDebit = execPrice * quantity; }
            else if (itype === "OPTION" && newNetQty < 0) { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; const delta = marginBlocked - oldMargin; const prem = execPrice * quantity; if (prem >= delta) walletCredit = prem - delta; else walletDebit = delta - prem; }
            else { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; walletDebit = marginBlocked - oldMargin; }
            const requiredCapital = (itype === "OPTION" && newNetQty > 0) ? execPrice * quantity : execPrice * tradeQtyLots * lotSize * 0.15;
            if (!isExit && walletBalance < requiredCapital + totalCharges) { report.push({ id: o.id, skipped: "insufficient_funds" }); continue; }
          } else {
            newAvg = existingAvg;
            const closedQtyLots = Math.abs(tradeQtyLots) > Math.abs(existingQty) ? Math.abs(existingQty) : Math.abs(tradeQtyLots);
            const remainingQtyLots = Math.abs(tradeQtyLots) - closedQtyLots;
            realizedPnl = (existingQty > 0 ? (execPrice - existingAvg) : (existingAvg - execPrice)) * closedQtyLots * lotSize;
            if (newNetQty === 0) {
              marginBlocked = 0;
              if (itype === "OPTION" && existingQty > 0) walletCredit = execPrice * closedQtyLots * lotSize;
              else if (itype === "OPTION" && existingQty < 0) { const ni = oldMargin - (execPrice * closedQtyLots * lotSize); if (ni >= 0) walletCredit = ni; else walletDebit = Math.abs(ni); }
              else { const ni = oldMargin + realizedPnl; if (ni >= 0) walletCredit = ni; else walletDebit = Math.abs(ni); }
            } else if (newNetQty * existingQty > 0) {
              if (itype === "OPTION" && existingQty > 0) { marginBlocked = 0; walletCredit = execPrice * closedQtyLots * lotSize; }
              else if (itype === "OPTION" && existingQty < 0) { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; const rel = oldMargin - marginBlocked; const ni = rel - (execPrice * closedQtyLots * lotSize); if (ni >= 0) walletCredit = ni; else walletDebit = Math.abs(ni); }
              else { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; const rel = oldMargin - marginBlocked; const ni = rel + realizedPnl; if (ni >= 0) walletCredit = ni; else walletDebit = Math.abs(ni); }
            } else {
              let closedNI = 0;
              if (itype === "OPTION" && existingQty > 0) closedNI = execPrice * closedQtyLots * lotSize;
              else if (itype === "OPTION" && existingQty < 0) closedNI = oldMargin - (execPrice * closedQtyLots * lotSize);
              else closedNI = oldMargin + realizedPnl;
              newAvg = execPrice;
              let openD = 0, openC = 0;
              if (itype === "OPTION" && newNetQty > 0) { marginBlocked = 0; openD = execPrice * remainingQtyLots * lotSize; }
              else if (itype === "OPTION" && newNetQty < 0) { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; const prem = execPrice * remainingQtyLots * lotSize; if (prem >= marginBlocked) openC = prem - marginBlocked; else openD = marginBlocked - prem; }
              else { marginBlocked = newAvg * Math.abs(newNetQty) * lotSize * 0.15; openD = marginBlocked; }
              const ni = closedNI + openC - openD; if (ni >= 0) walletCredit = ni; else walletDebit = Math.abs(ni);
            }
          }

          let finalDebit = walletDebit, finalCredit = walletCredit;
          if (totalCharges > 0) { if (walletCredit >= totalCharges) finalCredit = walletCredit - totalCharges; else { finalCredit = 0; finalDebit = walletDebit + (totalCharges - walletCredit); } }
          if (!isExit && walletBalance + finalCredit - finalDebit < 0) { report.push({ id: o.id, skipped: "insufficient_net" }); continue; }

          const positionData = { symbol: o.symbol, instrument_type: itype, option_type: o.option_type ?? "", strike_price: o.strike_price ?? 0, expiry_date: o.expiry_date ?? "", lot_size: lotSize, net_qty: newNetQty, avg_entry_price: newAvg };
          const orderData = { symbol: o.symbol, name, market, side, quantity, price: execPrice, total, realized_pnl: realizedPnl, status: "executed", order_type: orderType, instrument_type: itype, strike_price: o.strike_price ?? 0, option_type: o.option_type ?? "", expiry_date: o.expiry_date ?? "", charge_config_id: chargeConfigId, brokerage: charges.brokerage, stamp_duty: charges.stamp_duty, tax_charges: charges.tax_charges, total_charges: totalCharges };

          if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "FO", newNetQty, finalDebit, finalCredit, marginBlocked }); executed++; continue; }
          if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
          const rpc = await supabase.rpc("place_fo_order_transaction", { p_user_id: userId, p_wallet_debit: finalDebit, p_wallet_credit: finalCredit, p_margin_blocked: marginBlocked, p_margin_released: 0.0, p_position_data: positionData, p_order_data: orderData });
          if (rpc.error) throw new Error(rpc.error.message);
          await supabase.from("orders").delete().eq("id", o.id);
          executed++; report.push({ id: o.id, executed: true, kind: "FO", newNetQty });
          continue;
        }

        const exRes = await supabase.from("holdings").select("*").eq("user_id", userId).eq("symbol", o.symbol).eq("market", market).maybeSingle();
        const ex = exRes.data;
        if (side === "buy") {
          if (!ex) {
            if (!isExit && walletBalance < marginRequired + totalCharges) { report.push({ id: o.id, skipped: "insufficient_funds" }); continue; }
            if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_BUY_NEW" }); executed++; continue; }
            if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
            await supabase.from("profiles").update({ wallet_balance: walletBalance - total - totalCharges }).eq("id", userId);
            await supabase.from("holdings").insert({ user_id: userId, symbol: o.symbol, market, quantity, avg_price: execPrice, name, instrument_type: itype, strike_price: o.strike_price, option_type: o.option_type, expiry_date: o.expiry_date });
          } else {
            const oq = Number(ex.quantity), oa = Number(ex.avg_price);
            if (oq < 0) {
              const coverQty = quantity > -oq ? -oq : quantity;
              const remainingBuyQty = isExit ? 0 : quantity - coverQty;
              if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_COVER" }); executed++; continue; }
              if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
              const releasedMargin = coverQty * oa;
              realizedPnl += (oa - execPrice) * coverQty;
              await supabase.from("profiles").update({ wallet_balance: walletBalance + releasedMargin + realizedPnl - totalCharges, total_realized_pnl: totalRealizedPnl + realizedPnl - totalCharges }).eq("id", userId);
              const newQty = oq + coverQty;
              if (Math.abs(newQty) < 1e-8) await supabase.from("holdings").delete().eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
              else await supabase.from("holdings").update({ quantity: newQty }).eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
              if (remainingBuyQty > 0) {
                const remTotal = remainingBuyQty * execPrice;
                const up = await supabase.from("profiles").select("wallet_balance").eq("id", userId).maybeSingle();
                const upBal = Number(up.data?.wallet_balance ?? 0);
                if (upBal >= remTotal + totalCharges) { await supabase.from("profiles").update({ wallet_balance: upBal - remTotal }).eq("id", userId); await supabase.from("holdings").insert({ user_id: userId, symbol: o.symbol, market, quantity: remainingBuyQty, avg_price: execPrice, name, instrument_type: itype, strike_price: o.strike_price, option_type: o.option_type, expiry_date: o.expiry_date }); }
              }
            } else {
              if (!isExit && walletBalance < total + totalCharges) { report.push({ id: o.id, skipped: "insufficient_funds" }); continue; }
              if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_ADD_LONG" }); executed++; continue; }
              if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
              await supabase.from("profiles").update({ wallet_balance: walletBalance - total - totalCharges }).eq("id", userId);
              const nq = oq + quantity; const na = nq > 0 ? ((oa * oq) + (execPrice * quantity)) / nq : execPrice;
              await supabase.from("holdings").update({ quantity: nq, avg_price: na, name }).eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
            }
          }
        } else {
          if (!ex) {
            if (!isExit && walletBalance < marginRequired + totalCharges) { report.push({ id: o.id, skipped: "insufficient_funds" }); continue; }
            if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_SHORT_NEW" }); executed++; continue; }
            if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
            await supabase.from("profiles").update({ wallet_balance: walletBalance - marginRequired - totalCharges }).eq("id", userId);
            await supabase.from("holdings").insert({ user_id: userId, symbol: o.symbol, market, quantity: -quantity, avg_price: execPrice, name, instrument_type: itype, strike_price: o.strike_price, option_type: o.option_type, expiry_date: o.expiry_date });
          } else {
            const oq = Number(ex.quantity), oa = Number(ex.avg_price);
            if (oq > 0) {
              const sellQty = quantity > oq ? oq : quantity;
              const remainingSellQty = isExit ? 0 : quantity - sellQty;
              realizedPnl += (execPrice - oa) * sellQty;
              if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_SELL_CLOSE", realizedPnl }); executed++; continue; }
              if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
              await supabase.from("profiles").update({ wallet_balance: walletBalance + (sellQty * execPrice) - totalCharges, total_realized_pnl: totalRealizedPnl + realizedPnl - totalCharges }).eq("id", userId);
              const newQty = oq - sellQty;
              if (Math.abs(newQty) < 1e-8) await supabase.from("holdings").delete().eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
              else await supabase.from("holdings").update({ quantity: newQty, avg_price: oa, name }).eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
              if (remainingSellQty > 0) {
                const remTotal = remainingSellQty * execPrice;
                const up = await supabase.from("profiles").select("wallet_balance").eq("id", userId).maybeSingle();
                const upBal = Number(up.data?.wallet_balance ?? 0);
                if (upBal >= remTotal) { await supabase.from("profiles").update({ wallet_balance: upBal - remTotal }).eq("id", userId); await supabase.from("holdings").insert({ user_id: userId, symbol: o.symbol, market, quantity: -remainingSellQty, avg_price: execPrice, name, instrument_type: itype, strike_price: o.strike_price, option_type: o.option_type, expiry_date: o.expiry_date }); }
              }
            } else {
              if (!isExit && walletBalance < marginRequired + totalCharges) { report.push({ id: o.id, skipped: "insufficient_funds" }); continue; }
              if (!commit) { report.push({ id: o.id, wouldExecute: true, kind: "EQ_ADD_SHORT" }); executed++; continue; }
              if (!(await claim())) { report.push({ id: o.id, skipped: "claim_lost" }); continue; }
              await supabase.from("profiles").update({ wallet_balance: walletBalance - marginRequired - totalCharges }).eq("id", userId);
              const nq = oq - quantity; const oqAbs = Math.abs(oq); const na = (oqAbs + quantity) > 0 ? ((oa * oqAbs) + (execPrice * quantity)) / (oqAbs + quantity) : execPrice;
              await supabase.from("holdings").update({ quantity: nq, avg_price: na, name }).eq("user_id", userId).eq("symbol", o.symbol).eq("market", market);
            }
          }
        }

        if (commit) {
          await supabase.from("orders").update({ status: "executed", price: execPrice, total, realized_pnl: realizedPnl, executed_at: new Date().toISOString(), charge_config_id: chargeConfigId, brokerage: charges.brokerage, stamp_duty: charges.stamp_duty, tax_charges: charges.tax_charges, total_charges: totalCharges }).eq("id", o.id);
          executed++; report.push({ id: o.id, executed: true, kind: "EQUITY" });
        }
      } catch (e) {
        if (commit) { await supabase.from("orders").update({ status: "failed" }).eq("id", o.id).eq("status", "executing"); }
        report.push({ id: o.id, error: e instanceof Error ? e.message : String(e) });
      }
    }

    return json({ dryRun: !commit, pending: pending.length, executed, report });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
