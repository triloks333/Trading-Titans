import {
  adx,
  atr,
  bollinger,
  cci,
  donchian,
  ema,
  ichimoku,
  keltner,
  macd,
  momentum,
  pivots,
  psar,
  roc,
  rsi,
  sma,
  stochRsi,
  stochastic,
  supertrend,
  williamsR,
  wma,
  type IndicatorPlot,
  type IndicatorResult,
  type LinePoint,
  type Series,
} from './indicators'
import { palette } from './theme'
import type { Candle, ThemeMode } from './types'

/*
 * The indicator catalogue.
 *
 * One entry per indicator, holding its label, its default parameters and a
 * `build` that turns candles into plots. Adding an indicator is one entry here
 * plus one function in `indicators.ts` — nothing in `chart.ts` or in either client
 * needs to learn about it, which is the point of the indirection.
 *
 * The UI reads `INDICATORS` to render its picker, so a new indicator appears in
 * both the web app and the app with no UI change.
 */

export type ParamKind = 'period' | 'multiplier'

export interface ParamSpec {
  key: string
  label: string
  kind: ParamKind
  default: number
  min: number
  max: number
}

export interface IndicatorSpec {
  id: string
  name: string
  /** Grouping for the picker. */
  group: 'Moving averages' | 'Bands & channels' | 'Trend' | 'Momentum' | 'Volatility'
  pane: 'price' | 'separate'
  params: ParamSpec[]
  build(candles: Candle[], params: Record<string, number>, mode: ThemeMode): IndicatorResult
}

const period = (key: string, label: string, def: number, min = 1, max = 400): ParamSpec => ({
  key,
  label,
  kind: 'period',
  default: def,
  min,
  max,
})

const mult = (key: string, label: string, def: number): ParamSpec => ({
  key,
  label,
  kind: 'multiplier',
  default: def,
  min: 0.1,
  max: 10,
})

/** Pairs a series with bar times, dropping the warm-up nulls. */
function points(candles: Candle[], s: Series): LinePoint[] {
  const out: LinePoint[] = []
  for (let i = 0; i < candles.length; i++) {
    const v = s[i]
    if (v !== null && v !== undefined && Number.isFinite(v)) {
      out.push({ time: candles[i]!.time, value: v })
    }
  }
  return out
}

function line(
  key: string,
  label: string,
  color: string,
  data: LinePoint[],
  lineWidth: 1 | 2 = 2,
): IndicatorPlot {
  return { key, label, color, style: 'line', lineWidth, data }
}

/**
 * A distinct colour per instance, so two EMAs are told apart at a glance.
 *
 * Picked from the app's palette rather than generated, because generated hues land
 * on the bull green and bear red and then a moving average reads as a signal.
 */
const CYCLE = ['#1A73E8', '#6D28D9', '#B8860B', '#0891B2', '#DB2777', '#65A30D']
export function cycleColor(i: number): string {
  return CYCLE[i % CYCLE.length]!
}

export const INDICATORS: IndicatorSpec[] = [
  // ── Moving averages ───────────────────────────────────────────────────────
  {
    id: 'sma',
    name: 'Simple MA',
    group: 'Moving averages',
    pane: 'price',
    params: [period('length', 'Length', 20)],
    build: (c, p) => ({
      id: 'sma',
      label: `SMA ${p.length}`,
      pane: 'price',
      plots: [line('sma', `SMA ${p.length}`, cycleColor(0), points(c, sma(c.map((x) => x.close), p.length!)))],
    }),
  },
  {
    id: 'ema',
    name: 'Exponential MA',
    group: 'Moving averages',
    pane: 'price',
    params: [period('length', 'Length', 21)],
    build: (c, p) => ({
      id: 'ema',
      label: `EMA ${p.length}`,
      pane: 'price',
      plots: [line('ema', `EMA ${p.length}`, cycleColor(1), points(c, ema(c.map((x) => x.close), p.length!)))],
    }),
  },
  {
    id: 'wma',
    name: 'Weighted MA',
    group: 'Moving averages',
    pane: 'price',
    params: [period('length', 'Length', 20)],
    build: (c, p) => ({
      id: 'wma',
      label: `WMA ${p.length}`,
      pane: 'price',
      plots: [line('wma', `WMA ${p.length}`, cycleColor(2), points(c, wma(c.map((x) => x.close), p.length!)))],
    }),
  },

  // ── Bands & channels ──────────────────────────────────────────────────────
  {
    id: 'bollinger',
    name: 'Bollinger Bands',
    group: 'Bands & channels',
    pane: 'price',
    params: [period('length', 'Length', 20), mult('mult', 'Std dev', 2)],
    build: (c, p, mode) => {
      const b = bollinger(c, p.length!, p.mult!)
      const col = palette(mode)
      return {
        id: 'bollinger',
        label: `BB ${p.length}, ${p.mult}`,
        pane: 'price',
        plots: [
          line('bb.u', 'Upper', col.accent, points(c, b.upper), 1),
          line('bb.m', 'Basis', col.textMuted, points(c, b.mid), 1),
          line('bb.l', 'Lower', col.accent, points(c, b.lower), 1),
        ],
      }
    },
  },
  {
    id: 'donchian',
    name: 'Donchian Channels',
    group: 'Bands & channels',
    pane: 'price',
    params: [period('length', 'Length', 20)],
    build: (c, p, mode) => {
      const d = donchian(c, p.length!)
      const col = palette(mode)
      return {
        id: 'donchian',
        label: `Donchian ${p.length}`,
        pane: 'price',
        plots: [
          line('dc.u', 'Upper', col.up, points(c, d.upper), 1),
          line('dc.m', 'Basis', col.textMuted, points(c, d.mid), 1),
          line('dc.l', 'Lower', col.down, points(c, d.lower), 1),
        ],
      }
    },
  },
  {
    id: 'pivots',
    name: 'Pivot Points',
    group: 'Bands & channels',
    pane: 'price',
    // No parameters: classic pivots are defined by a formula, not tuned. Offering a
    // "length" would imply a choice that does not exist.
    params: [],
    build: (c, _p, mode) => {
      const v = pivots(c)
      const col = palette(mode)
      return {
        id: 'pivots',
        label: 'Pivots',
        pane: 'price',
        plots: [
          // Resistance in the falling colour and support in the rising one, so the
          // side of the market each level belongs to is readable without the label.
          line('pv.r3', 'R3', col.down, points(c, v.r3), 1),
          line('pv.r2', 'R2', col.down, points(c, v.r2), 1),
          line('pv.r1', 'R1', col.down, points(c, v.r1), 1),
          line('pv.pp', 'PP', col.textMuted, points(c, v.pp), 2),
          line('pv.s1', 'S1', col.up, points(c, v.s1), 1),
          line('pv.s2', 'S2', col.up, points(c, v.s2), 1),
          line('pv.s3', 'S3', col.up, points(c, v.s3), 1),
        ],
      }
    },
  },
  {
    id: 'keltner',
    name: 'Keltner Channels',
    group: 'Bands & channels',
    pane: 'price',
    params: [period('length', 'Length', 20), mult('mult', 'ATR mult', 2), period('atr', 'ATR length', 10)],
    build: (c, p, mode) => {
      const k = keltner(c, p.length!, p.mult!, p.atr!)
      const col = palette(mode)
      return {
        id: 'keltner',
        label: `Keltner ${p.length}, ${p.mult}`,
        pane: 'price',
        plots: [
          line('kc.u', 'Upper', '#0891B2', points(c, k.upper), 1),
          line('kc.m', 'Basis', col.textMuted, points(c, k.mid), 1),
          line('kc.l', 'Lower', '#0891B2', points(c, k.lower), 1),
        ],
      }
    },
  },

  // ── Trend ─────────────────────────────────────────────────────────────────
  {
    id: 'psar',
    name: 'Parabolic SAR',
    group: 'Trend',
    pane: 'price',
    params: [mult('step', 'Step', 0.02), mult('max', 'Max', 0.2)],
    build: (c, p) => ({
      id: 'psar',
      label: `PSAR ${p.step}, ${p.max}`,
      pane: 'price',
      plots: [
        // Dots, not a line: SAR jumps sides on a reversal, and joining those two
        // points draws a vertical stroke through the candles that means nothing.
        { key: 'psar', label: 'PSAR', color: '#6D28D9', style: 'dots', data: points(c, psar(c, p.step!, p.max!)) },
      ],
    }),
  },
  {
    id: 'supertrend',
    name: 'Supertrend',
    group: 'Trend',
    pane: 'price',
    params: [period('length', 'ATR length', 10), mult('mult', 'Multiplier', 3)],
    build: (c, p, mode) => {
      const st = supertrend(c, p.length!, p.mult!)
      const col = palette(mode)
      // Split into two series so the colour follows the trend. One series cannot
      // change colour mid-line, and a single-colour Supertrend loses its point.
      const upPts: LinePoint[] = []
      const downPts: LinePoint[] = []
      for (let i = 0; i < c.length; i++) {
        const v = st.line[i]
        if (v === null || v === undefined) continue
        ;(st.rising[i] ? upPts : downPts).push({ time: c[i]!.time, value: v })
      }
      return {
        id: 'supertrend',
        label: `Supertrend ${p.length}, ${p.mult}`,
        pane: 'price',
        plots: [
          line('st.up', 'Up', col.up, upPts),
          line('st.down', 'Down', col.down, downPts),
        ],
      }
    },
  },
  {
    id: 'ichimoku',
    name: 'Ichimoku Cloud',
    group: 'Trend',
    pane: 'price',
    params: [
      period('tenkan', 'Conversion', 9),
      period('kijun', 'Base', 26),
      period('senkou', 'Span B', 52),
    ],
    build: (c, p) => {
      const ich = ichimoku(c, p.tenkan!, p.kijun!, p.senkou!)
      // Span A and B are projected forward by the base period; Chikou lags by it.
      const fwd = (s: Series) => shift(c, s, p.kijun!)
      return {
        id: 'ichimoku',
        label: `Ichimoku ${p.tenkan}, ${p.kijun}, ${p.senkou}`,
        pane: 'price',
        plots: [
          line('ich.tenkan', 'Conversion', '#1A73E8', points(c, ich.tenkan), 1),
          line('ich.kijun', 'Base', '#DB2777', points(c, ich.kijun), 1),
          line('ich.senkouA', 'Span A', '#0F9D58', fwd(ich.senkouA), 1),
          line('ich.senkouB', 'Span B', '#D93025', fwd(ich.senkouB), 1),
          line('ich.chikou', 'Lagging', '#B8860B', shift(c, ich.chikou, -p.kijun!), 1),
        ],
      }
    },
  },

  // ── Momentum ──────────────────────────────────────────────────────────────
  {
    id: 'rsi',
    name: 'RSI',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 14)],
    build: (c, p) => ({
      id: 'rsi',
      label: `RSI ${p.length}`,
      pane: 'separate',
      levels: [30, 70],
      range: [0, 100],
      plots: [line('rsi', `RSI ${p.length}`, '#6D28D9', points(c, rsi(c, p.length!)))],
    }),
  },
  {
    id: 'macd',
    name: 'MACD',
    group: 'Momentum',
    pane: 'separate',
    params: [period('fast', 'Fast', 12), period('slow', 'Slow', 26), period('signal', 'Signal', 9)],
    build: (c, p, mode) => {
      const m = macd(c, p.fast!, p.slow!, p.signal!)
      const col = palette(mode)
      const hist = points(c, m.histogram)
      return {
        id: 'macd',
        label: `MACD ${p.fast}, ${p.slow}, ${p.signal}`,
        pane: 'separate',
        levels: [0],
        plots: [
          {
            key: 'macd.hist',
            label: 'Histogram',
            color: col.up,
            style: 'histogram',
            data: hist,
            colors: hist.map((h) => (h.value >= 0 ? `${col.up}99` : `${col.down}99`)),
          },
          line('macd.line', 'MACD', '#1A73E8', points(c, m.macd)),
          line('macd.signal', 'Signal', '#DB2777', points(c, m.signal), 1),
        ],
      }
    },
  },
  {
    id: 'stochastic',
    name: 'Stochastic',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 14), period('smooth', 'Smoothing', 3)],
    build: (c, p) => {
      const s = stochastic(c, p.length!, p.smooth!)
      return {
        id: 'stochastic',
        label: `Stoch ${p.length}, ${p.smooth}`,
        pane: 'separate',
        levels: [20, 80],
        range: [0, 100],
        plots: [
          line('stoch.k', '%K', '#1A73E8', points(c, s.k)),
          line('stoch.d', '%D', '#DB2777', points(c, s.d), 1),
        ],
      }
    },
  },
  {
    id: 'stochrsi',
    name: 'Stochastic RSI',
    group: 'Momentum',
    pane: 'separate',
    params: [period('rsi', 'RSI length', 14), period('stoch', 'Stoch length', 14), period('smooth', 'Smoothing', 3)],
    build: (c, p) => {
      const s = stochRsi(c, p.rsi!, p.stoch!, p.smooth!)
      return {
        id: 'stochrsi',
        label: `Stoch RSI ${p.rsi}`,
        pane: 'separate',
        levels: [20, 80],
        range: [0, 100],
        plots: [
          line('srsi.k', '%K', '#0891B2', points(c, s.k)),
          line('srsi.d', '%D', '#DB2777', points(c, s.d), 1),
        ],
      }
    },
  },
  {
    id: 'williams',
    name: 'Williams %R',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 14)],
    build: (c, p) => ({
      id: 'williams',
      label: `Williams %R ${p.length}`,
      pane: 'separate',
      levels: [-20, -80],
      range: [-100, 0],
      plots: [line('wr', `%R ${p.length}`, '#B8860B', points(c, williamsR(c, p.length!)))],
    }),
  },
  {
    id: 'cci',
    name: 'CCI',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 20)],
    build: (c, p) => ({
      id: 'cci',
      label: `CCI ${p.length}`,
      pane: 'separate',
      levels: [-100, 0, 100],
      plots: [line('cci', `CCI ${p.length}`, '#0891B2', points(c, cci(c, p.length!)))],
    }),
  },
  {
    id: 'roc',
    name: 'Rate of Change',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 12)],
    build: (c, p) => ({
      id: 'roc',
      label: `ROC ${p.length}`,
      pane: 'separate',
      levels: [0],
      plots: [line('roc', `ROC ${p.length}`, '#65A30D', points(c, roc(c, p.length!)))],
    }),
  },
  {
    id: 'momentum',
    name: 'Momentum',
    group: 'Momentum',
    pane: 'separate',
    params: [period('length', 'Length', 10)],
    build: (c, p) => ({
      id: 'momentum',
      label: `Momentum ${p.length}`,
      pane: 'separate',
      levels: [0],
      plots: [line('mom', `Mom ${p.length}`, '#DB2777', points(c, momentum(c, p.length!)))],
    }),
  },

  // ── Volatility ────────────────────────────────────────────────────────────
  {
    id: 'atr',
    name: 'ATR',
    group: 'Volatility',
    pane: 'separate',
    params: [period('length', 'Length', 14)],
    build: (c, p) => ({
      id: 'atr',
      label: `ATR ${p.length}`,
      pane: 'separate',
      plots: [line('atr', `ATR ${p.length}`, '#B8860B', points(c, atr(c, p.length!)))],
    }),
  },
  {
    id: 'adx',
    name: 'ADX / DMI',
    group: 'Trend',
    pane: 'separate',
    params: [period('length', 'Length', 14)],
    build: (c, p, mode) => {
      const a = adx(c, p.length!)
      const col = palette(mode)
      return {
        id: 'adx',
        label: `ADX ${p.length}`,
        pane: 'separate',
        // 25 is the conventional line between trending and ranging.
        levels: [25],
        plots: [
          line('adx', 'ADX', col.text, points(c, a.adx)),
          line('adx.plus', '+DI', col.up, points(c, a.plusDi), 1),
          line('adx.minus', '−DI', col.down, points(c, a.minusDi), 1),
        ],
      }
    },
  },
]

/**
 * Shifts a series along the time axis. Positive is forward (Ichimoku's cloud),
 * negative is backward (its lagging span).
 *
 * Forward needs bar times that do not exist yet, extrapolated from the MEDIAN
 * spacing of the existing bars. Median rather than mean because weekends and
 * trading holidays would drag a mean and land the projection on the wrong days.
 *
 * ponytail: even spacing means a daily projection sits on calendar days including
 * weekends. The ceiling is a few misplaced days at the extreme right edge; the
 * upgrade path is a session calendar, which is a lot of machinery for the leading
 * edge of one indicator.
 */
function shift(candles: Candle[], s: Series, by: number): LinePoint[] {
  if (candles.length === 0) return []
  if (by === 0) return points(candles, s)

  const deltas: number[] = []
  for (let i = 1; i < candles.length; i++) deltas.push(candles[i]!.time - candles[i - 1]!.time)
  deltas.sort((a, b) => a - b)
  const step = deltas[Math.floor(deltas.length / 2)] ?? 0
  const lastTime = candles[candles.length - 1]!.time

  const out: LinePoint[] = []
  for (let i = 0; i < candles.length; i++) {
    const v = s[i]
    if (v === null || v === undefined || !Number.isFinite(v)) continue
    const target = i + by
    if (target < 0) continue
    const time =
      target < candles.length
        ? candles[target]!.time
        : lastTime + (target - candles.length + 1) * step
    out.push({ time, value: v })
  }
  return out
}

export const INDICATOR_BY_ID = new Map(INDICATORS.map((i) => [i.id, i]))

export function defaultParams(spec: IndicatorSpec): Record<string, number> {
  return Object.fromEntries(spec.params.map((p) => [p.key, p.default]))
}
