/*
 * The one runnable check behind the aggregation.
 *
 * Run with `npm test`. Assert-based on purpose: no framework, no fixtures, no
 * config. It fails loudly if the bucketing, the OHLC assignment or the live-tick
 * merge breaks, and those are the three things that would silently draw a
 * plausible but wrong chart — the failure mode nobody spots by looking.
 */

import assert from 'node:assert/strict'
import {
  TIMEFRAME_SECONDS,
  aggregate,
  bucketStart,
  isHonestCandleTimeframe,
  mergeTick,
  rollUp,
  fxFactor,
  scalePrices,
} from './aggregate'
import { DEFAULT_PERIOD, periodFor, periodsFor } from './periods'
import { cacheKeyFor, historySymbol } from './symbols'
import type { Candle, Sample } from './types'

let checks = 0
function check(name: string, fn: () => void) {
  fn()
  checks++
  console.log(`  ok  ${name}`)
}

const M = 60
const at = (minute: number, price: number): Sample => ({ time: minute * M, price })

console.log('aggregate')

check('buckets align to the floor of the interval', () => {
  assert.equal(bucketStart(0, 300), 0)
  assert.equal(bucketStart(299, 300), 0)
  assert.equal(bucketStart(300, 300), 300)
  assert.equal(bucketStart(301, 300), 300)
})

check('five one-minute samples become one 5m candle with real OHLC', () => {
  // The whole reason this file exists: every number below is observed, none
  // invented. Order matters — open must be the FIRST price, close the LAST,
  // even though neither is the extreme.
  const candles = aggregate(
    [at(0, 100), at(1, 105), at(2, 98), at(3, 103), at(4, 101)],
    5 * M,
  )
  assert.equal(candles.length, 1)
  assert.deepEqual(candles[0], { time: 0, open: 100, high: 105, low: 98, close: 101 })
})

check('samples spanning a boundary split into separate candles', () => {
  const candles = aggregate([at(4, 10), at(5, 20), at(9, 30)], 5 * M)
  assert.equal(candles.length, 2)
  assert.deepEqual(candles[0], { time: 0, open: 10, high: 10, low: 10, close: 10 })
  assert.deepEqual(candles[1], { time: 300, open: 20, high: 30, low: 20, close: 30 })
})

check('out-of-order input is sorted, not trusted', () => {
  // Rows can come back from Postgres in any order without an ORDER BY. Reversed
  // input must not swap open and close.
  const forward = aggregate([at(0, 100), at(1, 105), at(2, 101)], 5 * M)
  const reversed = aggregate([at(2, 101), at(0, 100), at(1, 105)], 5 * M)
  assert.deepEqual(reversed, forward)
  assert.equal(reversed[0]!.open, 100)
  assert.equal(reversed[0]!.close, 101)
})

check('zero, negative and non-finite prices are dropped', () => {
  // A single 0 would print a wick to the axis floor and rescale the pane.
  const candles = aggregate(
    [at(0, 100), at(1, 0), at(2, -5), at(3, NaN), at(4, 102)],
    5 * M,
  )
  assert.equal(candles.length, 1)
  assert.deepEqual(candles[0], { time: 0, open: 100, high: 102, low: 100, close: 102 })
})

check('an empty series aggregates to nothing rather than throwing', () => {
  assert.deepEqual(aggregate([], 5 * M), [])
})

check('a lone sample yields a flat candle, which is the honest answer', () => {
  assert.deepEqual(aggregate([at(0, 42)], 5 * M), [
    { time: 0, open: 42, high: 42, low: 42, close: 42 },
  ])
})

console.log('isHonestCandleTimeframe')

check('1m is not candle-able at a 1/min sample rate, 5m and up are', () => {
  assert.equal(isHonestCandleTimeframe('1m'), false)
  assert.equal(isHonestCandleTimeframe('5m'), true)
  assert.equal(isHonestCandleTimeframe('1d'), true)
})

console.log('mergeTick')

const bar: Candle = { time: 300, open: 100, high: 110, low: 95, close: 105 }

check('a tick inside the current bucket extends the bar and moves the close', () => {
  const merged = mergeTick(bar, { time: 400, price: 108 }, 5 * M)
  assert.deepEqual(merged, { time: 300, open: 100, high: 110, low: 95, close: 108 })
})

check('a new high and a new low are taken, the open never moves', () => {
  assert.equal(mergeTick(bar, { time: 400, price: 120 }, 5 * M).high, 120)
  assert.equal(mergeTick(bar, { time: 400, price: 90 }, 5 * M).low, 90)
  assert.equal(mergeTick(bar, { time: 400, price: 90 }, 5 * M).open, 100)
})

check('a tick in the next bucket opens a new bar at that price', () => {
  assert.deepEqual(mergeTick(bar, { time: 600, price: 107 }, 5 * M), {
    time: 600,
    open: 107,
    high: 107,
    low: 107,
    close: 107,
  })
})

check('a late tick folds into the current bar instead of rewriting history', () => {
  // lightweight-charts' update() throws on a time before the last bar, and a
  // cron pass racing a client poll produces exactly this.
  const merged = mergeTick(bar, { time: 310, price: 130 }, 5 * M)
  assert.equal(merged.time, 300)
  assert.equal(merged.high, 130)
})

check('the first tick on an empty chart creates the bar', () => {
  assert.deepEqual(mergeTick(undefined, { time: 640, price: 50 }, 5 * M), {
    time: 600,
    open: 50,
    high: 50,
    low: 50,
    close: 50,
  })
})

console.log('rollUp')

check('1m bars roll into a 5m bar keeping the outer open and close', () => {
  const oneMin: Candle[] = [
    { time: 0, open: 10, high: 12, low: 9, close: 11 },
    { time: 60, open: 11, high: 15, low: 11, close: 14 },
    { time: 120, open: 14, high: 14, low: 8, close: 9 },
  ]
  assert.deepEqual(rollUp(oneMin, M, 5 * M), [
    { time: 0, open: 10, high: 15, low: 8, close: 9 },
  ])
})

check('rolling to a non-multiple or a finer timeframe is refused', () => {
  // 30m into 1h is fine; 30m into 45m would straddle boundaries and take the
  // open from the wrong side of one.
  assert.throws(() => rollUp([], TIMEFRAME_SECONDS['30m'], 45 * M))
  assert.throws(() => rollUp([], TIMEFRAME_SECONDS['1h'], TIMEFRAME_SECONDS['5m']))
})

check('rolling to the same timeframe copies rather than aliasing', () => {
  const src: Candle[] = [{ time: 0, open: 1, high: 2, low: 1, close: 2 }]
  const out = rollUp(src, M, M)
  assert.deepEqual(out, src)
  assert.notEqual(out, src)
})

console.log('symbols')

check('indices are sent to the history feed in caret form', () => {
  // Plain NIFTY becomes NIFTY.NS upstream, which is not a listing: the live
  // function answers 500 "YF history failed: 404". Verified against production.
  assert.equal(historySymbol('NIFTY', 'stock'), '^NSEI')
  assert.equal(historySymbol('BANKNIFTY', 'stock'), '^NSEBANK')
  assert.equal(historySymbol('SENSEX', 'stock'), '^BSESN')
})

check('equities and non-Indian markets pass through untouched', () => {
  assert.equal(historySymbol('RELIANCE', 'stock'), 'RELIANCE')
  assert.equal(historySymbol('AAPL', 'us_stock'), 'AAPL')
  assert.equal(historySymbol('BTC', 'crypto'), 'BTC')
  // Already caret form: must not be double-mapped.
  assert.equal(historySymbol('^NSEI', 'stock'), '^NSEI')
})

check('every button names a bar size, and each one is distinct', () => {
  // The bug this guards is the one users actually reported. The old row mixed bar
  // sizes with spans, so `1D` (5m bars over a day) and `5m` (5m bars over five
  // days) drew identically sized candles and tapping between them looked like
  // nothing happened. Checking that no two buttons share an INTERVAL is the check
  // that would have caught it; the old one compared interval+range, which differed,
  // so it passed while the row was still confusing.
  for (const market of ['stock', 'us_stock', 'crypto'] as const) {
    const seen = new Map<string, string>()
    for (const p of periodsFor(market)) {
      const clash = seen.get(p.interval)
      assert.equal(clash, undefined, `${market}: ${p.id} and ${clash} both draw ${p.interval}`)
      seen.set(p.interval, p.id)
      // And the label says the bar size, so the row reads as one idea.
      assert.equal(p.label, p.id)
    }
  }
})

check('the default period is a period that actually exists', () => {
  // The check for a real shipped bug. `main.ts` initialised its period id to the
  // string '3M', which stopped being a valid id when the row became bar sizes
  // only. Nothing caught it because `periodFor` falls back to the default, so the
  // CANVAS was always correct — but `currentPeriod()` returned '3M', which matches
  // no chip, so the app opened with no timeframe highlighted at all.
  //
  // Anything holding a period id must hold one of these, so assert the default is
  // one and that the fallback really does land on it.
  for (const market of ['stock', 'us_stock', 'crypto'] as const) {
    const ids = periodsFor(market).map((p) => p.id)
    assert.ok(
      ids.includes(DEFAULT_PERIOD),
      `${market}: DEFAULT_PERIOD ${DEFAULT_PERIOD} is not in [${ids.join(', ')}]`,
    )
    assert.equal(periodFor(market, DEFAULT_PERIOD).id, DEFAULT_PERIOD)
    // A retired or misspelled id must land on the default rather than throwing or
    // drawing an empty chart.
    for (const dead of ['3M', '1Y', '5Y', '10m', '1M', '', 'nonsense']) {
      assert.equal(
        periodFor(market, dead).id,
        DEFAULT_PERIOD,
        `${market}: '${dead}' should fall back to ${DEFAULT_PERIOD}`,
      )
    }
  }
})

check('crypto is offered the same timeframes as everything else', () => {
  // It used to get spans only, because CoinGecko ignores the interval it is sent.
  // Crypto history comes from CoinDCX now, which serves a named interval, so there
  // is no longer a reason to offer crypto less.
  const stock = periodsFor('stock').map((p) => p.id)
  const crypto = periodsFor('crypto').map((p) => p.id)
  assert.deepEqual(crypto, stock)
  for (const wanted of ['1m', '5m', '15m', '30m', '1h'] as const) {
    assert.ok(crypto.includes(wanted), `crypto must offer ${wanted}`)
  }
})

check('rolling finer bars into coarser ones keeps the real extremes', () => {
  // The rollup itself, which `market-history` now does server-side for the sizes a
  // venue cannot serve — CoinDCX has no 5m or 30m, Yahoo has no 10m.
  const fives: Candle[] = [
    { time: 600, open: 10, high: 12, low: 9, close: 11 },
    { time: 900, open: 11, high: 15, low: 8, close: 14 },
  ]
  const tens = rollUp(fives, 300, 600)
  assert.equal(tens.length, 1)
  assert.deepEqual(tens[0], { time: 600, open: 10, high: 15, low: 8, close: 14 })
})

check('currency conversion runs the right way round', () => {
  // A US equity read in rupees: GOOGL at $338.46 with 1 USD = 88 INR is ~₹29,784.
  // Backwards it would be ₹3.85, which looks like a penny stock rather than an
  // error, so the direction is worth pinning.
  assert.equal(fxFactor('USD', 'INR', 88), 88)
  assert.ok(Math.abs(338.46 * fxFactor('USD', 'INR', 88) - 29784.48) < 0.01)

  // An Indian equity read in dollars: RELIANCE at ₹1322 is ~$15.02.
  assert.ok(Math.abs(1322 * fxFactor('INR', 'USD', 88) - 15.023) < 0.001)

  // Same currency both ways is exactly 1, not 1.0000000001 from a divide.
  assert.equal(fxFactor('INR', 'INR', 88), 1)
  assert.equal(fxFactor('USD', 'USD', 0), 1)
})

check('an unusable rate refuses to convert rather than zeroing the chart', () => {
  // The app starts with usdInr = 0 before the first fetch, and stays there
  // offline. Scaling by 0 would draw a flat line along the axis; scaling by
  // Infinity would draw nothing. Both are worse than the wrong currency, and the
  // caller picks its axis label from this factor so the label stays honest too.
  for (const bad of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.equal(fxFactor('USD', 'INR', bad), 1, `rate ${bad} must not convert`)
  }
})

check('scaling moves every price and no timestamp', () => {
  const bars: Candle[] = [
    { time: 100, open: 10, high: 20, low: 5, close: 15 },
    { time: 200, open: 15, high: 25, low: 12, close: 22 },
  ]
  const out = scalePrices(bars, 2)
  assert.deepEqual(out, [
    { time: 100, open: 20, high: 40, low: 10, close: 30 },
    { time: 200, open: 30, high: 50, low: 24, close: 44 },
  ])
  // The originals are untouched: the caller may still hold them.
  assert.equal(bars[0]!.open, 10)
  // A factor of 1 is the common case — INR instrument, INR display — and must not
  // allocate a copy of several hundred bars on every load.
  assert.equal(scalePrices(bars, 1), bars)
})

check('an option charts its underlying, and hyphenated equities survive', () => {
  // The app's own option format. Yahoo has no listing for the contract, so
  // sending it verbatim drew nothing at all on the option detail screen.
  assert.equal(historySymbol('NIFTY-2026-09-30-25000-CE', 'stock'), '^NSEI')
  assert.equal(historySymbol('RELIANCE-2026-09-30-1400-PE', 'stock'), 'RELIANCE')

  // Real NSE tickers containing a hyphen: splitting on the first one would send
  // the chart to an instrument that does not exist.
  assert.equal(historySymbol('BAJAJ-AUTO', 'stock'), 'BAJAJ-AUTO')
  assert.equal(historySymbol('NAM-INDIA', 'stock'), 'NAM-INDIA')

  // And the drawn instrument is still the one being priced.
  assert.equal(
    cacheKeyFor(historySymbol('NIFTY-2026-09-30-25000-CE', 'stock'), 'stock'),
    cacheKeyFor('NIFTY-2026-09-30-25000-CE', 'stock'),
  )
})

check('quote keys collapse to what refresh-quotes actually stores', () => {
  assert.equal(cacheKeyFor('NSE:RELIANCE-EQ', 'stock'), 'RELIANCE')
  assert.equal(cacheKeyFor('^NSEI', 'stock'), 'NIFTY')
  assert.equal(cacheKeyFor('B-BTC_USDT', 'crypto'), 'BTC')
  assert.equal(cacheKeyFor('BTC-INR', 'crypto'), 'BTC')
  // An option collapses to its underlying, which is what the cache holds.
  assert.equal(cacheKeyFor('NIFTY260529C20000', 'stock'), 'NIFTY')
})

check('the two directions are mirror images for every index', () => {
  // The pairing that matters: draw one instrument, price the same one. If these
  // ever disagree the chart looks like a data glitch rather than a mapping bug.
  for (const ours of ['NIFTY', 'BANKNIFTY', 'SENSEX'] as const) {
    assert.equal(
      cacheKeyFor(historySymbol(ours, 'stock'), 'stock'),
      ours,
      `${ours} does not survive the round trip`,
    )
  }
})

console.log(`\n${checks} checks passed`)
