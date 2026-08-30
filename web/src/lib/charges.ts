/*
 * Transaction charges: brokerage, STT, stamp duty, exchange fees, GST.
 *
 * Deliberately dependency-free — no Supabase client, no Vite `import.meta.env`.
 * That is what lets charges.check.ts run this under plain `node` and assert it
 * against charges the live engine actually computed. Fetching the rate card lives
 * in lib/market.ts instead, with the rest of the data layer.
 *
 * This is a PREVIEW. The authoritative figure is computed server-side and written
 * onto the order row at fill; nothing here moves money. The point of mirroring it
 * is that a user should see, before confirming, the number that will actually be
 * debited.
 *
 * Which implementation this mirrors matters, because the codebase has two that
 * disagree. `calculateTransactionCharges` in app/lib/services/supabase_service.dart
 * honours an `isIntraday` flag; `computeCharges` in
 * supabase/functions/execute-pending-orders does not — it always applies delivery
 * rates and always charges DP on an equity sell. Every order the web places goes
 * in as PENDING and is priced by that engine, so the engine is what the wallet
 * actually pays. This file mirrors the engine.
 *
 * (Worth flagging separately: the mobile order screen defaults its Intraday
 * toggle ON and previews with intraday rates, so its preview understates the real
 * charge on an equity buy — intraday STT is 0 on the buy side against delivery's
 * 0.1%. That is a mobile bug, not something to reproduce here.)
 */

export interface ChargeConfig {
  [key: string]: number | string | undefined
}

export interface Charges {
  brokerage: number
  stampDuty: number
  stt: number
  exchange: number
  clearing: number
  sebi: number
  turnover: number
  dp: number
  otherFee: number
  gst: number
  /** STT + exchange + GST + clearing + SEBI + turnover, as stored in orders.tax_charges. */
  taxCharges: number
  /** What actually leaves the wallet on top of the trade value. */
  totalCharges: number
}

export type InstrumentType = 'EQUITY' | 'FUTURE' | 'OPTION'
export type Side = 'buy' | 'sell'

/**
 * Fallback rates, used only if `charge_configurations` cannot be read.
 *
 * Deliberately the same stale 2025 numbers the mobile app carries, rather than
 * today's: if the two clients ever fall back, they should at least fall back to
 * the same place. The live row supersedes all of this (2026 rates: options STT
 * 0.15%, futures 0.05%).
 */
export const DEFAULT_CHARGE_RATES: Record<string, number> = {
  equity_brokerage_rate: 0.0005,
  equity_brokerage_max: 20.0,
  fo_brokerage_flat: 20.0,
  stamp_duty_delivery: 0.00015,
  stamp_duty_intraday: 0.00003,
  stamp_duty_options: 0.00003,
  stamp_duty_futures: 0.00002,
  stt_delivery: 0.001,
  stt_intraday_sell: 0.00025,
  stt_options_sell: 0.000625,
  stt_futures_sell: 0.000125,
  exchange_delivery: 0.0000322,
  exchange_options: 0.00053,
  exchange_futures: 0.000019,
  gst_rate: 0.18,
  clearing_fee_rate: 0.000002,
  sebi_regulatory_fee_rate: 0.000001,
  turnover_tax_rate: 0.000001,
  dp_charges_flat: 13.5,
  other_broker_fee_flat: 0.0,
}

/**
 * Round to paise, half away from zero.
 *
 * Not `Math.round`, which rounds half towards +Infinity and would therefore
 * disagree with Dart's `roundToDouble()` on a negative half. Charges are never
 * negative today, so this makes no difference to any current figure — it is here
 * so the two implementations cannot drift if one ever is.
 */
const round2 = (n: number): number => {
  const scaled = n * 100
  const r = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled)
  return r / 100
}

/**
 * Charges for one order leg.
 *
 * Returns all-zero for anything that is not an Indian stock-market trade, which
 * is what the engine does: `market === 'stock'` is the only branch that computes
 * charges, so crypto and US equity trade free. Reproducing that here rather than
 * charging optimistically means the preview cannot promise a fee the engine will
 * not take, or vice versa.
 */
export function calculateCharges({
  instrumentType,
  side,
  quantity,
  price,
  market = 'stock',
  config,
}: {
  instrumentType: InstrumentType
  side: Side
  quantity: number
  price: number
  market?: string
  config?: ChargeConfig | null
}): Charges {
  const zero: Charges = {
    brokerage: 0, stampDuty: 0, stt: 0, exchange: 0, clearing: 0,
    sebi: 0, turnover: 0, dp: 0, otherFee: 0, gst: 0,
    taxCharges: 0, totalCharges: 0,
  }

  if (market !== 'stock') return zero
  if (!Number.isFinite(quantity) || !Number.isFinite(price)) return zero
  if (quantity <= 0 || price <= 0) return zero

  const g = (key: string, fallback: number): number => {
    const v = config?.[key]
    const n = typeof v === 'string' ? Number(v) : v
    return typeof n === 'number' && Number.isFinite(n) ? n : fallback
  }

  const totalValue = price * quantity

  let brokerage = 0
  let stampDuty = 0
  let stt = 0
  let exchange = 0

  if (instrumentType === 'EQUITY') {
    brokerage = Math.min(
      totalValue * g('equity_brokerage_rate', 0.0005),
      g('equity_brokerage_max', 20),
    )
    if (side === 'buy') stampDuty = totalValue * g('stamp_duty_delivery', 0.00015)
    // Delivery STT applies to BOTH sides, unlike intraday which is sell-only.
    stt = totalValue * g('stt_delivery', 0.001)
    exchange = totalValue * g('exchange_delivery', 0.0000322)
  } else if (instrumentType === 'FUTURE') {
    brokerage = g('fo_brokerage_flat', 20)
    if (side === 'buy') stampDuty = totalValue * g('stamp_duty_futures', 0.00002)
    if (side === 'sell') stt = totalValue * g('stt_futures_sell', 0.000125)
    exchange = totalValue * g('exchange_futures', 0.000019)
  } else {
    brokerage = g('fo_brokerage_flat', 20)
    if (side === 'buy') stampDuty = totalValue * g('stamp_duty_options', 0.00003)
    // Options STT is charged on the PREMIUM, which is what `price` already is for
    // an option leg — not on the notional.
    if (side === 'sell') stt = totalValue * g('stt_options_sell', 0.000625)
    exchange = totalValue * g('exchange_options', 0.00053)
  }

  const clearing = totalValue * g('clearing_fee_rate', 0.000002)
  const sebi = totalValue * g('sebi_regulatory_fee_rate', 0.000001)
  const turnover = totalValue * g('turnover_tax_rate', 0.000001)
  const dp = instrumentType === 'EQUITY' && side === 'sell' ? g('dp_charges_flat', 13.5) : 0
  const otherFee = g('other_broker_fee_flat', 0)

  // GST is on the SERVICE fees only. STT, stamp duty and DP are taxes/duties in
  // their own right and are not part of the GST base.
  const gst = (brokerage + exchange + clearing + sebi + turnover + otherFee) * g('gst_rate', 0.18)

  const taxCharges = stt + exchange + gst + clearing + sebi + turnover
  const totalCharges = brokerage + stampDuty + taxCharges + dp + otherFee

  return {
    brokerage: round2(brokerage),
    stampDuty: round2(stampDuty),
    stt: round2(stt),
    exchange: round2(exchange),
    clearing: round2(clearing),
    sebi: round2(sebi),
    turnover: round2(turnover),
    dp: round2(dp),
    otherFee: round2(otherFee),
    gst: round2(gst),
    taxCharges: round2(taxCharges),
    totalCharges: round2(totalCharges),
  }
}
