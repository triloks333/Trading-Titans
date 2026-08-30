import { useEffect, useRef, useState } from 'react'
import {
  createChart,
  CandlestickSeries,
  type IChartApi,
  type ISeriesApi,
} from 'lightweight-charts'
import { fetchCandles, timeframesFor, DEFAULT_TIMEFRAME } from '@/lib/market'
import { cn, CURRENCY_SYMBOL, currencyFor } from '@/lib/format'

/*
 * Candles rendered with lightweight-charts — TradingView's own open-source
 * charting library, MIT licensed and built for exactly this.
 *
 * Worth stating why this is not an embedded TradingView page: tradingview.com
 * sends X-Frame-Options, so it cannot be put in an iframe, and linking out to it
 * is not a chart feature — it is an exit from the product. This draws from the
 * same market-history function the mobile app uses, so both platforms show the
 * same numbers.
 */

/*
 * Timeframes come from lib/market.ts, where each one pairs a candle interval with
 * the range it should cover. The buttons used to offer bare intervals (5m … 1w)
 * against a range fixed at one month, so "1w" drew four candles and "1d" drew
 * twenty-two. Choosing a period rather than an interval is also what a user
 * actually wants to express.
 */

export function CandleChart({
  symbol,
  market,
  height = 380,
}: {
  symbol: string
  market: string
  height?: number
}) {
  const containerRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<IChartApi | null>(null)
  const seriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null)

  const [timeframe, setTimeframe] = useState<string>(DEFAULT_TIMEFRAME)
  const [state, setState] = useState<'loading' | 'ready' | 'empty' | 'error'>('loading')

  // Crypto offers fewer frames than equities, so the selected one may not exist
  // after switching instrument; fall back rather than request something invalid.
  const frames = timeframesFor(market)
  const activeFrame = frames.some((f) => f.id === timeframe) ? timeframe : DEFAULT_TIMEFRAME

  // Create the chart once, then only ever feed it new data. Recreating it on
  // every symbol change would drop the user's pan and zoom.
  useEffect(() => {
    if (!containerRef.current) return

    const chart = createChart(containerRef.current, {
      height,
      layout: {
        background: { color: 'transparent' },
        textColor: '#627d98',
        fontFamily: 'Inter, sans-serif',
        attributionLogo: false,
      },
      grid: {
        vertLines: { visible: false },
        horzLines: { color: 'rgba(221,231,242,0.9)' },
      },
      rightPriceScale: { borderColor: '#dde7f2' },
      timeScale: { borderColor: '#dde7f2', rightOffset: 4 },
      crosshair: { mode: 1 },
      localization: {
        // The axis has to agree with the instrument. A US chart previously
        // labelled its dollar candles with a rupee sign, which made a $320 stock
        // read as if it cost the same as a mid-cap Indian share.
        priceFormatter: (p: number) => {
          const ccy = currencyFor(market)
          return `${CURRENCY_SYMBOL[ccy]}${p.toLocaleString(
            ccy === 'USD' ? 'en-US' : 'en-IN',
            { maximumFractionDigits: 2 },
          )}`
        },
      },
    })

    const series = chart.addSeries(CandlestickSeries, {
      upColor: '#0f9d58',
      downColor: '#d93025',
      borderUpColor: '#0f9d58',
      borderDownColor: '#d93025',
      wickUpColor: '#0f9d58',
      wickDownColor: '#d93025',
    })

    chartRef.current = chart
    seriesRef.current = series

    const observer = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width
      if (w) chart.applyOptions({ width: Math.floor(w) })
    })
    observer.observe(containerRef.current)

    return () => {
      observer.disconnect()
      chart.remove()
      chartRef.current = null
      seriesRef.current = null
    }
  }, [height])

  // The chart instance is created once and deliberately not rebuilt on symbol
  // change, so the price formatter captured in that effect would keep whichever
  // currency was current when it ran. Re-applying it here means switching from an
  // Indian stock to a US one relabels the axis without discarding the chart (and
  // with it the user's pan and zoom).
  useEffect(() => {
    const ccy = currencyFor(market)
    chartRef.current?.applyOptions({
      localization: {
        priceFormatter: (p: number) =>
          `${CURRENCY_SYMBOL[ccy]}${p.toLocaleString(ccy === 'USD' ? 'en-US' : 'en-IN', {
            maximumFractionDigits: 2,
          })}`,
      },
    })
  }, [market])

  useEffect(() => {
    let cancelled = false
    setState('loading')

    fetchCandles(symbol, market, activeFrame)
      .then((candles) => {
        if (cancelled || !seriesRef.current) return
        if (candles.length === 0) {
          seriesRef.current.setData([])
          setState('empty')
          return
        }
        seriesRef.current.setData(
          candles.map((c) => ({
            // lightweight-charts wants seconds; the function returns millis.
            time: Math.floor(c.t / 1000) as never,
            open: c.o,
            high: c.h,
            low: c.l,
            close: c.c,
          })),
        )
        chartRef.current?.timeScale().fitContent()
        setState('ready')
      })
      .catch(() => {
        if (!cancelled) setState('error')
      })

    return () => {
      cancelled = true
    }
  }, [symbol, market, activeFrame])

  return (
    <div>
      <div className="relative">
        <div ref={containerRef} style={{ height }} />
        {state !== 'ready' && (
          <div className="absolute inset-0 flex items-center justify-center">
            <p className="text-xs text-ink-4">
              {state === 'loading' && 'Loading chart…'}
              {state === 'empty' && 'No price history for this interval.'}
              {state === 'error' && 'Chart data is unavailable right now.'}
            </p>
          </div>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-1.5 border-t border-birch px-4 py-3">
        {frames.map((tf) => (
          <button
            key={tf.id}
            onClick={() => setTimeframe(tf.id)}
            className={cn(
              'rounded-tag px-2.5 py-1 text-[11px] font-semibold transition-colors',
              activeFrame === tf.id ? 'bg-ink text-white' : 'bg-cream text-ink-4 hover:text-ink',
            )}
          >
            {tf.label}
          </button>
        ))}
        {/* States the candle size, so a user can tell 1Y-of-daily from 5Y-of-weekly
            rather than having to infer it from the bar width. */}
        <span className="ml-auto text-[10px] text-ink-5">
          {frames.find((t) => t.id === activeFrame)?.interval} candles
        </span>
      </div>
    </div>
  )
}
