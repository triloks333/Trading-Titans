import { cacheKeyFor } from '../core/symbols'
import { fromMarketQuote } from './quote'
import type { Market, Sample } from '../core/types'

/*
 * The live edge, faster than `quotes_cache`.
 *
 * The cache is rewritten once a minute, so a chart fed only from it moves once a
 * minute however often it polls — which is what made the candles look dead. This
 * feeds the open chart from a faster source for its one symbol:
 *
 *   crypto  Binance's public trade stream, every trade as it prints, scaled to
 *           rupees by the ratio between our cached INR price and the first
 *           print. Not CoinDCX's stream, though fills price from CoinDCX: its
 *           socket refuses every browser Origin but its own (checked 2026-11-02),
 *           so neither the WebView nor the web app can open it.
 *   stocks  `market-quote` (live Yahoo, not the cache) every couple of seconds,
 *           backing off while the price is not moving, so a closed market costs
 *           one call every 30s rather than one every 2.5s.
 *
 * These are real observed prices, never interpolated. Fills still come from the
 * cache, so the chart can lead the fill price by up to the cache's age — the
 * trade-off chosen on 2026-11-02 for a chart that moves like a market.
 */

// The market-data-only host: no account features, so fewer regional blocks.
const BINANCE_WS = 'wss://data-stream.binance.vision/ws'
const POLL_MS = 2_500
const POLL_MAX_MS = 30_000

export interface LiveStream {
  stop(): void
  /** Epoch ms of the last message from the feed, ticking or not. 0 = never. */
  lastSeen(): number
}

/**
 * Streams live prices for [symbol] to [onTick], in the instrument's own currency.
 *
 * [anchor] is a recent INR price (the cache quote) so crypto can draw from the
 * first USDT trade instead of waiting for an INR one.
 */
export function streamLive(
  symbol: string,
  market: Market,
  onTick: (tick: Sample) => void,
  anchor?: number | null,
): LiveStream {
  return market === 'crypto'
    ? streamCrypto(cacheKeyFor(symbol, market), onTick, anchor ?? 0)
    : // An option charts its underlying; asking for the contract would put its
      // premium on the underlying's candles.
      pollQuote(market === 'stock' ? cacheKeyFor(symbol, market) : symbol, market, onTick)
}

function pollQuote(symbol: string, market: Market, onTick: (t: Sample) => void): LiveStream {
  let stopped = false
  let seen = 0
  let last = 0
  let wait = POLL_MS
  let timer: ReturnType<typeof setTimeout> | undefined

  async function tick() {
    // A hidden tab is nobody watching; skip the call but keep the loop.
    if (typeof document === 'undefined' || !document.hidden) {
      try {
        const q = await fromMarketQuote(symbol, market)
        if (stopped) return
        if (q) {
          seen = Date.now()
          // Only a changed price is pushed: after the close the same last price
          // stamped "now" would open fresh flat candles past the session end.
          if (q.price !== last) {
            last = q.price
            wait = POLL_MS
            onTick({ time: q.time, price: q.price })
          } else {
            wait = Math.min(wait * 2, POLL_MAX_MS)
          }
        }
      } catch {
        wait = Math.min(wait * 2, POLL_MAX_MS)
      }
    }
    if (!stopped) timer = setTimeout(tick, wait)
  }
  void tick()

  return {
    stop() {
      stopped = true
      clearTimeout(timer)
    },
    lastSeen: () => seen,
  }
}

function streamCrypto(coin: string, onTick: (t: Sample) => void, anchor: number): LiveStream {
  let ws: WebSocket | null = null
  let stopped = false
  let seen = 0
  let retry = 1_000
  // Rupees per USDT for this coin, so Binance's prints land at our INR level.
  // shortcut: fixed at load, so a premium that drifts over hours drifts the edge;
  // every symbol or timeframe change re-anchors. Re-anchor on a timer if it shows.
  let ratio = 0

  function connect() {
    if (stopped) return
    ws = new WebSocket(`${BINANCE_WS}/${coin.toLowerCase()}usdt@trade`)
    ws.onopen = () => {
      retry = 1_000
    }
    ws.onmessage = (e) => {
      let d: { p?: string; T?: number }
      try {
        d = JSON.parse(String(e.data))
      } catch {
        return
      }
      const price = Number(d.p)
      const time = Math.floor(Number(d.T) / 1000)
      if (!(price > 0) || !Number.isFinite(time)) return
      seen = Date.now()
      if (!ratio && anchor > 0) ratio = anchor / price
      // No anchor means no honest rupee level, so draw nothing and let the
      // host's cache poll carry the chart.
      if (ratio) onTick({ time, price: price * ratio })
    }
    // onerror is always followed by onclose, so reconnecting here covers both.
    ws.onclose = () => {
      if (stopped) return
      setTimeout(connect, retry)
      retry = Math.min(retry * 2, 30_000)
    }
  }
  connect()

  return {
    stop() {
      stopped = true
      ws?.close()
    },
    lastSeen: () => seen,
  }
}
