import type { Market, Timeframe } from './types'

/*
 * What a user picks, versus what the chart buckets by.
 *
 * These are two different things and conflating them is why an earlier chart had
 * two buttons that drew the same picture. A user wants to express a SPAN — "show
 * me three months" — while the chart needs a BAR SIZE to bucket live ticks into,
 * and the vendor needs both.
 *
 * So a period pairs the two. The ranges below are lifted from `web/src/lib/market.ts`,
 * which worked this out first and documented why: each pair is chosen to hold
 * roughly 60 to 400 bars, and to stay inside Yahoo's intraday history caps (about
 * 60 days at 5m and 15m, ~730 days at 1h). Asking for more returns an empty series
 * rather than an error, which is the silent-empty-chart failure this avoids.
 *
 * This file replaces that copy and the `RANGE_FOR` table that used to sit in
 * data/history.ts, so the mapping now exists once for both clients.
 */

export type PeriodId = '1m' | '5m' | '15m' | '30m' | '1h' | '1D' | '1W'

export interface ChartPeriod {
  id: PeriodId
  label: string
  /** Bar size. Also the bucket a live tick folds into. */
  interval: Timeframe
  /** Span to request from the history feed. */
  range: string
}

/*
 * EVERY BUTTON IS A BAR SIZE. NONE OF THEM IS A SPAN.
 *
 * The previous row mixed the two — `1m 5m 10m 1h` named bar sizes while
 * `1D 1W 1M 3M 1Y 5Y` named spans — and that is what users reported as "the
 * timeframes don't work". They were right, and not because any bar size was
 * wrong:
 *
 *   `1D` drew 5-minute bars over one day.  `5m` drew 5-minute bars over five days.
 *   `1M` drew hourly bars over one month.  `1h` drew hourly bars over three.
 *
 * Tap between either pair and the candles are the same size; only the span moves.
 * In a row that opens with `1m 5m`, every button reads as a bar size, so the ones
 * that silently changed something else looked broken. A "no two buttons draw the
 * same picture" check passed the whole time, because the spans did differ — it was
 * measuring the wrong thing.
 *
 * So the row is now one idea, the way Zerodha, Groww and TradingView all do it: a
 * bar size, with a span chosen per bar size to land in the 200-500 range that
 * reads well and stays inside the vendor's intraday caps. Bar counts below are
 * measured against the live function, not estimated.
 */
const ALL: ChartPeriod[] = [
  { id: '1m', label: '1m', interval: '1m', range: '1d' },    // 361 bars
  { id: '5m', label: '5m', interval: '5m', range: '5d' },    // 364
  { id: '15m', label: '15m', interval: '15m', range: '10d' }, // 248
  { id: '30m', label: '30m', interval: '30m', range: '1mo' }, // 270
  { id: '1h', label: '1h', interval: '1h', range: '3mo' },   // 452
  { id: '1D', label: '1D', interval: '1d', range: '1y' },    // ~250
  { id: '1W', label: '1W', interval: '1w', range: '5y' },    // ~260
]

/**
 * Crypto now gets the same seven, which it could not before.
 *
 * The old crypto list was spans only because CoinGecko's `/ohlc` ignores the
 * interval entirely and picks granularity from the day count — a "1m" request came
 * back in 30-minute bars. Crypto history is served from CoinDCX instead now, the
 * same venue `market-quote` already reads the live price from, so a 1-minute chip
 * draws genuine 1-minute bars and the last candle no longer disagrees with the
 * price beside it.
 */
export function periodsFor(_market: Market): ChartPeriod[] {
  return ALL
}

/** Daily bars over a year: the one view every market and symbol has history for. */
export const DEFAULT_PERIOD: PeriodId = '1D'

/**
 * The period to use for [id] in [market], falling back rather than throwing.
 *
 * Crypto offers fewer periods than equities, so a selection made on a stock can be
 * invalid after switching instrument. Requesting something the provider will not
 * serve returns an empty chart with no explanation, so fall back to the default.
 */
export function periodFor(market: Market, id: string): ChartPeriod {
  const available = periodsFor(market)
  return (
    available.find((p) => p.id === id) ??
    available.find((p) => p.id === DEFAULT_PERIOD) ??
    available[available.length - 1]!
  )
}
