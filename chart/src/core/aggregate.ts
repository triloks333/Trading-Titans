import type { Candle, Currency, Sample, Seconds, Timeframe } from './types'

/*
 * Turning our own price samples into candles.
 *
 * WHY THIS EXISTS
 * `quotes_cache` holds one price per symbol, rewritten by the `refresh-quotes`
 * cron every minute. That is a sample, not a bar: at one observation per minute
 * there is no open/high/low/close inside a minute to read. So a 1-minute candle
 * built from it would have o=h=l=c and three of its four numbers would be
 * fabricated.
 *
 * What IS honest:
 *   - 5 minutes and up, from five or more samples: open = first, high = max,
 *     low = min, close = last. Every number is one we actually observed.
 *   - 1 minute, drawn as a line. See `isHonestCandleTimeframe`.
 *
 * The same functions serve the live edge: `mergeTick` folds the newest price into
 * the bar in progress, which is how the right-hand side of the chart tracks the
 * price the matching engine is filling at.
 */

/** Bucket width in seconds for each timeframe. */
export const TIMEFRAME_SECONDS: Record<Timeframe, Seconds> = {
  '1m': 60,
  '5m': 5 * 60,
  '15m': 15 * 60,
  '30m': 30 * 60,
  '1h': 60 * 60,
  '1d': 24 * 60 * 60,
  '1w': 7 * 24 * 60 * 60,
}

/**
 * False where our sampling rate cannot fill four distinct OHLC values.
 *
 * At one sample per minute a 1-minute bar is a single observation. Callers draw
 * a line there instead of inventing a body and two wicks. This only governs
 * OUR series — vendor history arrives pre-aggregated with real intra-bar
 * extremes and is not subject to it.
 */
export function isHonestCandleTimeframe(tf: Timeframe, sampleIntervalSeconds = 60): boolean {
  return TIMEFRAME_SECONDS[tf] >= sampleIntervalSeconds * 2
}

/** The start of the bucket [time] falls in. */
export function bucketStart(time: Seconds, bucketSeconds: Seconds): Seconds {
  return Math.floor(time / bucketSeconds) * bucketSeconds
}

/**
 * Groups samples into OHLC bars of [bucketSeconds].
 *
 * Sorts defensively rather than trusting the caller: samples read back from the
 * database in a different order would otherwise put the open and close at the
 * wrong ends of the bar, which looks like a plausible chart and is wrong.
 *
 * Non-finite and non-positive prices are dropped. A single zero would print a
 * wick to the floor and rescale the whole pane, so it is worth more to lose the
 * point than to draw it.
 */
export function aggregate(samples: Sample[], bucketSeconds: Seconds): Candle[] {
  if (bucketSeconds <= 0) throw new Error('bucketSeconds must be positive')

  const clean = samples
    .filter((s) => Number.isFinite(s.price) && s.price > 0 && Number.isFinite(s.time))
    .sort((a, b) => a.time - b.time)

  const out: Candle[] = []
  for (const s of clean) {
    const start = bucketStart(s.time, bucketSeconds)
    const last = out[out.length - 1]
    if (last && last.time === start) {
      last.high = Math.max(last.high, s.price)
      last.low = Math.min(last.low, s.price)
      last.close = s.price
    } else {
      out.push({ time: start, open: s.price, high: s.price, low: s.price, close: s.price })
    }
  }
  return out
}

/**
 * Folds a live price into the bar in progress.
 *
 * Returns the single bar to hand to `ISeriesApi.update()`, which replaces the bar
 * at that time or appends a later one — so one return value covers both "the
 * current candle grew" and "a new candle opened".
 *
 * [last] is the newest bar currently on the chart, or undefined for an empty
 * chart. When the tick belongs to a bucket at or before [last], the bar is
 * extended; a tick that lands in a NEW bucket opens at that price, which is
 * correct: the open of a bar is the first price observed in it.
 *
 * A tick older than the current bar is folded into that bar rather than
 * rewriting history, because `update()` rejects a time before the last bar and
 * would throw. Out-of-order arrivals are normal when a cron pass and a client
 * poll race.
 */
export function mergeTick(
  last: Candle | undefined,
  tick: Sample,
  bucketSeconds: Seconds,
): Candle {
  const start = bucketStart(tick.time, bucketSeconds)

  if (!last || start > last.time) {
    return { time: start, open: tick.price, high: tick.price, low: tick.price, close: tick.price }
  }

  return {
    time: last.time,
    open: last.open,
    high: Math.max(last.high, tick.price),
    low: Math.min(last.low, tick.price),
    close: tick.price,
  }
}

/**
 * Re-buckets existing bars into a coarser timeframe.
 *
 * Used when the source series is finer than the requested view — five 1-minute
 * bars into one 5-minute bar. The target must be a whole multiple of the source
 * or bars would straddle boundaries and the open would come from the wrong side.
 */
export function rollUp(candles: Candle[], fromSeconds: Seconds, toSeconds: Seconds): Candle[] {
  if (toSeconds < fromSeconds) throw new Error('cannot roll up to a finer timeframe')
  if (toSeconds % fromSeconds !== 0) {
    throw new Error(`${toSeconds}s is not a whole multiple of ${fromSeconds}s`)
  }
  if (toSeconds === fromSeconds) return candles.slice()

  const sorted = candles.slice().sort((a, b) => a.time - b.time)
  const out: Candle[] = []
  for (const c of sorted) {
    const start = bucketStart(c.time, toSeconds)
    const last = out[out.length - 1]
    if (last && last.time === start) {
      last.high = Math.max(last.high, c.high)
      last.low = Math.min(last.low, c.low)
      last.close = c.close
    } else {
      out.push({ time: start, open: c.open, high: c.high, low: c.low, close: c.close })
    }
  }
  return out
}

/*
 * ── Currency ────────────────────────────────────────────────────────────────
 *
 * An instrument is quoted in one currency and the user may want to read it in
 * another. `quotes_cache` holds US equities in dollars (GOOGL at 338.46) and
 * everything else in rupees, including crypto, which `market-quote` converts
 * upstream before caching. A user who chose a dollar display and opens RELIANCE
 * wants dollars on the axis, the crosshair, the legend and the last-price badge —
 * every number, not just the ones that were easy.
 *
 * WHY THE HOST SUPPLIES THE RATE
 * The Flutter app already holds one, in `CurrencyService`, refreshed every half
 * hour and shared with `Money` — which is what formats the price in the header
 * directly above this chart. If the chart fetched its own rate the two would
 * disagree by whatever moved in between, and a header and a chart that disagree
 * about the same instrument read as a bug in the prices rather than in the FX.
 * So the caller states the facts and this does the arithmetic.
 */

/**
 * Multiplier to convert a price from [from] into [to].
 *
 * Returns exactly 1 when no conversion is possible, which is the safe answer
 * rather than the convenient one: a zero or absent rate would otherwise scale
 * every price to zero or infinity, and a chart of zeroes is worse than a chart in
 * the wrong currency. Callers pair this with a label chosen from the factor, so an
 * unusable rate shows honest rupees rather than rupees labelled as dollars.
 *
 * Mirrors `FxConverter` in `app/lib/core/currency.dart`. That one is the app's,
 * this one is the chart's; both take rupees-per-dollar and neither rounds.
 */
export function fxFactor(from: Currency, to: Currency, usdInr: number): number {
  if (from === to) return 1
  if (!Number.isFinite(usdInr) || usdInr <= 0) return 1
  return from === 'USD' ? usdInr : 1 / usdInr
}

/**
 * Every price in [candles] multiplied by [factor], times untouched.
 *
 * Applied at the data boundary, before the series is handed to the chart, so that
 * the axis, the crosshair, the legend and every price-pane indicator are all in
 * the same units without any of them knowing a conversion happened. Indicators
 * come out correct for free: a moving average or MACD scales with its input, and
 * a bounded oscillator like RSI or Stochastic divides the factor straight back
 * out.
 */
export function scalePrices(candles: Candle[], factor: number): Candle[] {
  if (factor === 1) return candles
  return candles.map((c) => ({
    time: c.time,
    open: c.open * factor,
    high: c.high * factor,
    low: c.low * factor,
    close: c.close * factor,
  }))
}
