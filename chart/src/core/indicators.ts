import type { Candle, Seconds } from './types'

/*
 * Technical indicators, as pure functions over the candle array.
 *
 * Nothing here touches the DOM, the network or lightweight-charts. That is what
 * lets the same nineteen indicators serve the React web app and the Flutter
 * WebView without either of them owning the maths, and it is what makes the
 * awkward ones (Wilder smoothing, ADX, Parabolic SAR) checkable in `indicators.test.ts`.
 *
 * ALIGNMENT
 * Every internal series is the same length as `candles`, with `null` where the
 * indicator has not warmed up yet. Returning a short array instead would push
 * "which bar does index 0 mean" onto every caller, and an off-by-one there draws
 * a plausible line at the wrong dates — the kind of wrong nobody sees.
 *
 * WHAT IS MISSING, AND WHY
 * No VWAP, OBV, Money Flow Index, Volume Profile or Accumulation/Distribution.
 * All of them need per-bar volume, and `market-history` returns only `{t,o,h,l,c}` —
 * the edge function reads Yahoo's volume and drops it. Adding them is a change to
 * that function, not to this file, and inventing volume to fill the gap would make
 * every one of them lie.
 */

/** A value per bar, `null` before the indicator has enough history. */
export type Series = (number | null)[]

/** A plottable point. Bars with no value are omitted, not zeroed. */
export interface LinePoint {
  time: Seconds
  value: number
}

export type PlotStyle = 'line' | 'histogram' | 'dots'

export interface IndicatorPlot {
  key: string
  label: string
  color: string
  style: PlotStyle
  lineWidth?: 1 | 2
  /** Histogram bars coloured per point, for MACD. */
  colors?: string[]
  data: LinePoint[]
}

export interface IndicatorResult {
  id: string
  /** Shown in the legend, with the parameters baked in: "EMA 21". */
  label: string
  /** `price` overlays the candles; `separate` gets its own pane. */
  pane: 'price' | 'separate'
  plots: IndicatorPlot[]
  /** Horizontal reference lines, e.g. RSI 30 and 70. */
  levels?: number[]
  /** Pins the pane's scale, e.g. [0, 100] for RSI. */
  range?: [number, number]
}

// ── Primitives ──────────────────────────────────────────────────────────────

const closes = (c: Candle[]): Series => c.map((x) => x.close)
const highs = (c: Candle[]): Series => c.map((x) => x.high)
const lows = (c: Candle[]): Series => c.map((x) => x.low)
/** Typical price, the basis for CCI and the Ichimoku-style midpoints. */
const typical = (c: Candle[]): Series => c.map((x) => (x.high + x.low + x.close) / 3)

export function sma(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  let sum = 0
  let count = 0
  for (let i = 0; i < v.length; i++) {
    const x = v[i]
    if (x === null || x === undefined) {
      // A gap resets the window: averaging across it would silently span a hole.
      sum = 0
      count = 0
      continue
    }
    sum += x
    count++
    if (count > n) {
      const drop = v[i - n]
      if (drop !== null && drop !== undefined) sum -= drop
      count = n
    }
    if (count === n) out[i] = sum / n
  }
  return out
}

/**
 * Exponential moving average, seeded with the SMA of the first [n] values.
 *
 * Seeding matters. Starting from the first close instead makes the early output
 * depend heavily on one bar, and two charts over different ranges then disagree
 * about the same date. The SMA seed is what Wilder, TradingView and every
 * textbook use.
 */
export function ema(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  const k = 2 / (n + 1)
  let prev: number | null = null
  let sum = 0
  let count = 0

  for (let i = 0; i < v.length; i++) {
    const x = v[i]
    if (x === null || x === undefined) continue
    if (prev === null) {
      sum += x
      count++
      if (count === n) {
        prev = sum / n
        out[i] = prev
      }
      continue
    }
    prev = x * k + prev * (1 - k)
    out[i] = prev
  }
  return out
}

/** Weighted moving average, weights 1..n with n on the newest bar. */
export function wma(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  const denom = (n * (n + 1)) / 2
  for (let i = n - 1; i < v.length; i++) {
    let acc = 0
    let ok = true
    for (let j = 0; j < n; j++) {
      const x = v[i - n + 1 + j]
      if (x === null || x === undefined) {
        ok = false
        break
      }
      acc += x * (j + 1)
    }
    if (ok) out[i] = acc / denom
  }
  return out
}

/**
 * Wilder's smoothing: seed with the SMA of the first [n], then
 * `(prev * (n-1) + x) / n`.
 *
 * Not the same as an EMA of period n — it is an EMA of period 2n-1. RSI, ATR and
 * ADX are all defined in terms of this, and substituting a plain EMA gives values
 * that look right and disagree with every other platform.
 */
export function wilder(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  let prev: number | null = null
  let sum = 0
  let count = 0

  for (let i = 0; i < v.length; i++) {
    const x = v[i]
    if (x === null || x === undefined) continue
    if (prev === null) {
      sum += x
      count++
      if (count === n) {
        prev = sum / n
        out[i] = prev
      }
      continue
    }
    prev = (prev * (n - 1) + x) / n
    out[i] = prev
  }
  return out
}

/**
 * Pins a value to a bounded oscillator's defined range.
 *
 * Needed for real, not for tidiness. The divisions in the stochastic family carry
 * floating-point noise — measured `-1.18e-14` and `100.00000000000001` on ordinary
 * data — and both cause visible defects: the pane is scaled to exactly [0, 100] so
 * an overshoot sits a hair outside it, and a legend formatting `-1.18e-14` shows
 * `-0.0000`, which reads as a bug to whoever is looking at it.
 */
function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v
}

/** Population standard deviation over a rolling window. */
export function stdev(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  for (let i = n - 1; i < v.length; i++) {
    let sum = 0
    let ok = true
    for (let j = 0; j < n; j++) {
      const x = v[i - j]
      if (x === null || x === undefined) {
        ok = false
        break
      }
      sum += x
    }
    if (!ok) continue
    const mean = sum / n
    let acc = 0
    for (let j = 0; j < n; j++) acc += (v[i - j]! - mean) ** 2
    out[i] = Math.sqrt(acc / n)
  }
  return out
}

/** Rolling highest of [v]. */
export function highest(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  for (let i = n - 1; i < v.length; i++) {
    let best = -Infinity
    for (let j = 0; j < n; j++) {
      const x = v[i - j]
      if (x === null || x === undefined) {
        best = -Infinity
        break
      }
      if (x > best) best = x
    }
    if (best !== -Infinity) out[i] = best
  }
  return out
}

/** Rolling lowest of [v]. */
export function lowest(v: Series, n: number): Series {
  const out: Series = new Array(v.length).fill(null)
  for (let i = n - 1; i < v.length; i++) {
    let best = Infinity
    for (let j = 0; j < n; j++) {
      const x = v[i - j]
      if (x === null || x === undefined) {
        best = Infinity
        break
      }
      if (x < best) best = x
    }
    if (best !== Infinity) out[i] = best
  }
  return out
}

/**
 * True Range: the greater of the bar's own span and its gap from the previous
 * close. The gap terms are what make ATR react to overnight moves, which on
 * Indian equities is most of the interesting volatility.
 */
export function trueRange(c: Candle[]): Series {
  const out: Series = new Array(c.length).fill(null)
  for (let i = 1; i < c.length; i++) {
    const cur = c[i]!
    const prevClose = c[i - 1]!.close
    out[i] = Math.max(
      cur.high - cur.low,
      Math.abs(cur.high - prevClose),
      Math.abs(cur.low - prevClose),
    )
  }
  // Bar 0 has no previous close, so its range is all we can honestly say.
  if (c.length > 0) out[0] = c[0]!.high - c[0]!.low
  return out
}

export function atr(c: Candle[], n = 14): Series {
  return wilder(trueRange(c), n)
}

// ── Oscillators and studies ─────────────────────────────────────────────────

/** Relative Strength Index, Wilder smoothed. */
export function rsi(c: Candle[], n = 14): Series {
  const gains: Series = new Array(c.length).fill(null)
  const losses: Series = new Array(c.length).fill(null)
  for (let i = 1; i < c.length; i++) {
    const diff = c[i]!.close - c[i - 1]!.close
    gains[i] = Math.max(diff, 0)
    losses[i] = Math.max(-diff, 0)
  }
  // Bar 0 has no change to measure, so it stays null rather than counting as flat.
  const avgGain = wilder(gains.slice(1), n)
  const avgLoss = wilder(losses.slice(1), n)

  const out: Series = new Array(c.length).fill(null)
  for (let i = 0; i < avgGain.length; i++) {
    const g = avgGain[i]
    const l = avgLoss[i]
    if (g === null || l === null || g === undefined || l === undefined) continue
    // All-gains means no downside to divide by; 100 is the defined limit.
    out[i + 1] = l === 0 ? 100 : clamp(100 - 100 / (1 + g / l), 0, 100)
  }
  return out
}

/** Stochastic %K and %D. */
export function stochastic(c: Candle[], n = 14, smooth = 3): { k: Series; d: Series } {
  const hh = highest(highs(c), n)
  const ll = lowest(lows(c), n)
  const raw: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const h = hh[i]
    const l = ll[i]
    if (h === null || l === null || h === undefined || l === undefined) continue
    // A flat window has no range to place the close within; 50 is the neutral
    // reading and avoids a divide by zero producing Infinity.
    raw[i] = h === l ? 50 : clamp(((c[i]!.close - l) / (h - l)) * 100, 0, 100)
  }
  const k = clampSeries(sma(raw, smooth), 0, 100)
  return { k, d: clampSeries(sma(k, smooth), 0, 100) }
}

/** Clamps every value in a series, leaving the nulls alone. */
function clampSeries(s: Series, min: number, max: number): Series {
  return s.map((v) => (v === null || v === undefined ? null : clamp(v, min, max)))
}

/** Average Directional Index, with the two directional indicators. */
export function adx(c: Candle[], n = 14): { adx: Series; plusDi: Series; minusDi: Series } {
  const plusDm: Series = new Array(c.length).fill(null)
  const minusDm: Series = new Array(c.length).fill(null)

  for (let i = 1; i < c.length; i++) {
    const up = c[i]!.high - c[i - 1]!.high
    const down = c[i - 1]!.low - c[i]!.low
    // Only the larger move counts, and only if it is positive: a bar that is
    // both an outside and an inside bar contributes to neither direction.
    plusDm[i] = up > down && up > 0 ? up : 0
    minusDm[i] = down > up && down > 0 ? down : 0
  }

  const smTr = wilder(trueRange(c).slice(1), n)
  const smPlus = wilder(plusDm.slice(1), n)
  const smMinus = wilder(minusDm.slice(1), n)

  const plusDi: Series = new Array(c.length).fill(null)
  const minusDi: Series = new Array(c.length).fill(null)
  const dx: Series = new Array(c.length).fill(null)

  for (let i = 0; i < smTr.length; i++) {
    const tr = smTr[i]
    const p = smPlus[i]
    const m = smMinus[i]
    if (!tr || p === null || m === null || p === undefined || m === undefined) continue
    const pdi = clamp((p / tr) * 100, 0, 100)
    const mdi = clamp((m / tr) * 100, 0, 100)
    plusDi[i + 1] = pdi
    minusDi[i + 1] = mdi
    const sum = pdi + mdi
    dx[i + 1] = sum === 0 ? 0 : clamp((Math.abs(pdi - mdi) / sum) * 100, 0, 100)
  }

  return { adx: wilder(dx, n), plusDi, minusDi }
}

/** Commodity Channel Index. */
export function cci(c: Candle[], n = 20): Series {
  const tp = typical(c)
  const avg = sma(tp, n)
  const out: Series = new Array(c.length).fill(null)
  for (let i = n - 1; i < c.length; i++) {
    const a = avg[i]
    if (a === null || a === undefined) continue
    let dev = 0
    for (let j = 0; j < n; j++) dev += Math.abs(tp[i - j]! - a)
    const md = dev / n
    // Lambert's 0.015 makes roughly 70-80% of readings fall inside ±100.
    out[i] = md === 0 ? 0 : (tp[i]! - a) / (0.015 * md)
  }
  return out
}

/** Parabolic SAR. Stateful by nature: each bar depends on the whole run so far. */
export function psar(c: Candle[], step = 0.02, max = 0.2): Series {
  const out: Series = new Array(c.length).fill(null)
  if (c.length < 2) return out

  let rising = c[1]!.close >= c[0]!.close
  let af = step
  let sar = rising ? c[0]!.low : c[0]!.high
  let ep = rising ? c[0]!.high : c[0]!.low

  for (let i = 1; i < c.length; i++) {
    const bar = c[i]!
    sar = sar + af * (ep - sar)

    // The SAR may never enter the previous two bars' range, or it would signal a
    // reversal on a bar that never actually traded through it.
    const prev = c[i - 1]!
    if (rising) {
      sar = Math.min(sar, prev.low, c[Math.max(0, i - 2)]!.low)
    } else {
      sar = Math.max(sar, prev.high, c[Math.max(0, i - 2)]!.high)
    }

    if (rising && bar.low < sar) {
      rising = false
      sar = ep
      ep = bar.low
      af = step
    } else if (!rising && bar.high > sar) {
      rising = true
      sar = ep
      ep = bar.high
      af = step
    } else if (rising && bar.high > ep) {
      ep = bar.high
      af = Math.min(af + step, max)
    } else if (!rising && bar.low < ep) {
      ep = bar.low
      af = Math.min(af + step, max)
    }

    out[i] = sar
  }
  return out
}

/** Supertrend: an ATR band that only ever tightens until price breaks it. */
export function supertrend(
  c: Candle[],
  n = 10,
  mult = 3,
): { line: Series; rising: boolean[] } {
  const a = atr(c, n)
  const tp = typical(c)
  const line: Series = new Array(c.length).fill(null)
  const rising: boolean[] = new Array(c.length).fill(true)

  let upper: number | null = null
  let lower: number | null = null
  let up = true

  for (let i = 0; i < c.length; i++) {
    const av = a[i]
    const mid = tp[i]
    if (av === null || av === undefined || mid === null || mid === undefined) continue

    const basicUpper = mid + mult * av
    const basicLower = mid - mult * av
    const prevClose = i > 0 ? c[i - 1]!.close : c[i]!.close

    // The ratchet: a band moves in the favourable direction freely and only
    // retreats once price closes through it. Without this Supertrend is just an
    // ATR channel and gives no trend.
    upper =
      upper === null || basicUpper < upper || prevClose > upper ? basicUpper : upper
    lower =
      lower === null || basicLower > lower || prevClose < lower ? basicLower : lower

    if (c[i]!.close > upper) up = true
    else if (c[i]!.close < lower) up = false

    rising[i] = up
    line[i] = up ? lower : upper
  }
  return { line, rising }
}

/** Rate of Change, as a percentage. */
export function roc(c: Candle[], n = 12): Series {
  const out: Series = new Array(c.length).fill(null)
  for (let i = n; i < c.length; i++) {
    const past = c[i - n]!.close
    if (past !== 0) out[i] = ((c[i]!.close - past) / past) * 100
  }
  return out
}

/** Momentum: the raw price difference over [n] bars. */
export function momentum(c: Candle[], n = 10): Series {
  const out: Series = new Array(c.length).fill(null)
  for (let i = n; i < c.length; i++) out[i] = c[i]!.close - c[i - n]!.close
  return out
}

/** Williams %R. Same shape as the stochastic, on a -100..0 scale. */
export function williamsR(c: Candle[], n = 14): Series {
  const hh = highest(highs(c), n)
  const ll = lowest(lows(c), n)
  const out: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const h = hh[i]
    const l = ll[i]
    if (h === null || l === null || h === undefined || l === undefined) continue
    out[i] = h === l ? -50 : clamp(((h - c[i]!.close) / (h - l)) * -100, -100, 0)
  }
  return out
}

/** MACD line, signal and histogram. */
export function macd(
  c: Candle[],
  fast = 12,
  slow = 26,
  signalPeriod = 9,
): { macd: Series; signal: Series; histogram: Series } {
  const f = ema(closes(c), fast)
  const s = ema(closes(c), slow)
  const line: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const a = f[i]
    const b = s[i]
    // Starts only once the SLOW average exists, so the line does not begin as a
    // difference against nothing.
    if (a !== null && b !== null && a !== undefined && b !== undefined) line[i] = a - b
  }
  const signal = ema(line, signalPeriod)
  const histogram: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const m = line[i]
    const g = signal[i]
    if (m !== null && g !== null && m !== undefined && g !== undefined) histogram[i] = m - g
  }
  return { macd: line, signal, histogram }
}

/** Stochastic RSI: the stochastic oscillator applied to the RSI series. */
export function stochRsi(
  c: Candle[],
  rsiPeriod = 14,
  stochPeriod = 14,
  smooth = 3,
): { k: Series; d: Series } {
  const r = rsi(c, rsiPeriod)
  const hh = highest(r, stochPeriod)
  const ll = lowest(r, stochPeriod)
  const raw: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const h = hh[i]
    const l = ll[i]
    const v = r[i]
    if (h === null || l === null || v === null || h === undefined || l === undefined || v === undefined) {
      continue
    }
    raw[i] = h === l ? 50 : clamp(((v - l) / (h - l)) * 100, 0, 100)
  }
  const k = clampSeries(sma(raw, smooth), 0, 100)
  return { k, d: clampSeries(sma(k, smooth), 0, 100) }
}

/** Bollinger Bands. */
export function bollinger(c: Candle[], n = 20, mult = 2) {
  const mid = sma(closes(c), n)
  const sd = stdev(closes(c), n)
  const upper: Series = new Array(c.length).fill(null)
  const lower: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const m = mid[i]
    const s = sd[i]
    if (m === null || s === null || m === undefined || s === undefined) continue
    upper[i] = m + mult * s
    lower[i] = m - mult * s
  }
  return { upper, mid, lower }
}

/** Donchian Channels. */
export function donchian(c: Candle[], n = 20) {
  const upper = highest(highs(c), n)
  const lower = lowest(lows(c), n)
  const mid: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const u = upper[i]
    const l = lower[i]
    if (u !== null && l !== null && u !== undefined && l !== undefined) mid[i] = (u + l) / 2
  }
  return { upper, mid, lower }
}

/** Keltner Channels: an EMA with ATR-scaled bands. */
export function keltner(c: Candle[], n = 20, mult = 2, atrPeriod = 10) {
  const mid = ema(closes(c), n)
  const a = atr(c, atrPeriod)
  const upper: Series = new Array(c.length).fill(null)
  const lower: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const m = mid[i]
    const av = a[i]
    if (m === null || av === null || m === undefined || av === undefined) continue
    upper[i] = m + mult * av
    lower[i] = m - mult * av
  }
  return { upper, mid, lower }
}

/** Midpoint of the highest high and lowest low, the Ichimoku building block. */
function donchianMid(c: Candle[], n: number): Series {
  const hh = highest(highs(c), n)
  const ll = lowest(lows(c), n)
  const out: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const h = hh[i]
    const l = ll[i]
    if (h !== null && l !== null && h !== undefined && l !== undefined) out[i] = (h + l) / 2
  }
  return out
}

export function ichimoku(c: Candle[], tenkanN = 9, kijunN = 26, senkouN = 52) {
  const tenkan = donchianMid(c, tenkanN)
  const kijun = donchianMid(c, kijunN)
  const senkouA: Series = new Array(c.length).fill(null)
  for (let i = 0; i < c.length; i++) {
    const t = tenkan[i]
    const k = kijun[i]
    if (t !== null && k !== null && t !== undefined && k !== undefined) senkouA[i] = (t + k) / 2
  }
  return { tenkan, kijun, senkouA, senkouB: donchianMid(c, senkouN), chikou: closes(c), kijunN }
}
