import type { Market } from './types'

/*
 * Symbol identity, in both directions.
 *
 * One instrument has three names in this system and they do not agree:
 *
 *   app / quotes_cache   NIFTY          RELIANCE      BTC
 *   Yahoo (history)      ^NSEI          RELIANCE.NS   BTC-INR
 *   CoinDCX perpetual    —              —             B-BTC_USDT
 *
 * The two functions here are the translation, and they are mirror images. Keep
 * them that way: if `historySymbol` sends the chart to one instrument while
 * `cacheKeyFor` prices a different one, the chart draws one thing and quotes
 * another, which looks like a data glitch rather than a mapping bug.
 *
 * Both are pure and live in core rather than in `src/data` precisely so the test
 * can reach them without pulling in the network client.
 */

/**
 * Index tickers, translated for the history feed.
 *
 * `refresh-quotes` stores indices under the plain name, so `quotes_cache` is
 * keyed on `NIFTY`. Yahoo needs the caret form, and `toYfSymbol` in the edge
 * function only passes `^NSEI`, `^NSEBANK` and `^BSESN` through untouched —
 * everything else gets `.NS` appended. So `NIFTY` went out as `NIFTY.NS`, which
 * is not a listing, and `market-history` answered 500 with "YF history failed:
 * 404".
 *
 * Verified against the live function: `NIFTY` 500s, `^NSEI` returns 376
 * five-minute bars, `^NSEBANK` and `^BSESN` return 248 daily bars each.
 */
const HISTORY_ALIAS: Record<string, string> = {
  NIFTY: '^NSEI',
  NIFTY50: '^NSEI',
  NSEI: '^NSEI',
  BANKNIFTY: '^NSEBANK',
  NSEBANK: '^NSEBANK',
  SENSEX: '^BSESN',
  BSESN: '^BSESN',
}

/** The symbol to ask the history feed for. */
export function historySymbol(symbol: string, market: Market): string {
  if (market !== 'stock') return symbol
  const s = symbol.toUpperCase().trim()

  // An option has no history feed of its own — Yahoo does not list
  // `NIFTY-2026-09-30-25000-CE`, it answers 404 — so chart the underlying. That
  // is also what `cacheKeyFor` prices the bar from, so the drawn instrument and
  // the live tick stay the same instrument.
  //
  // Matched on the `-CE`/`-PE` suffix rather than by splitting on the first
  // hyphen, because `BAJAJ-AUTO` and `NAM-INDIA` are equities whose real Yahoo
  // listing contains one.
  if (/-(CE|PE)$/.test(s)) return historySymbol(s.split('-')[0]!, market)

  // Already caret form, or a plain equity: both are correct as they stand.
  if (s.startsWith('^')) return s
  return HISTORY_ALIAS[s] ?? symbol
}

/**
 * The key `refresh-quotes` stores a symbol under in `quotes_cache`.
 *
 * Mirrors `extractUnderlying` in that function and `cacheKeyFor` in
 * `MarketService`: derivatives are cached under their underlying, and index
 * aliases collapse to canonical names. Getting this wrong is a silent cache miss
 * and a live fetch on every poll rather than an error, so it is worth keeping in
 * step.
 *
 * ponytail: a third copy of this rule, after the Dart and the edge function. The
 * ceiling is drift when a new alias appears; the upgrade path is an RPC returning
 * the canonical key, which is not worth a round trip per poll.
 */
export function cacheKeyFor(symbol: string, market: Market): string {
  let s = symbol.toUpperCase().trim()

  if (market === 'crypto') {
    // CoinDCX perpetuals arrive as B-BTC_USDT; the feed only knows BTC.
    return s
      .replace(/^B-/, '')
      .replace(/_USDT$/, '')
      .replace(/-(INR|USD|USDT)$/, '')
  }

  if (s.startsWith('NSE:') || s.startsWith('BSE:')) s = s.slice(4)
  s = s.replace('-EQ-', '-')
  if (s.endsWith('-EQ')) s = s.slice(0, -3)
  if (s.includes(' ')) s = s.split(' ')[0]!
  if (s.includes('-')) s = s.split('-')[0]!

  if (s === '^NSEI' || s === 'NSEI' || s === 'NIFTY50') return 'NIFTY'
  if (s === '^NSEBANK' || s === 'NSEBANK') return 'BANKNIFTY'
  if (s === '^BSESN' || s === 'SENSEX' || s === 'BSESN') return 'SENSEX'

  // An option or future symbol carries a digit; the underlying precedes it.
  const digit = s.search(/\d/)
  if (digit > 0) s = s.slice(0, digit)
  return s
}
