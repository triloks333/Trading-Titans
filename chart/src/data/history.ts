import { functionsBase, getJson } from './client'
import { historySymbol } from '../core/symbols'
import type { ChartPeriod } from '../core/periods'
import type { Candle, Market, Timeframe } from '../core/types'

/*
 * Historical bars, from the `market-history` edge function.
 *
 * That function proxies Yahoo Finance (equities, indices) and CoinGecko (crypto).
 * Nothing is stored on our side yet — `tick_data` exists in the schema with zero
 * rows — so this is the vendor's history, not ours, and it will not agree to the
 * paisa with `quotes_cache`. That seam is known and deliberate for now: the body of
 * the chart is the vendor's, the live edge is ours. Once we record our own series,
 * only this module changes.
 */

/** What `market-history` returns. `t` is MILLISECONDS. */
interface HistoryResponse {
  symbol: string
  points: { t: number; v: number }[]
  candles: { t: number; o: number; h: number; l: number; c: number }[]
}

/**
 * Our interval keys translated to the upstream ones.
 *
 * Necessary because we pass `strict=1`. In that mode `market-history` forwards
 * `interval` to Yahoo verbatim rather than putting it through its own
 * `intervalMap`, so the mapping becomes ours to get right. Every key below is
 * already a valid Yahoo interval except the weekly one: Yahoo wants `1wk`, and
 * `1w` comes back as a 400 that surfaces as a 500 from the function.
 *
 * Verified against the live function: `^BSESN` at `1w` fails with
 * "YF history failed: 400", at `1wk` returns 262 weekly bars.
 *
 * The alternative was dropping `strict` and letting the function pick, but that
 * also discards `range` — which is how a "3M" and a "1Y" button previously drew
 * identical charts. Owning both parameters is the point of strict mode.
 */
const YF_INTERVAL: Record<Timeframe, string> = {
  '1m': '1m',
  '5m': '5m',
  '15m': '15m',
  '30m': '30m',
  '1h': '1h',
  '1d': '1d',
  '1w': '1wk',
}

/** Fetches bars for [symbol] over [period]. */
export async function fetchHistory(
  symbol: string,
  market: Market,
  period: ChartPeriod,
): Promise<Candle[]> {
  const q = new URLSearchParams({
    symbol: historySymbol(symbol, market),
    market,
    interval: YF_INTERVAL[period.interval],
    range: period.range,
    strict: '1',
  })
  const data = await getJson<HistoryResponse>(`${functionsBase}/market-history?${q}`)

  // Bars arrive at the interval asked for. Where a venue cannot serve that size
  // natively, `market-history` fetches a finer one and rolls it up before
  // answering — CoinDCX has no 5m, Yahoo has no 10m. That belongs on the server
  // because it is knowledge about a venue, and a chart should not have to hold a
  // table of which provider can serve which bar size.
  return (data.candles ?? [])
    .filter((c) => [c.o, c.h, c.l, c.c].every((n) => Number.isFinite(n) && n > 0))
    // Milliseconds to seconds, once, here. See the note on `Seconds` in types.ts.
    .map((c) => ({
      time: Math.floor(c.t / 1000),
      open: c.o,
      high: c.h,
      low: c.l,
      close: c.c,
    }))
    .sort((a, b) => a.time - b.time)
}
