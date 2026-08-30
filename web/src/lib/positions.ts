import { currencyFor, type Currency } from './currency.ts'
import { daysToExpiry, futurePrice, optionPremium } from './optionPricing.ts'
import type { Quote } from './types.ts'

// Dependency-free on purpose (no Supabase client, no Vite `import.meta.env`), so
// positions.check.ts can run this whole model under plain `node`. The query that
// feeds `today` lives in lib/market.ts with the rest of the data layer.

/*
 * The portfolio's numbers, in one place.
 *
 * Previously the Portfolio page did this inline and got four things wrong, each
 * of which showed a user a figure that was not their position:
 *
 *  1. `filter(h => h.quantity > 0)` silently dropped every SHORT. There are 12
 *     live short holdings in production; on the web they simply did not exist,
 *     so neither did the capital they have blocked.
 *  2. A US position mixed currencies: `avg_price` is rupees (the engine converts
 *     at fill) while `quotes_cache.price` for us_stock is dollars, so
 *     `value - invested` subtracted rupees from dollars and produced a P&L out by
 *     the exchange rate.
 *  3. `fo_positions` was never read at all — 3 open F&O positions invisible.
 *  4. No day P&L, and P&L was gross of charges.
 *
 * Definitions settled with the mobile app: **net of charges is canonical**, and
 * "current value" for a position that blocks margin is margin + P&L rather than
 * notional, so that `wallet + positions` reconciles.
 */

export type PositionKind = 'EQUITY' | 'CRYPTO' | 'US' | 'FUTURE' | 'OPTION'

export interface Position {
  key: string
  symbol: string
  /** What to show a human: an option renders as "NIFTY 24500 CE". */
  label: string
  market: string
  kind: PositionKind
  /** Signed. Negative is short. For F&O this is lots, not units. */
  quantity: number
  /** Units behind the position: quantity x lot size. Equals quantity off F&O. */
  units: number
  isShort: boolean

  /** The instrument's own currency — dollars for a US equity. */
  currency: Currency
  displayAvgPrice: number
  displayLtp: number
  /** Capital committed, in `currency`. Margin for a short or a future. */
  displayInvested: number
  displayValue: number
  displayPnl: number
  displayPnlPct: number
  /** Today's move, in `currency`. Zero when it cannot be established. */
  displayDayPnl: number

  /** Rupee figures, for portfolio-wide totals. Zero if a US rate was needed and unavailable. */
  investedInr: number
  valueInr: number
  pnlInr: number
  dayPnlInr: number
  /** True when the rupee figures above required an FX rate that could not be fetched. */
  inrUnavailable: boolean

  expiryDate: string | null
  createdAt: string | null
}

interface HoldingRow {
  id: string
  symbol: string
  name: string | null
  market: string | null
  quantity: number
  avg_price: number
  native_avg_price: number | null
  native_currency: string | null
  instrument_type: string | null
  created_at: string | null
}

interface FoRow {
  id: string
  symbol: string
  instrument_type: string
  option_type: string | null
  strike_price: number | null
  expiry_date: string | null
  lot_size: number
  net_qty: number
  avg_entry_price: number
  margin_blocked: number
  created_at: string | null
}

/** Today's executed orders, aggregated per symbol, for the day-P&L formula. */
export interface TodayActivity {
  bought: number
  soldQty: number
  cashIn: number
  cashOut: number
  /** Realized P&L NET of the charges on those same orders. */
  realizedNet: number
}

export const activityKey = (symbol: string, market: string) => `${symbol}\u001f${market}`
const key = activityKey

/**
 * Today's P&L for a cash position, mirroring the mobile formula.
 *
 * The naive `(ltp - previousClose) * qty` is only right for a position held
 * untouched from yesterday's close. Once you have traded the symbol today it
 * over- or under-counts, because part of the move happened before you owned the
 * shares. Marking the opening quantity to the previous close and treating today's
 * buys and sells as cash flows handles both.
 */
export function cashDayPnl(
  quantity: number,
  ltp: number,
  previousClose: number,
  act: TodayActivity | undefined,
): number {
  if (previousClose <= 0 || ltp <= 0) return 0
  const bought = act?.bought ?? 0
  const sold = act?.soldQty ?? 0
  const cashIn = act?.cashIn ?? 0
  const cashOut = act?.cashOut ?? 0

  if (quantity > 0) {
    const openingQty = Math.max(0, quantity - bought + sold)
    const openingValue = openingQty * previousClose
    return quantity * ltp + cashOut - (openingValue + cashIn)
  }
  if (quantity < 0) {
    const openingAbs = Math.max(0, Math.abs(quantity) - sold + bought)
    const openingValue = openingAbs * previousClose
    return openingValue + cashOut - (Math.abs(quantity) * ltp + cashIn)
  }
  // Flat: whatever was banked today, already net of charges.
  return act?.realizedNet ?? 0
}

export interface BuildPositionsInput {
  holdings: HoldingRow[]
  foPositions: FoRow[]
  quotes: Quote[]
  today: Map<string, TodayActivity>
  /** USD -> INR. Zero means unavailable; US rupee figures are then flagged, not guessed. */
  usdInr: number
}

export function buildPositions(input: BuildPositionsInput): Position[] {
  const { holdings, foPositions, quotes, today, usdInr } = input

  const quoteFor = (symbol: string, market: string): Quote | undefined =>
    quotes.find((q) => q.symbol === symbol && (q.market ?? 'stock') === market) ??
    quotes.find((q) => q.symbol === symbol)

  const out: Position[] = []

  // ── Cash positions: equity, crypto and US equity ──────────────────────────
  for (const h of holdings) {
    const qty = Number(h.quantity) || 0
    // `!== 0`, not `> 0`: a short is a position.
    if (qty === 0) continue

    const market = h.market ?? 'stock'
    const currency = currencyFor(market)
    const isUs = currency === 'USD'
    const q = quoteFor(h.symbol, market)

    // Everything below is computed in ONE currency — the instrument's own — so a
    // dollar price is never subtracted from a rupee cost basis.
    const avgInr = Number(h.avg_price) || 0
    const displayAvgPrice = isUs ? Number(h.native_avg_price) || avgInr : avgInr
    const displayLtp = Number(q?.price) || displayAvgPrice
    const prevClose = Number(q?.previous_close) || 0

    const absQty = Math.abs(qty)
    const displayInvested = displayAvgPrice * absQty
    // Signed quantity makes this correct in both directions: a short gains as the
    // price falls, because (ltp - avg) and qty are both negative.
    const displayPnl = (displayLtp - displayAvgPrice) * qty
    // Margin + P&L rather than notional, so wallet + positions reconciles for a
    // short exactly as it does on mobile.
    const displayValue = displayInvested + displayPnl
    const act = today.get(key(h.symbol, market))
    const displayDayPnl = cashDayPnl(qty, displayLtp, prevClose, act)

    const rate = isUs ? usdInr : 1
    const inrUnavailable = isUs && !(usdInr > 0)
    const toInr = (v: number) => (inrUnavailable ? 0 : v * rate)

    out.push({
      key: `H:${h.id}`,
      symbol: h.symbol,
      label: h.name?.trim() || h.symbol,
      market,
      kind: isUs ? 'US' : market === 'crypto' ? 'CRYPTO' : 'EQUITY',
      quantity: qty,
      units: qty,
      isShort: qty < 0,
      currency,
      displayAvgPrice,
      displayLtp,
      displayInvested,
      displayValue,
      displayPnl,
      displayPnlPct: displayInvested > 0 ? (displayPnl / displayInvested) * 100 : 0,
      displayDayPnl,
      // The rupee cost basis is read from `avg_price` rather than converted from
      // the dollar one: that is the number of rupees the wallet actually paid, at
      // the rate on the day of the fill, not today's rate.
      investedInr: isUs ? avgInr * absQty : displayInvested,
      valueInr: isUs ? toInr(displayValue) : displayValue,
      pnlInr: isUs ? toInr(displayValue) - avgInr * absQty : displayPnl,
      dayPnlInr: isUs ? toInr(displayDayPnl) : displayDayPnl,
      inrUnavailable,
      expiryDate: null,
      createdAt: h.created_at,
    })
  }

  // ── F&O positions ─────────────────────────────────────────────────────────
  for (const f of foPositions) {
    const lots = Number(f.net_qty) || 0
    if (lots === 0) continue

    const lotSize = Number(f.lot_size) || 1
    const units = lots * lotSize
    const absUnits = Math.abs(units)
    const isOption = f.instrument_type === 'OPTION'
    const avg = Number(f.avg_entry_price) || 0
    const margin = Number(f.margin_blocked) || 0

    // The underlying's spot, then the same model the engine uses to turn a spot
    // into a premium or a futures price.
    const spot = Number(quoteFor(underlyingOf(f.symbol), 'stock')?.price) || 0
    const dte = daysToExpiry(f.expiry_date)
    const ltp = isOption
      ? optionPremium({
          optionType: f.option_type || 'CE',
          spot,
          strike: Number(f.strike_price) || 0,
          daysToExpiry: dte,
        })
      : futurePrice({ spot, daysToExpiry: dte })

    const displayPnl = (ltp - avg) * units
    // A long option is paid for in full, so its premium IS the capital committed.
    // A short option or any future only blocks margin.
    const displayInvested = isOption && lots > 0 ? avg * absUnits : margin
    const displayValue = displayInvested + displayPnl

    out.push({
      key: `F:${f.id}`,
      symbol: f.symbol,
      label: isOption
        ? `${f.symbol} ${Number(f.strike_price ?? 0).toFixed(0)} ${f.option_type ?? ''}`.trim()
        : `${f.symbol} FUT`,
      market: 'stock',
      kind: isOption ? 'OPTION' : 'FUTURE',
      quantity: lots,
      units,
      isShort: lots < 0,
      currency: 'INR',
      displayAvgPrice: avg,
      displayLtp: ltp,
      displayInvested,
      displayValue,
      displayPnl,
      displayPnlPct: displayInvested > 0 ? (displayPnl / displayInvested) * 100 : 0,
      // F&O day P&L would need yesterday's modelled premium, which needs
      // yesterday's spot. Reported as zero rather than guessed; the position's
      // total P&L above is exact.
      displayDayPnl: 0,
      investedInr: displayInvested,
      valueInr: displayValue,
      pnlInr: displayPnl,
      dayPnlInr: 0,
      inrUnavailable: false,
      expiryDate: f.expiry_date,
      createdAt: f.created_at,
    })
  }

  return out.sort((a, b) => b.displayValue - a.displayValue)
}

/**
 * Underlying behind an F&O symbol, for the spot lookup.
 *
 * Mirrors `extractUnderlying` in the engine, including the index aliases. Kept
 * narrow on purpose: it only has to find a `quotes_cache` key.
 */
export function underlyingOf(symbolRaw: string): string {
  let s = (symbolRaw || '').toUpperCase().trim()
  if (s.startsWith('NSE:') || s.startsWith('BSE:')) s = s.slice(4)
  if (s.endsWith('-EQ')) s = s.slice(0, -3)
  if (s.includes(' ')) s = s.split(' ')[0]
  if (s.includes('-')) s = s.split('-')[0]
  if (s === '^NSEI' || s === 'NSEI' || s === 'NIFTY50') return 'NIFTY'
  if (s === '^NSEBANK' || s === 'NSEBANK') return 'BANKNIFTY'
  if (s === '^BSESN' || s === 'SENSEX') return 'SENSEX'
  const digit = s.search(/\d/)
  if (digit > 0) s = s.slice(0, digit)
  return s
}

export interface PortfolioTotals {
  investedInr: number
  valueInr: number
  pnlInr: number
  pnlPct: number
  dayPnlInr: number
  /** True if any position could not be expressed in rupees, so totals exclude it. */
  partial: boolean
}

export function totalsOf(positions: Position[]): PortfolioTotals {
  let investedInr = 0
  let valueInr = 0
  let pnlInr = 0
  let dayPnlInr = 0
  let partial = false
  for (const p of positions) {
    if (p.inrUnavailable) {
      partial = true
      continue
    }
    investedInr += p.investedInr
    valueInr += p.valueInr
    pnlInr += p.pnlInr
    dayPnlInr += p.dayPnlInr
  }
  return {
    investedInr,
    valueInr,
    pnlInr,
    pnlPct: investedInr > 0 ? (pnlInr / investedInr) * 100 : 0,
    dayPnlInr,
    partial,
  }
}
