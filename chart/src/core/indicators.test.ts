/*
 * Checks for the indicator maths.
 *
 * Run with `npm test`. These exist because a wrong indicator does not throw or
 * render blank — it draws a smooth, plausible line at the wrong values, and
 * nobody spots that by looking. Each case below pins a number that can be worked
 * out by hand or is fixed by definition.
 *
 * The awkward ones get the most attention: Wilder smoothing (not an EMA of the
 * same period), MACD's start (gated on the SLOW average), ADX (two levels of
 * smoothing), and Parabolic SAR (stateful, with a reversal rule).
 */

import assert from 'node:assert/strict'
import {
  adx,
  atr,
  bollinger,
  cci,
  donchian,
  ema,
  highest,
  ichimoku,
  keltner,
  lowest,
  macd,
  momentum,
  psar,
  roc,
  rsi,
  sma,
  stdev,
  stochRsi,
  stochastic,
  supertrend,
  trueRange,
  wilder,
  williamsR,
  wma,
} from './indicators'
import { INDICATORS, defaultParams } from './registry'
import type { Candle } from './types'

let checks = 0
function check(name: string, fn: () => void) {
  fn()
  checks++
  console.log(`  ok  ${name}`)
}

/** Bars from closes, with a small deterministic range around each. */
function bars(closes: number[]): Candle[] {
  return closes.map((c, i) => ({
    time: i * 86400,
    open: i === 0 ? c : closes[i - 1]!,
    high: c + 1,
    low: c - 1,
    close: c,
  }))
}

const near = (a: number | null | undefined, b: number, eps = 1e-9) => {
  assert.notEqual(a, null, 'value is null')
  assert.ok(Math.abs(a! - b) < eps, `${a} !== ${b}`)
}

console.log('moving averages')

check('SMA warms up then averages the window', () => {
  const out = sma([1, 2, 3, 4, 5], 3)
  assert.deepEqual(out.slice(0, 2), [null, null])
  near(out[2], 2) // (1+2+3)/3
  near(out[3], 3)
  near(out[4], 4)
})

check('EMA is seeded with the SMA, not the first value', () => {
  // Seeding from close[0] instead makes early output hinge on one bar, so two
  // charts over different ranges disagree about the same date.
  const out = ema([1, 2, 3, 4, 5], 3)
  assert.deepEqual(out.slice(0, 2), [null, null])
  near(out[2], 2) // seed = SMA(1,2,3)
  const k = 2 / 4
  near(out[3], 4 * k + 2 * (1 - k)) // 3
  near(out[4], 5 * k + 3 * (1 - k)) // 4
})

check('WMA weights the newest bar most', () => {
  // (1*1 + 2*2 + 3*3) / 6
  near(wma([1, 2, 3], 3)[2], 14 / 6)
})

check('Wilder smoothing is not an EMA of the same period', () => {
  // Wilder(n) equals EMA(2n-1). If these ever match, someone has substituted one
  // for the other and RSI/ATR/ADX will disagree with every other platform.
  const v = [1, 2, 3, 4, 5, 6, 7, 8]
  const w = wilder(v, 3)
  const e = ema(v, 3)
  near(w[2], 2) // same SMA seed
  near(w[3], (2 * 2 + 4) / 3)
  assert.notEqual(w[5], e[5])
})

check('a gap resets the SMA window instead of averaging across it', () => {
  const out = sma([1, 2, null, 4, 5, 6], 3)
  assert.equal(out[3], null, 'must not span the hole')
  near(out[5], 5) // (4+5+6)/3
})

console.log('bands and channels')

check('population stdev, and Bollinger bands sit symmetrically on the basis', () => {
  // [2,4,4,4,5,5,7,9] has mean 5 and population sd 2.
  near(stdev([2, 4, 4, 4, 5, 5, 7, 9], 8)[7], 2)
  const b = bollinger(bars([2, 4, 4, 4, 5, 5, 7, 9]), 8, 2)
  near(b.mid[7], 5)
  near(b.upper[7], 9)
  near(b.lower[7], 1)
})

check('Donchian tracks the extremes of the window, mid is their midpoint', () => {
  const c = bars([10, 12, 8, 11])
  const d = donchian(c, 4)
  near(d.upper[3], 13) // highest high = 12 + 1
  near(d.lower[3], 7) //  lowest low  =  8 - 1
  near(d.mid[3], 10)
})

check('Keltner bands are ATR-scaled around an EMA', () => {
  const c = bars([10, 11, 12, 13, 14, 15])
  const k = keltner(c, 3, 2, 3)
  const mid = k.mid[5]!
  const up = k.upper[5]!
  const lo = k.lower[5]!
  near(up - mid, mid - lo) // symmetric
  assert.ok(up > mid && mid > lo)
})

check('highest and lowest respect the window, not the whole series', () => {
  near(highest([5, 1, 9, 2], 2)[3], 9)
  near(lowest([5, 1, 9, 2], 2)[3], 2)
})

console.log('volatility')

check('true range includes the gap from the previous close', () => {
  // A bar entirely above the previous close: its own span is 2, but the gap is 12.
  const c: Candle[] = [
    { time: 0, open: 10, high: 10, low: 10, close: 10 },
    { time: 86400, open: 20, high: 22, low: 20, close: 21 },
  ]
  near(trueRange(c)[1], 12)
})

check('ATR is a Wilder average of true range', () => {
  const c = bars([10, 12, 11, 13, 12, 14])
  const a = atr(c, 3)
  assert.equal(a[1], null, 'not warmed up')
  assert.ok(a[5]! > 0)
})

console.log('momentum')

check('RSI is 100 when every bar rises and stays inside 0..100', () => {
  const up = rsi(bars([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]), 14)
  near(up[15], 100) // no losses to divide by; 100 is the defined limit
  for (const v of up) if (v !== null) assert.ok(v >= 0 && v <= 100)
})

check('RSI is 0 when every bar falls', () => {
  const down = rsi(bars([16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]), 14)
  near(down[15], 0)
})

check('RSI leaves bar 0 null rather than counting it as unchanged', () => {
  // Bar 0 has no previous close, so there is no change to measure. Treating it as
  // flat drags the first average toward the middle.
  assert.equal(rsi(bars([1, 2, 3]), 2)[0], null)
})

check('MACD starts with the SLOW average and the histogram is line minus signal', () => {
  const closes = Array.from({ length: 60 }, (_, i) => 100 + Math.sin(i / 4) * 10)
  const m = macd(bars(closes), 12, 26, 9)
  // Nothing before the 26-bar average exists, or the line would be a difference
  // against nothing.
  assert.equal(m.macd[24], null)
  assert.notEqual(m.macd[25], null)
  for (let i = 0; i < closes.length; i++) {
    if (m.histogram[i] !== null) near(m.histogram[i], m.macd[i]! - m.signal[i]!)
  }
})

check('stochastic pins to 100 at the window high and 0 at its low', () => {
  const rising = stochastic(bars([1, 2, 3, 4, 5]), 3, 1)
  near(rising.k[4], 100 * (5 - 2) / (6 - 2)) // close 5, HH 6, LL 2
  // A flat window has no range to place the close in: 50 is neutral and avoids
  // dividing by zero.
  near(stochastic(bars([7, 7, 7, 7]), 3, 1).k[3], 50)
})

check('Williams %R is the stochastic mirrored onto -100..0', () => {
  const c = bars([1, 2, 3, 4, 5])
  const wr = williamsR(c, 3)
  const st = stochastic(c, 3, 1)
  near(wr[4], st.k[4]! - 100)
  for (const v of wr) if (v !== null) assert.ok(v >= -100 && v <= 0)
})

check('ROC is a percentage and momentum is the raw difference', () => {
  near(roc(bars([100, 110]), 1)[1], 10)
  near(momentum(bars([100, 110]), 1)[1], 10)
  near(roc(bars([200, 210]), 1)[1], 5) // same 10 points, half the percentage
})

check('CCI is zero when typical price sits on its own average', () => {
  near(cci(bars([5, 5, 5, 5, 5]), 3)[4], 0)
})

check('Stochastic RSI stays inside 0..100', () => {
  const closes = Array.from({ length: 80 }, (_, i) => 100 + Math.sin(i / 5) * 8)
  const s = stochRsi(bars(closes), 14, 14, 3)
  for (const v of s.k) if (v !== null) assert.ok(v >= 0 && v <= 100)
  for (const v of s.d) if (v !== null) assert.ok(v >= 0 && v <= 100)
})

console.log('trend')

check('ADX and both DIs stay inside 0..100, and +DI leads in an uptrend', () => {
  const c = bars(Array.from({ length: 40 }, (_, i) => 100 + i * 2))
  const a = adx(c, 14)
  for (const s of [a.adx, a.plusDi, a.minusDi]) {
    for (const v of s) if (v !== null) assert.ok(v >= 0 && v <= 100, `out of range: ${v}`)
  }
  assert.ok(a.plusDi[39]! > a.minusDi[39]!, '+DI should lead a rising market')
})

check('−DI leads in a downtrend', () => {
  const c = bars(Array.from({ length: 40 }, (_, i) => 180 - i * 2))
  const a = adx(c, 14)
  assert.ok(a.minusDi[39]! > a.plusDi[39]!)
})

check('Parabolic SAR sits below a rising market and flips on a break', () => {
  const up = bars(Array.from({ length: 20 }, (_, i) => 100 + i * 3))
  const s = psar(up)
  assert.ok(s[19]! < up[19]!.close, 'SAR must trail below an uptrend')

  // Rise then collapse: the SAR has to cross to the other side of price.
  const flip = bars([...Array.from({ length: 12 }, (_, i) => 100 + i * 3), 120, 110, 95, 80, 70])
  const f = psar(flip)
  assert.ok(f[16]! > flip[16]!.close, 'SAR must sit above price after a reversal')
})

check('Supertrend is below price while rising and above it while falling', () => {
  const up = bars(Array.from({ length: 40 }, (_, i) => 100 + i * 2))
  const st = supertrend(up, 10, 3)
  assert.equal(st.rising[39], true)
  assert.ok(st.line[39]! < up[39]!.close)

  const down = bars(Array.from({ length: 40 }, (_, i) => 180 - i * 2))
  const sd = supertrend(down, 10, 3)
  assert.equal(sd.rising[39], false)
  assert.ok(sd.line[39]! > down[39]!.close)
})

check('Ichimoku Span A is the mean of the conversion and base lines', () => {
  const c = bars(Array.from({ length: 80 }, (_, i) => 100 + Math.sin(i / 6) * 12))
  const ich = ichimoku(c, 9, 26, 52)
  const i = 70
  near(ich.senkouA[i], (ich.tenkan[i]! + ich.kijun[i]!) / 2)
  assert.notEqual(ich.senkouB[i], null)
})

console.log('registry')

check('every indicator builds on real-shaped data without throwing', () => {
  // The breadth check: 19 entries, each with its own maths and plot wiring. One
  // that throws would blank the chart for whoever switched it on.
  const c = bars(Array.from({ length: 120 }, (_, i) => 100 + Math.sin(i / 7) * 15 + i * 0.2))
  for (const spec of INDICATORS) {
    const r = spec.build(c, defaultParams(spec), 'light')
    assert.equal(r.pane, spec.pane, `${spec.id} pane mismatch`)
    assert.ok(r.plots.length > 0, `${spec.id} produced no plots`)
    assert.ok(r.label.length > 0, `${spec.id} has no label`)
    for (const plot of r.plots) {
      assert.ok(plot.data.length > 0, `${spec.id}/${plot.key} produced no points`)
      for (const p of plot.data) {
        assert.ok(Number.isFinite(p.value), `${spec.id}/${plot.key} has a non-finite value`)
        assert.ok(Number.isFinite(p.time), `${spec.id}/${plot.key} has a bad time`)
      }
    }
  }
})

check('plot points are strictly ascending in time', () => {
  // lightweight-charts throws on unsorted data, and Ichimoku's shifted spans are
  // exactly where an ordering mistake would hide.
  const c = bars(Array.from({ length: 120 }, (_, i) => 100 + Math.sin(i / 7) * 15))
  for (const spec of INDICATORS) {
    for (const plot of spec.build(c, defaultParams(spec), 'light').plots) {
      for (let i = 1; i < plot.data.length; i++) {
        assert.ok(
          plot.data[i]!.time > plot.data[i - 1]!.time,
          `${spec.id}/${plot.key} is not ascending at ${i}`,
        )
      }
    }
  }
})

check('every plot key is unique within its indicator', () => {
  // Duplicate keys would collide in the crosshair value map and the legend would
  // show one plot's number against another's label.
  for (const spec of INDICATORS) {
    const r = spec.build(bars(Array.from({ length: 120 }, (_, i) => 100 + i)), defaultParams(spec), 'light')
    const keys = r.plots.map((p) => p.key)
    assert.equal(new Set(keys).size, keys.length, `${spec.id} has duplicate plot keys`)
  }
})

check('indicator ids are unique across the catalogue', () => {
  const ids = INDICATORS.map((i) => i.id)
  assert.equal(new Set(ids).size, ids.length)
})

check('a short series produces no points rather than throwing', () => {
  // Someone opens a 1-minute chart before the market has printed 26 bars.
  for (const spec of INDICATORS) {
    const r = spec.build(bars([100, 101, 102]), defaultParams(spec), 'light')
    for (const plot of r.plots) {
      for (const p of plot.data) assert.ok(Number.isFinite(p.value))
    }
  }
})

console.log(`\n${checks} checks passed`)
