/*
 * The data shapes the chart works in. Deliberately not the shapes any of our
 * endpoints return — those are mapped at the boundary in `src/data`, so exactly
 * one file has to change if a feed changes.
 */

/**
 * Seconds since the epoch, UTC.
 *
 * Not milliseconds. `market-history` returns `t` in milliseconds and
 * lightweight-charts wants seconds, so the division happens once, at the data
 * boundary, and everything past that point is seconds. Mixing the two silently
 * puts every bar in 1970 or 55000 AD, which renders as an empty chart with no
 * error — the exact bug this comment exists to prevent.
 */
export type Seconds = number

/** One OHLC bar. `time` is the bucket START, not the sample time. */
export interface Candle {
  time: Seconds
  open: number
  high: number
  low: number
  close: number
}

/** A single observed price. What `quotes_cache` gives us, one row at a time. */
export interface Sample {
  time: Seconds
  price: number
}

/** Markets, matching the `market` column and every edge function's parameter. */
export type Market = 'stock' | 'us_stock' | 'crypto' | 'commodity'

/**
 * Timeframes the chart offers.
 *
 * These are exactly the keys `_shared/yahoo.ts` accepts in its `intervalMap`, so a
 * timeframe is passed straight through to `market-history` as `interval`. Where a
 * venue cannot serve one natively, `market-history` fetches a finer bar and rolls
 * it up before answering, so the chart never has to know which provider can do
 * what.
 */
export type Timeframe = '1m' | '5m' | '15m' | '30m' | '1h' | '1d' | '1w'

export const TIMEFRAMES: Timeframe[] = ['1m', '5m', '15m', '30m', '1h', '1d', '1w']

/** How the price series is drawn. */
export type SeriesStyle = 'candles' | 'line'

export type ThemeMode = 'light' | 'dark'

/** Which currency to format prices in. The chart never converts, only labels. */
export type Currency = 'INR' | 'USD'
