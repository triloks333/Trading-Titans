import {
  AreaSeries,
  CandlestickSeries,
  CrosshairMode,
  HistogramSeries,
  LineSeries,
  LineStyle,
  TickMarkType,
  createChart,
  createTextWatermark,
  type IChartApi,
  type ISeriesApi,
  type SeriesType,
  type Time,
  type UTCTimestamp,
} from 'lightweight-charts'

import { CURRENCY_SYMBOL, FONT_NUM, palette } from './theme'
import { TIMEFRAME_SECONDS, mergeTick } from './aggregate'
import { createBrandBadge, paneTitleOptions, watermarkOptions } from './brand'
import { createDrawingLayer, type DrawingLayer } from './drawings'
import type { IndicatorResult } from './indicators'
import type {
  Candle,
  Currency,
  Sample,
  SeriesStyle,
  ThemeMode,
  Timeframe,
} from './types'

/*
 * The chart. One implementation, no framework.
 *
 * Nothing here imports React, and nothing knows it might be inside a WebView.
 * That is the point: the web app wraps it in a component and the Flutter client
 * loads it as a bundled asset, and both get identical behaviour. The chart this
 * replaces existed three times over — a TradingView embed on Android,
 * `interactive_chart` on Flutter web, `lightweight-charts` in the React app — and
 * the three disagreed about prices, styling and which symbol was even shown.
 *
 * It draws what it is given and fetches nothing; fetching lives in `src/data`.
 * It is also strictly read-only about prices and must never become a second
 * opinion on what something costs: `quotes_cache` is what the matching engine
 * fills from, and this is a view downstream of it.
 *
 * PANES
 * Overlays (moving averages, bands, SAR) go on pane 0 with the candles.
 * Oscillators (RSI, MACD, ADX) each get their own pane via v5's `addSeries(...,
 * paneIndex)`. Panes are torn down and rebuilt whenever the indicator set changes,
 * because lightweight-charts has no way to reorder them and an incremental update
 * leaves empty panes behind.
 */

export interface HoverState {
  bar: Candle | null
  /** Indicator plot values at the hovered bar, keyed by plot key. */
  values: Map<string, number>
}

export interface LegendRow {
  label: string
  vals: { color: string; v: number }[]
}

/**
 * Indicator values at the crosshair, or the latest bar's when not hovering.
 *
 * Lives here rather than in either client because both need it and it is the same
 * reading either way: the web app renders these rows as chips under the chart and
 * the WebView renders them as chips above it. Two copies would drift the moment an
 * indicator gained a plot.
 */
export function readLegend(results: IndicatorResult[], state: HoverState): LegendRow[] {
  const rows: LegendRow[] = []
  for (const r of results) {
    const vals: { color: string; v: number }[] = []
    for (const plot of r.plots) {
      const v = state.values.get(plot.key) ?? plot.data[plot.data.length - 1]?.value
      if (v === undefined) continue
      vals.push({ color: plot.color, v })
    }
    if (vals.length > 0) rows.push({ label: r.label, vals })
  }
  return rows
}

/**
 * A legend number narrow enough to sit in a chip.
 *
 * Significant digits rather than a fixed width: an RSI at 54.31 and a stochastic
 * at 0.0042 both need to be readable, and 54.3100 wastes the space that a phone
 * does not have.
 */
export function compactValue(v: number): string {
  const a = Math.abs(v)
  if (a >= 1000) return v.toFixed(1)
  if (a >= 1) return v.toFixed(2)
  return v.toFixed(4)
}

export interface TitanChartOptions {
  mode?: ThemeMode
  style?: SeriesStyle
  currency?: Currency
  timeframe?: Timeframe
  /** Text under the watermark wordmark, normally the instrument. */
  subtitle?: string
  /** Fires on crosshair move, and with a null bar when the pointer leaves. */
  onHover?: (state: HoverState) => void
}

export interface TitanChart {
  /** Replaces the whole series. Use on symbol or timeframe change. */
  setCandles(candles: Candle[]): void
  /**
   * Folds a live price into the bar in progress.
   *
   * This is the live edge: pass `quotes_cache.price` and the right-hand side of
   * the chart tracks the exact number the engine is filling at.
   */
  pushTick(tick: Sample): void
  /** Replaces every indicator. Panes are rebuilt to match. */
  setIndicators(results: IndicatorResult[]): void
  setStyle(style: SeriesStyle): void
  setMode(mode: ThemeMode): void
  setCurrency(currency: Currency): void
  setSubtitle(subtitle: string): void
  /** Only affects live-tick bucketing; the caller refetches the series itself. */
  setTimeframe(tf: Timeframe): void
  lastBar(): Candle | null
  /**
   * The series as the chart holds it, live ticks included.
   *
   * Exposed so callers never keep a parallel copy. The harness did, and it
   * desynced the moment a tick opened a new bar rather than extending the last:
   * the legend read a stale close while the badge read the live one, from two
   * arrays meant to be the same data.
   */
  bars(): readonly Candle[]
  fitContent(): void
  /** Trendlines and horizontal levels. See core/drawings.ts. */
  drawings(): DrawingLayer
  destroy(): void
}

/** lightweight-charts wants branded seconds. One cast, in one place. */
const asTime = (s: number) => s as UTCTimestamp

/**
 * Decimal places for the price axis, derived from the data rather than fixed at 2.
 * The same chart draws RELIANCE near 1,400 and SHIB near 0.00002, and a fixed 2
 * flattens a whole class of instruments into a row of zeroes.
 */
function precisionFor(candles: Candle[]): number {
  if (candles.length === 0) return 2
  let min = Infinity
  for (const c of candles) if (c.low > 0 && c.low < min) min = c.low
  if (!Number.isFinite(min)) return 2
  if (min >= 1) return 2
  if (min >= 0.01) return 4
  return 8
}

export function createTitanChart(
  container: HTMLElement,
  options: TitanChartOptions = {},
): TitanChart {
  let mode: ThemeMode = options.mode ?? 'light'
  let style: SeriesStyle = options.style ?? 'candles'
  let currency: Currency = options.currency ?? 'INR'
  let timeframe: Timeframe = options.timeframe ?? '1d'
  let subtitle = options.subtitle ?? ''
  let candles: Candle[] = []
  let indicators: IndicatorResult[] = []
  let precision = 2

  // The badge needs a positioned ancestor, and the container is the caller's.
  if (getComputedStyle(container).position === 'static') container.style.position = 'relative'

  const chart: IChartApi = createChart(container, { autoSize: true, ...layoutFor() })

  let priceSeries: ISeriesApi<'Candlestick'> | ISeriesApi<'Area'> = buildPriceSeries()
  /** Every indicator series, so they can all be removed on a rebuild. */
  let indicatorSeries: ISeriesApi<SeriesType>[] = []
  /** Plot key to its series, for reading values at the crosshair. */
  let plotSeries = new Map<string, ISeriesApi<SeriesType>>()

  // Reads `priceSeries` through a closure rather than being handed it, because the
  // series is torn down and rebuilt on every style, mode and precision change. A
  // captured reference would go stale and drawings would silently stop placing.
  const drawings = createDrawingLayer(container, chart, () => priceSeries, mode)

  let watermark = createTextWatermark(chart.panes()[0]!, watermarkOptions(mode, subtitle))
  let badge = createBrandBadge(mode)
  container.append(badge)

  /** One title watermark per study pane, torn down with its pane on a rebuild. */
  let paneTitles: { detach(): void }[] = []

  function layoutFor() {
    const p = palette(mode)
    return {
      layout: {
        background: { color: p.background },
        textColor: p.textMuted,
        // Ours, not theirs. Apache-2.0 does not oblige a visible mark, and the
        // branding on this chart is Trading Titans'.
        attributionLogo: false,
        // Monospaced, because every string lightweight-charts draws is a number:
        // axis ticks, the crosshair labels, the last-price badge. Proportional
        // digits make that column shimmer as the last bar updates.
        fontFamily: FONT_NUM,
        fontSize: 11,
        panes: { separatorColor: p.border, separatorHoverColor: p.accent, enableResize: true },
      },
      grid: {
        // Horizontal only. Vertical lines add nothing a price chart needs — the
        // time axis already marks the intervals — and at 250 bars they turn the
        // pane into graph paper that the candles have to compete with.
        vertLines: { visible: false },
        horzLines: { color: p.gridLine, style: LineStyle.Solid },
      },
      crosshair: {
        // Magnet snaps to the nearest bar, which on a touch screen is the
        // difference between reading a price and guessing at one.
        mode: CrosshairMode.Magnet,
        vertLine: {
          color: p.crosshair,
          width: 1 as const,
          style: LineStyle.Dashed,
          labelBackgroundColor: p.accent,
        },
        horzLine: {
          color: p.crosshair,
          width: 1 as const,
          style: LineStyle.Dashed,
          labelBackgroundColor: p.accent,
        },
      },
      rightPriceScale: {
        borderColor: p.border,
        // Just enough headroom to clear the brand badge, which is about 28px, plus
        // a little at the bottom so the last-price badge never sits on the pane
        // separator. Study panes override this — see the note in paintIndicators.
        scaleMargins: { top: 0.1, bottom: 0.1 },
      },
      timeScale: {
        borderColor: p.border,
        // Intraday needs the clock; a daily chart does not.
        timeVisible: TIMEFRAME_SECONDS[timeframe] < TIMEFRAME_SECONDS['1d'],
        secondsVisible: false,
        // Room to the right of the newest bar so the live candle is not jammed
        // against the axis, and so an Ichimoku projection has somewhere to go.
        rightOffset: 8,
        barSpacing: 9,
        minBarSpacing: 0.6,
        tickMarkFormatter: (t: Time, type: TickMarkType) =>
          clock(
            t,
            type === TickMarkType.Year
              ? { year: 'numeric' }
              : type === TickMarkType.Month
                ? { month: 'short' }
                : type === TickMarkType.DayOfMonth
                  ? { day: 'numeric' }
                  : { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' },
          ),
      },
      localization: {
        // The crosshair's time label.
        timeFormatter: (t: Time) =>
          clock(
            t,
            TIMEFRAME_SECONDS[timeframe] < TIMEFRAME_SECONDS['1d']
              ? { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }
              : { day: 'numeric', month: 'short', year: '2-digit' },
          ),
      },
    }
  }

  /**
   * A bar time in the reader's own clock.
   *
   * lightweight-charts labels in UTC, which put 17:00 under a 22:30 IST candle.
   * Intraday uses the device's zone, so it is IST in India and local time for
   * anyone abroad. Daily and coarser bars stay in UTC: they are stamped at UTC
   * midnight, and a zone behind UTC would label each day with the day before.
   */
  function clock(t: Time, opts: Intl.DateTimeFormatOptions): string {
    const intraday = TIMEFRAME_SECONDS[timeframe] < TIMEFRAME_SECONDS['1d']
    return new Date((t as number) * 1000).toLocaleString('en-GB', {
      ...opts,
      timeZone: intraday ? undefined : 'UTC',
    })
  }

  /**
   * Format for anything on the price axis: the candles and any overlay.
   *
   * Deliberately a per-series custom format rather than
   * `localization.priceFormatter`. That option is chart-WIDE and outranks every
   * series format, so setting the currency there put a rupee sign on the RSI and
   * Stochastic axes — "₹70.00" for a bounded oscillator. Currency belongs to the
   * instrument, not to the chart, so it lives on the series that actually plot it.
   */
  function priceFormat() {
    return {
      type: 'custom' as const,
      minMove: 1 / 10 ** precision,
      formatter: (v: number) => `${CURRENCY_SYMBOL[currency]}${v.toFixed(precision)}`,
    }
  }

  /**
   * Format for a series in its own pane.
   *
   * `localization.priceFormatter` is chart-wide, so without this an RSI axis read
   * "₹70.00" and "₹100.00" — a currency symbol on a bounded oscillator, which is
   * simply wrong. A per-series custom format takes precedence over the chart
   * default, so each oscillator formats itself as a plain number.
   */
  function studyFormat() {
    /** Decimals appropriate to a magnitude, so a small MACD keeps its detail. */
    const digitsFor = (magnitude: number) =>
      magnitude >= 1000 ? 0 : magnitude >= 1 ? 2 : 4

    return {
      type: 'custom' as const,
      minMove: 0.0001,
      // Zero is special-cased: its magnitude is 0, so the rule below would give it
      // four decimals and a MACD zero line would be labelled "0.0000".
      formatter: (v: number) => (v === 0 ? '0.00' : v.toFixed(digitsFor(Math.abs(v)))),
      /**
       * One precision for the whole axis, chosen from its largest tick.
       *
       * Formatting each tick on its own magnitude mixed "0.0000" and "40.00" on a
       * single MACD scale, which reads as a rendering fault. This receives every
       * tick at once, which is what it is for.
       */
      tickmarksFormatter: (values: readonly number[]) => {
        let max = 0
        for (const v of values) max = Math.max(max, Math.abs(v))
        const digits = digitsFor(max)
        return values.map((v) => v.toFixed(digits))
      },
    }
  }

  function buildPriceSeries() {
    const p = palette(mode)
    if (style === 'candles') {
      return chart.addSeries(CandlestickSeries, {
        upColor: p.up,
        downColor: p.down,
        // Borderless. A border in the same colour as the body is invisible at wide
        // spacing and a solid smear at 250 bars, where every candle is two or
        // three pixels of body inside two pixels of outline.
        borderVisible: false,
        // Wicks a shade darker than the bodies, so a long wick still reads as
        // belonging to its candle without drawing the eye off the body.
        wickUpColor: p.wickUp,
        wickDownColor: p.wickDown,
        priceFormat: priceFormat(),
      })
    }
    // Area rather than a bare line: the fill reads as "price over time" at a
    // glance on a phone, where a 1px line on a busy background does not. Also the
    // honest choice at 1-minute, where our own sampling cannot fill a candle body.
    return chart.addSeries(AreaSeries, {
      lineColor: p.accent,
      topColor: `${p.accent}40`,
      bottomColor: `${p.accent}04`,
      lineWidth: 2,
      priceFormat: priceFormat(),
    })
  }

  function paintPrice() {
    if (style === 'candles') {
      ;(priceSeries as ISeriesApi<'Candlestick'>).setData(
        candles.map((c) => ({
          time: asTime(c.time),
          open: c.open,
          high: c.high,
          low: c.low,
          close: c.close,
        })),
      )
    } else {
      ;(priceSeries as ISeriesApi<'Area'>).setData(
        candles.map((c) => ({ time: asTime(c.time), value: c.close })),
      )
    }
  }

  /**
   * Tears down and rebuilds every indicator series.
   *
   * Wholesale rather than incremental because panes cannot be reordered or
   * removed once created: adding RSI then removing it would otherwise leave an
   * empty pane taking up a third of the chart. Cheap enough — the maths is
   * already done by the time this runs.
   */
  function paintIndicators() {
    for (const t of paneTitles) {
      try {
        t.detach()
      } catch {
        // Its pane is already gone.
      }
    }
    paneTitles = []

    for (const s of indicatorSeries) {
      try {
        chart.removeSeries(s)
      } catch {
        // Already gone with its pane. Nothing to do.
      }
    }
    indicatorSeries = []
    plotSeries = new Map()

    // Panes are indexed from 1; pane 0 is the price.
    let nextPane = 1
    for (const ind of indicators) {
      const paneIndex = ind.pane === 'price' ? 0 : nextPane++

      for (const plot of ind.plots) {
        if (plot.data.length === 0) continue

        if (plot.style === 'histogram') {
          const s = chart.addSeries(
            HistogramSeries,
            {
              color: plot.color,
              priceLineVisible: false,
              lastValueVisible: false,
              priceFormat: studyFormat(),
            },
            paneIndex,
          )
          s.setData(
            plot.data.map((d, i) => ({
              time: asTime(d.time),
              value: d.value,
              color: plot.colors?.[i] ?? plot.color,
            })),
          )
          indicatorSeries.push(s)
          plotSeries.set(plot.key, s)
          continue
        }

        const s = chart.addSeries(
          LineSeries,
          {
            color: plot.color,
            lineWidth: plot.lineWidth ?? 2,
            priceLineVisible: false,
            lastValueVisible: false,
            // Dots are a line with no join, which is what Parabolic SAR needs:
            // joining across a reversal draws a vertical stroke through the
            // candles that means nothing.
            ...(plot.style === 'dots'
              ? { lineStyle: LineStyle.Dotted, lineWidth: 1 as const, pointMarkersVisible: true }
              : {}),
            // Overlays share the price axis and so its currency; studies in their
            // own pane must not inherit a rupee sign for an RSI reading.
            priceFormat: ind.pane === 'price' ? priceFormat() : studyFormat(),
          },
          paneIndex,
        )
        s.setData(plot.data.map((d) => ({ time: asTime(d.time), value: d.value })))
        indicatorSeries.push(s)
        plotSeries.set(plot.key, s)
      }

      // Reference levels (RSI 30/70, MACD zero) belong to the pane, and a price
      // line on the pane's first series is the only per-pane anchor available.
      const anchor = ind.plots.map((p) => plotSeries.get(p.key)).find(Boolean)
      if (anchor && ind.levels) {
        const p = palette(mode)
        for (const level of ind.levels) {
          anchor.createPriceLine({
            price: level,
            color: p.border,
            lineWidth: 1,
            lineStyle: LineStyle.Dashed,
            // No axis label. With one on, RSI's 30 and 70 badges printed on top of
            // the axis's own ticks and the scale became an unreadable stack of
            // overlapping numbers. The dashed line carries the meaning; 30 and 70
            // on an RSI need no caption.
            axisLabelVisible: false,
            title: '',
          })
        }
      }
      if (anchor && ind.range) {
        anchor.applyOptions({
          autoscaleInfoProvider: () => ({
            priceRange: { minValue: ind.range![0], maxValue: ind.range![1] },
          }),
        })
      }

      // Study panes get their own, tighter margins.
      //
      // `rightPriceScale.scaleMargins` is chart-wide, and the price pane wants
      // generous headroom for its title and last-price badge. Inherited by a pane
      // pinned to 0..100, that 16% top margin stretched the visible range to 120
      // and an RSI axis was labelled past its own maximum.
      //
      // ponytail: the top margin still has to clear the pane title, so a bounded
      // oscillator has a little dead space above its maximum and a tall pane can
      // fit a tick there — an RSI axis may show 120. The line, its 30/70 guides
      // and every value are correct; it is one label in empty space. Removing it
      // needs the axis range and the margin decoupled, which lightweight-charts
      // does not expose, so the upgrade path is a DOM pane title positioned from
      // pane geometry instead of a watermark.
      if (paneIndex > 0) {
        chart.priceScale('right', paneIndex).applyOptions({
          scaleMargins: { top: 0.16, bottom: 0.08 },
          borderColor: palette(mode).border,
        })
      }

      // Name the pane. Three stacked oscillators with no titles can only be told
      // apart by matching line colours against the legend, which is not reading a
      // chart, it is decoding one.
      if (paneIndex > 0) {
        const pane = chart.panes()[paneIndex]
        if (pane) paneTitles.push(createTextWatermark(pane, paneTitleOptions(mode, ind.label)))
      }
    }

    // Give the price pane the room. Oscillator panes are readable at a fraction
    // of it, and an even split makes the candles useless with two indicators on.
    const panes = chart.panes()
    if (panes.length > 1) {
      panes[0]!.setStretchFactor(panes.length > 2 ? 3 : 2.6)
      for (let i = 1; i < panes.length; i++) panes[i]!.setStretchFactor(1)
    }
  }

  if (options.onHover) {
    const onHover = options.onHover
    chart.subscribeCrosshairMove((param) => {
      if (param.time === undefined) {
        onHover({ bar: null, values: new Map() })
        return
      }
      const t = param.time as unknown as number
      const values = new Map<string, number>()
      for (const [key, series] of plotSeries) {
        const point = param.seriesData.get(series) as { value?: number } | undefined
        if (point?.value !== undefined) values.set(key, point.value)
      }
      // Read the bar from our own array, not `seriesData`: in line mode the price
      // series carries only a close and the legend still wants the full OHLC.
      onHover({ bar: candles.find((c) => c.time === t) ?? null, values })
    })
  }

  function rebuildAll() {
    chart.applyOptions(layoutFor())
    chart.removeSeries(priceSeries)
    priceSeries = buildPriceSeries()
    paintPrice()
    paintIndicators()
  }

  return {
    setCandles(next) {
      candles = next.slice().sort((a, b) => a.time - b.time)
      const nextPrecision = precisionFor(candles)
      if (nextPrecision !== precision) {
        precision = nextPrecision
        // Precision lives on both the axis formatter and the series format, so a
        // change has to touch the chart options as well as the series.
        chart.applyOptions(layoutFor())
        priceSeries.applyOptions({ priceFormat: priceFormat() })
      }
      paintPrice()
      chart.timeScale().fitContent()
    },

    pushTick(tick) {
      const bucket = TIMEFRAME_SECONDS[timeframe]
      const merged = mergeTick(candles[candles.length - 1], tick, bucket)

      const last = candles[candles.length - 1]
      if (last && last.time === merged.time) candles[candles.length - 1] = merged
      else candles.push(merged)

      if (style === 'candles') {
        ;(priceSeries as ISeriesApi<'Candlestick'>).update({
          time: asTime(merged.time),
          open: merged.open,
          high: merged.high,
          low: merged.low,
          close: merged.close,
        })
      } else {
        ;(priceSeries as ISeriesApi<'Area'>).update({
          time: asTime(merged.time),
          value: merged.close,
        })
      }
    },

    setIndicators(next) {
      indicators = next
      paintIndicators()
    },

    setStyle(next) {
      if (next === style) return
      style = next
      chart.removeSeries(priceSeries)
      priceSeries = buildPriceSeries()
      paintPrice()
    },

    setMode(next) {
      if (next === mode) return
      mode = next
      watermark.applyOptions(watermarkOptions(mode, subtitle))
      badge.remove()
      badge = createBrandBadge(mode)
      container.append(badge)
      // Series colours are baked in at construction, so everything is rebuilt
      // rather than recoloured field by field.
      rebuildAll()
    },

    setCurrency(next) {
      if (next === currency) return
      currency = next
      chart.applyOptions(layoutFor())
    },

    setSubtitle(next) {
      subtitle = next
      watermark.applyOptions(watermarkOptions(mode, subtitle))
    },

    setTimeframe(next) {
      if (next === timeframe) return
      timeframe = next
      // Only the axis needs to know; the caller replaces the series via
      // setCandles once it has refetched.
      chart.applyOptions(layoutFor())
    },

    lastBar() {
      return candles[candles.length - 1] ?? null
    },

    bars() {
      return candles
    },

    fitContent() {
      chart.timeScale().fitContent()
    },

    drawings() {
      return drawings
    },

    destroy() {
      drawings.destroy()
      badge.remove()
      chart.remove()
    },
  }
}
