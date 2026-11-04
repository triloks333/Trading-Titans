import { functionsBase, getJson, restBase } from './client'
import { cacheKeyFor } from '../core/symbols'
import type { Market, Sample } from '../core/types'

/*
 * The live price — the reason for doing any of this.
 *
 * `quotes_cache` is the table `execute-pending-orders` prices fills from and the
 * table `MarketService` reads to render the app. So a chart whose right-hand edge
 * comes from here shows the number a user will actually be filled at. The
 * TradingView embed this replaces drew a different feed entirely, so its candles
 * and our fills could disagree with nothing to explain the gap.
 *
 * `refresh-quotes` rewrites rows on a `* * * * *` cron, and only for symbols in
 * its universe (watchlist, holdings, open F&O, active alerts, pending orders,
 * indices, a popular list) whose market session is open — about 74 symbols. Any
 * symbol outside that set has no row, which is why `market-quote` is the fallback
 * rather than an error.
 */

interface QuoteRow {
  symbol: string
  market: string
  price: number | string
  previous_close: number | string | null
  open: number | string | null
  day_high: number | string | null
  day_low: number | string | null
  name: string | null
  source: string | null
  updated_at: string
}

export interface LiveQuote extends Sample {
  previousClose: number | null
  open: number | null
  dayHigh: number | null
  dayLow: number | null
  name: string | null
  /** Which feed answered, and whether it came from our cache or live. */
  source: string
  /** True when this came from `quotes_cache` — the engine's own price. */
  fromCache: boolean
}

/** Postgres numerics arrive as strings over REST. */
const num = (v: unknown): number | null => {
  if (v === null || v === undefined) return null
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : null
}

/**
 * Reads our own cached price. Returns null when there is no row for this symbol,
 * which is the normal case outside the ~74-symbol refresh universe.
 */
async function fromQuotesCache(symbol: string, market: Market): Promise<LiveQuote | null> {
  const key = cacheKeyFor(symbol, market)
  const q = new URLSearchParams({
    select: 'symbol,market,price,previous_close,open,day_high,day_low,name,source,updated_at',
    symbol: `eq.${key}`,
    market: `eq.${market}`,
    limit: '1',
  })
  const rows = await getJson<QuoteRow[]>(`${restBase}/quotes_cache?${q}`)
  const row = rows[0]
  if (!row) return null

  const price = num(row.price)
  if (price === null || price <= 0) return null

  return {
    // The row's own timestamp, not the clock. A cron pass a minute ago must land
    // in the bar it belongs to, or the live edge jumps ahead of the data.
    time: Math.floor(new Date(row.updated_at).getTime() / 1000),
    price,
    previousClose: num(row.previous_close),
    open: num(row.open),
    dayHigh: num(row.day_high),
    dayLow: num(row.day_low),
    name: row.name,
    source: row.source ?? 'quotes_cache',
    fromCache: true,
  }
}

/** Live fetch, for symbols the refresh job does not cover. Also the stock leg of
 * data/stream.ts, which needs fresher than the cache's once a minute. */
export async function fromMarketQuote(symbol: string, market: Market): Promise<LiveQuote | null> {
  const q = new URLSearchParams({ symbol, market })
  const data = await getJson<Record<string, unknown>>(
    `${functionsBase}/market-quote?${q}`,
  )
  const price = num(data.price)
  if (price === null || price <= 0) return null

  return {
    time: Math.floor(Date.now() / 1000),
    price,
    previousClose: num(data.previous_close),
    open: num(data.open),
    dayHigh: num(data.day_high),
    dayLow: num(data.day_low),
    name: typeof data.name === 'string' ? data.name : null,
    source: typeof data.source === 'string' ? data.source : 'market-quote',
    fromCache: false,
  }
}

/**
 * Our price for [symbol], preferring the cache the engine itself uses.
 *
 * Cache first is not an optimisation, it is correctness: that row is the price a
 * fill would be made at, and a live fetch could return something a few paise
 * different and put the chart out of step with the order book.
 */
export async function fetchLiveQuote(
  symbol: string,
  market: Market,
): Promise<LiveQuote | null> {
  try {
    const cached = await fromQuotesCache(symbol, market)
    if (cached) return cached
  } catch {
    // Fall through to the live fetch: a chart that stops updating is worse than
    // one showing a price from a slightly different instant.
  }
  try {
    return await fromMarketQuote(symbol, market)
  } catch {
    return null
  }
}
