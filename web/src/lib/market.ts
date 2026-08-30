import { supabase, functionsBase, functionHeaders } from './supabase'
import { DEFAULT_CHARGE_RATES, type ChargeConfig } from './charges'
import { activityKey, type TodayActivity } from './positions'
import type { Candle, HistoryResponse, Quote } from './types'

/*
 * Market data. Two sources, deliberately:
 *
 *  - quotes_cache (a Postgres table) for prices. It is refreshed server-side by
 *    the refresh-quotes cron, so reading it is a single fast query through
 *    PostgREST, which sends proper CORS headers.
 *  - the market-history edge function for candles, because history is too large
 *    to cache per symbol and the function proxies Yahoo/CoinGecko for us. Calling
 *    those providers from the browser directly is impossible: they send no CORS
 *    headers, and they need a User-Agent that browsers forbid scripts from
 *    setting.
 */

/**
 * Market Pulse strip. `symbol` must match quotes_cache exactly — the indices are
 * stored without spaces (`NIFTY`, `BANKNIFTY`), so the pretty name is carried
 * separately rather than guessed from the key.
 */
export const PULSE = [
  { symbol: 'NIFTY', label: 'Nifty 50' },
  { symbol: 'SENSEX', label: 'Sensex' },
  { symbol: 'BANKNIFTY', label: 'Bank Nifty' },
  { symbol: 'BTC', label: 'Bitcoin' },
  { symbol: 'ETH', label: 'Ethereum' },
  { symbol: 'SOL', label: 'Solana' },
] as const

export const PULSE_SYMBOLS = PULSE.map((p) => p.symbol)

export async function fetchQuotes(symbols: string[]): Promise<Quote[]> {
  if (symbols.length === 0) return []
  const { data, error } = await supabase
    .from('quotes_cache')
    .select('*')
    .in('symbol', symbols)
  if (error) throw error
  return (data ?? []) as unknown as Quote[]
}

/** Everything currently in the quote cache — the browsable instrument list. */
export async function fetchAllQuotes(): Promise<Quote[]> {
  const { data, error } = await supabase
    .from('quotes_cache')
    .select('*')
    .order('symbol')
  if (error) throw error
  return (data ?? []) as unknown as Quote[]
}

/**
 * Chart timeframes, each pairing a candle interval with the range it should span.
 *
 * The range used to be hard-coded to `1mo` for every interval, which produced
 * charts that were not wrong so much as useless: a weekly candle over one month is
 * four bars, and a daily candle over one month is twenty-two. Each entry below is
 * chosen so the chart holds a readable number of candles — roughly 60 to 400 — and
 * so the pair is one Yahoo actually serves. Yahoo caps intraday history (about 60
 * days at 5m and 15m, ~730 days at 1h), so the ranges here stay inside those
 * limits; asking for more returns an empty series rather than an error, which is
 * exactly the silent-empty-chart failure this replaces.
 */
export interface Timeframe {
  id: string
  label: string
  interval: string
  range: string
}

const YAHOO_TIMEFRAMES: Timeframe[] = [
  { id: '1D', label: '1D', interval: '5m', range: '1d' },
  { id: '1W', label: '1W', interval: '15m', range: '5d' },
  { id: '1M', label: '1M', interval: '1h', range: '1mo' },
  { id: '3M', label: '3M', interval: '1d', range: '3mo' },
  { id: '1Y', label: '1Y', interval: '1d', range: '1y' },
  { id: '5Y', label: '5Y', interval: '1wk', range: '5y' },
]

/*
 * Crypto stops at one year, and that is a real provider limit rather than a
 * choice: CoinGecko's public OHLC endpoint serves a fixed set of day counts of
 * which 365 is the largest, so a 5-year button could only ever have shown an
 * error. Offering it and failing is worse than not offering it.
 */
const CRYPTO_TIMEFRAMES: Timeframe[] = YAHOO_TIMEFRAMES.filter((t) => t.id !== '5Y')

export function timeframesFor(market: string): Timeframe[] {
  return market === 'crypto' ? CRYPTO_TIMEFRAMES : YAHOO_TIMEFRAMES
}

export const DEFAULT_TIMEFRAME = '3M'

export async function fetchCandles(
  symbol: string,
  market: string,
  timeframeId: string,
): Promise<Candle[]> {
  const available = timeframesFor(market)
  const tf = available.find((t) => t.id === timeframeId) ?? available[available.length - 2]
  const url =
    `${functionsBase}/market-history` +
    `?symbol=${encodeURIComponent(symbol)}` +
    `&market=${encodeURIComponent(market)}` +
    `&range=${encodeURIComponent(tf.range)}` +
    `&interval=${encodeURIComponent(tf.interval)}` +
    // Without this the function discards `range` whenever an interval is present,
    // so 3M and 1Y both returned a year of daily candles — two buttons, one chart.
    `&strict=1`

  const res = await fetch(url, { headers: functionHeaders })
  if (!res.ok) throw new Error(`History unavailable (${res.status})`)
  const body = (await res.json()) as HistoryResponse
  return body.candles ?? []
}

// ── Instrument search ────────────────────────────────────────────────────────

export type SearchMarket = 'all' | 'stock' | 'us_stock' | 'crypto'

export interface SearchHit {
  symbol: string
  name: string
  market: string
  instrumentType: 'EQUITY' | 'FUTURE' | 'OPTION'
  expiryDate: string | null
  strikePrice: number | null
  optionType: string | null
  /** Contract size. 1 for cash; the real lot for a future or an option. */
  lotSize: number
  /** Live price, when the symbol happens to be in the quote cache. */
  price?: number
  changePct?: number
}

const isDerivative = (h: SearchHit) => h.instrumentType !== 'EQUITY'

/**
 * Search the whole tradeable universe.
 *
 * The previous implementation searched `quotes_cache`, which holds about 60 rows
 * — the symbols someone currently holds, watches or has a pending order on, plus
 * a hard-coded popular list. Everything else in the market was unfindable, so
 * "search" could not reach 80,002 tradeable instruments including every future
 * and option. This goes through the market-search function, which queries the
 * `instruments` table and filters on `tradeable`, so expired F&O is excluded at
 * source by the same flag the daily sweep maintains.
 *
 * The quote cache is still consulted, for two things it alone provides: live
 * prices, and the index symbols (NIFTY, BANKNIFTY, SENSEX) which are not rows in
 * `instruments` at all and would otherwise be missing from search results.
 */
export async function searchInstruments(
  query: string,
  market: SearchMarket = 'all',
): Promise<SearchHit[]> {
  const q = query.trim()
  if (q.length < 2) return []

  const markets: Exclude<SearchMarket, 'all'>[] =
    market === 'all' ? ['stock', 'us_stock', 'crypto'] : [market]

  // In parallel: the instrument search per market, plus one cache lookup.
  const [cached, ...perMarket] = await Promise.all([
    supabase
      .from('quotes_cache')
      .select('*')
      .or(`symbol.ilike.%${q}%,name.ilike.%${q}%`)
      .limit(25),
    ...markets.map((m) => searchOneMarket(q, m)),
  ])

  const hits = perMarket.flat()

  // Cache rows first: they carry a live price, and they are the only source of the
  // index symbols. Deduplicated below, so a symbol present in both keeps the
  // priced version.
  const cacheHits: SearchHit[] = ((cached.data ?? []) as unknown as Quote[])
    .filter((qq) => market === 'all' || (qq.market ?? 'stock') === market)
    .map((qq) => ({
      symbol: qq.symbol,
      name: qq.name?.trim() || qq.symbol,
      market: qq.market ?? 'stock',
      instrumentType: 'EQUITY' as const,
      expiryDate: null,
      strikePrice: null,
      optionType: null,
      lotSize: 1,
      price: qq.price,
      changePct: qq.change_pct ?? undefined,
    }))

  const seen = new Set<string>()
  const merged: SearchHit[] = []
  for (const h of [...cacheHits, ...hits]) {
    const k = `${h.symbol.toUpperCase()}\u001f${h.market}\u001f${h.instrumentType}\u001f${h.expiryDate ?? ''}\u001f${h.strikePrice ?? ''}\u001f${h.optionType ?? ''}`
    if (seen.has(k)) continue
    seen.add(k)
    merged.push(h)
  }

  // Cash before derivatives: someone typing a bare ticker wants the share, and a
  // liquid underlying can otherwise bury it under hundreds of option strikes.
  return merged.sort((a, b) => Number(isDerivative(a)) - Number(isDerivative(b)))
}

async function searchOneMarket(
  q: string,
  market: Exclude<SearchMarket, 'all'>,
): Promise<SearchHit[]> {
  try {
    const url =
      `${functionsBase}/market-search` +
      `?q=${encodeURIComponent(q)}&market=${encodeURIComponent(market)}`
    const res = await fetch(url, { headers: functionHeaders })
    if (!res.ok) return []
    const body = await res.json()
    // The function answers with a bare array; an object here means an error shape.
    if (!Array.isArray(body)) return []
    return body.map((raw) => {
      const r = raw as Record<string, unknown>
      const type = String(r.instrument_type ?? 'EQUITY').toUpperCase()
      return {
        symbol: String(r.display_symbol ?? r.symbol ?? ''),
        name: String(r.name ?? r.symbol ?? ''),
        market: String(r.market ?? market),
        instrumentType:
          type === 'FUTURE' || type === 'OPTION' ? (type as 'FUTURE' | 'OPTION') : 'EQUITY',
        expiryDate: r.expiry_date ? String(r.expiry_date) : null,
        strikePrice: r.strike_price != null ? Number(r.strike_price) : null,
        optionType: r.option_type ? String(r.option_type) : null,
        // Lot size is load-bearing, not decoration: an F&O order is placed in
        // units, so a wrong lot means a position many times the intended size.
        lotSize: Number(r.lot_size) > 0 ? Number(r.lot_size) : 1,
      }
    })
  } catch {
    return []
  }
}

const MARKET_LABELS: Record<string, string> = {
  stock: 'NSE / BSE',
  us_stock: 'US market',
  crypto: 'Crypto',
}

/**
 * Secondary line for a symbol.
 *
 * Falls back to the market rather than the symbol: quotes_cache has no company
 * name for many instruments, and echoing "AARTIIND" under "AARTIIND" is worse
 * than saying nothing.
 */
export function labelFor(q: Quote): string {
  const pulse = PULSE.find((p) => p.symbol === q.symbol)
  if (pulse) return pulse.label

  const name = q.name?.trim()
  if (name && name.toUpperCase() !== q.symbol.toUpperCase()) return name

  return MARKET_LABELS[q.market ?? 'stock'] ?? 'Market'
}

/**
 * The live charge rate card, newest `effective_from` first.
 *
 * Falls back to the stale defaults the mobile app also carries, so if this query
 * ever fails both clients degrade to the same numbers rather than to different
 * ones. The id is returned because orders store `charge_config_id`, which is what
 * keeps a historical trade reconcilable after the rates change.
 */
export async function fetchChargeConfig(): Promise<{
  id: string | null
  config: ChargeConfig
}> {
  const { data, error } = await supabase
    .from('charge_configurations')
    .select('id, config')
    .order('effective_from', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error || !data) return { id: null, config: DEFAULT_CHARGE_RATES }
  const row = data as { id: string | null; config: ChargeConfig | null }
  return { id: row.id ?? null, config: row.config ?? DEFAULT_CHARGE_RATES }
}

/**
 * USD -> INR, for folding US positions into a rupee portfolio total.
 *
 * Uses the `market=fx` branch of market-quote, which exists precisely for this
 * and is the same rate source (`USDINR=X` via Yahoo) that the order engine
 * records on a US fill. Fetching it in the browser directly is not an option:
 * Yahoo sends no CORS headers and requires a User-Agent scripts may not set.
 *
 * Returns 0 on failure rather than a guessed constant, so callers can choose to
 * omit a blended total instead of showing a wrong one. The engine's own fallback
 * constant is deliberately not copied here — a stale rupee figure on screen is
 * worse than an honest omission, whereas the engine has no such choice because
 * it must price the fill.
 */
export async function fetchUsdInr(): Promise<number> {
  try {
    const res = await fetch(`${functionsBase}/market-quote?market=fx`, {
      headers: functionHeaders,
    })
    if (!res.ok) return 0
    const body = (await res.json()) as { price?: number; fx_rate?: number }
    const rate = body.fx_rate ?? body.price ?? 0
    return typeof rate === 'number' && rate > 0 ? rate : 0
  } catch {
    return 0
  }
}

/**
 * Executed orders since local midnight, aggregated per symbol+market.
 *
 * Feeds the day-P&L formula in lib/positions.ts. Mirrors the window
 * `SupabaseService.getHoldings` uses on mobile, and subtracts each order's own
 * charges from its realized P&L so a closed position's figure is net — the
 * canonical definition settled with the mobile app.
 */
export async function fetchTodayActivity(): Promise<Map<string, TodayActivity>> {
  const now = new Date()
  const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const { data } = await supabase
    .from('orders')
    .select('symbol, market, quantity, price, side, realized_pnl, total_charges')
    .eq('status', 'executed')
    .gte('executed_at', midnight.toISOString())

  const out = new Map<string, TodayActivity>()
  for (const raw of data ?? []) {
    const r = raw as {
      symbol: string
      market: string | null
      quantity: number
      price: number | null
      side: string
      realized_pnl: number | null
      total_charges: number | null
    }
    const k = activityKey(r.symbol, r.market ?? 'stock')
    const cur =
      out.get(k) ?? { bought: 0, soldQty: 0, cashIn: 0, cashOut: 0, realizedNet: 0 }
    const qty = Number(r.quantity) || 0
    const px = Number(r.price) || 0
    if (r.side === 'buy') {
      cur.bought += qty
      cur.cashIn += qty * px
    } else if (r.side === 'sell') {
      cur.soldQty += qty
      cur.cashOut += qty * px
    }
    cur.realizedNet += (Number(r.realized_pnl) || 0) - (Number(r.total_charges) || 0)
    out.set(k, cur)
  }
  return out
}
