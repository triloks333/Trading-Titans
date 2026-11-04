import { useEffect, useMemo, useRef, useState } from 'react'
import { Star, Trash2, Pencil, SlidersHorizontal, Maximize2, Minimize2 } from 'lucide-react'
import {
  compactValue,
  createTitanChart,
  DEFAULT_PERIOD,
  defaultParams,
  defaultTemplate,
  deleteTemplate,
  fetchHistory,
  fetchLiveQuote,
  INDICATORS,
  listTemplates,
  periodFor,
  periodsFor,
  readLegend,
  renameTemplate,
  saveTemplate,
  streamLive,
  toggleDefault,
  type ChartTemplate,
  type LiveStream,
  type HoverState,
  type IndicatorResult,
  type IndicatorSpec,
  type LegendRow,
  type Market,
  type TemplateEntry,
  type TitanChart,
} from '@chart'
import { cn } from '@/lib/format'

/*
 * The instrument chart.
 *
 * Everything that draws is in the shared `chart` package — the same code the
 * Flutter client loads as a bundled asset. This file is only the React shell
 * around it: state, buttons, and the indicator tray.
 *
 * WHAT THIS REPLACED
 * A local `lightweight-charts` setup that duplicated the theme, the currency
 * formatting and the millisecond-to-second conversion, and carried no indicators
 * at all. There were three charts in this product and they disagreed with each
 * other; now there is one.
 *
 * The live price comes from `quotes_cache`, which is the table the matching engine
 * prices fills from — so the right-hand edge of the chart is the number a user
 * would actually be filled at. Historical bars are still the vendor's, so the body
 * of the chart will not agree to the paisa. That seam is known.
 */

export function CandleChart({
  symbol,
  market,
  height = 420,
}: {
  symbol: string
  market: string
  height?: number
}) {
  const containerRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<TitanChart | null>(null)

  const mkt = market as Market
  const [periodId, setPeriodId] = useState<string>(DEFAULT_PERIOD)
  const [state, setState] = useState<'loading' | 'ready' | 'empty' | 'error'>('loading')
  const [trayOpen, setTrayOpen] = useState(false)
  const [legend, setLegend] = useState<LegendRow[]>([])
  const [isEnlarged, setIsEnlarged] = useState(false)

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsEnlarged(false)
    }
    if (isEnlarged) {
      window.addEventListener('keydown', handleKeyDown)
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      document.body.style.overflow = ''
    }
  }, [isEnlarged])

  useEffect(() => {
    const t = setTimeout(() => {
      chartRef.current?.fitContent()
    }, 50)
    return () => clearTimeout(t)
  }, [isEnlarged])

  /** Active indicators and their parameters. Parameters are part of a strategy. */
  const [active, setActive] = useState<Map<string, Record<string, number>>>(() => {
    // A starred strategy is what "default" means: the chart opens with it on.
    const saved = defaultTemplate()
    const m = new Map<string, Record<string, number>>()
    if (saved) for (const e of saved.entries) m.set(e.id, { ...e.params })
    return m
  })
  const [templates, setTemplates] = useState<ChartTemplate[]>(() => listTemplates())
  const [tplName, setTplName] = useState(() => defaultTemplate()?.name ?? '')
  const [tplMsg, setTplMsg] = useState<{ text: string; ok: boolean } | null>(null)

  const periods = periodsFor(mkt)
  const period = periodFor(mkt, periodId)

  // Results are recomputed from the chart's own bars, so they always match what is
  // drawn rather than a copy kept here.
  const results = useRef<IndicatorResult[]>([])

  /*
   * The chart instance is created once and fed new data, never rebuilt on symbol
   * change — rebuilding would discard the user's pan and zoom on every switch.
   */
  useEffect(() => {
    if (!containerRef.current) return
    const chart = createTitanChart(containerRef.current, {
      mode: 'light',
      timeframe: period.interval,
      subtitle: `${symbol} · ${period.label}`,
      onHover: (s: HoverState) => setLegend(readLegend(results.current, s)),
    })
    chartRef.current = chart
    return () => {
      chart.destroy()
      chartRef.current = null
    }
    // Intentionally once. Symbol, period and indicators are pushed in below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const applyIndicators = useMemo(
    () => (chart: TitanChart, current: Map<string, Record<string, number>>) => {
      const bars = [...chart.bars()]
      const out: IndicatorResult[] = []
      // Catalogue order, not click order, so panes do not shuffle when a strategy
      // is applied in a different sequence than it was built in.
      for (const spec of INDICATORS) {
        const params = current.get(spec.id)
        if (!params) continue
        try {
          out.push(spec.build(bars, params, 'light'))
        } catch {
          // One bad indicator must not blank the chart.
        }
      }
      results.current = out
      chart.setIndicators(out)
      setLegend(readLegend(out, { bar: null, values: new Map() }))
    },
    [],
  )

  // Data. Both requests at once: history is the body of the chart, the quote its edge.
  useEffect(() => {
    const chart = chartRef.current
    if (!chart) return
    let cancelled = false
    let stream: LiveStream | null = null
    setState('loading')
    chart.setCurrency(mkt === 'us_stock' ? 'USD' : 'INR')
    chart.setTimeframe(period.interval)
    chart.setSubtitle(`${symbol} · ${period.label}`)

    Promise.all([
      fetchHistory(symbol, mkt, period),
      fetchLiveQuote(symbol, mkt).catch(() => null),
    ])
      .then(([candles, quote]) => {
        if (cancelled || !chartRef.current) return
        chart.setCandles(candles)
        if (quote) chart.pushTick({ time: quote.time, price: quote.price })
        // The live edge; without it this chart froze at whatever loaded.
        stream = streamLive(symbol, mkt, (tick) => chart.pushTick(tick), quote?.price)
        applyIndicators(chart, active)
        setState(candles.length === 0 ? 'empty' : 'ready')
      })
      .catch(() => {
        if (!cancelled) setState('error')
      })

    return () => {
      cancelled = true
      stream?.stop()
    }
  }, [symbol, mkt, period, active, applyIndicators])

  function toggleIndicator(spec: IndicatorSpec) {
    setActive((prev) => {
      const next = new Map(prev)
      if (next.has(spec.id)) next.delete(spec.id)
      else next.set(spec.id, defaultParams(spec))
      return next
    })
    noteDivergence()
  }

  function setParam(spec: IndicatorSpec, key: string, raw: number, min: number, max: number) {
    // Clamped here as well as on read: a length of 100000 typed in spins every bar
    // through a window that can never fill.
    const v = Number.isFinite(raw) ? Math.min(max, Math.max(min, raw)) : min
    setActive((prev) => {
      const next = new Map(prev)
      const cur = next.get(spec.id)
      if (cur) next.set(spec.id, { ...cur, [key]: v })
      return next
    })
    noteDivergence()
  }

  function noteDivergence() {
    // Applying a strategy then changing something means what is on screen is no
    // longer that strategy. Saying so avoids "I starred it but it opens different".
    if (tplName) setTplMsg({ text: `Changed since “${tplName}”. Save to keep it.`, ok: false })
  }

  function currentEntries(): TemplateEntry[] {
    const out: TemplateEntry[] = []
    for (const spec of INDICATORS) {
      const params = active.get(spec.id)
      if (params) out.push({ id: spec.id, params: { ...params } })
    }
    return out
  }

  function onSave() {
    const res = saveTemplate(tplName, currentEntries())
    if (!res.ok) {
      setTplMsg({ text: res.error ?? 'Could not save that.', ok: false })
      return
    }
    setTemplates(listTemplates())
    setTplMsg({ text: `Saved “${res.template!.name}”.`, ok: true })
  }

  function onApply(t: ChartTemplate) {
    const m = new Map<string, Record<string, number>>()
    for (const e of t.entries) m.set(e.id, { ...e.params })
    setActive(m)
    setTplName(t.name)
    setTplMsg({ text: `Applied “${t.name}”.`, ok: true })
  }

  return (
    <div
      className={cn(
        'relative flex flex-col',
        isEnlarged && 'fixed inset-0 z-50 bg-pure-white p-4 sm:p-6 overflow-hidden shadow-2xl',
      )}
    >
      {isEnlarged && (
        <div className="flex items-center justify-between border-b border-birch pb-3 mb-2">
          <div>
            <h3 className="text-base font-bold text-ink">{symbol}</h3>
            <p className="text-xs text-ink-4">
              {mkt === 'us_stock' ? 'US Equity' : 'NSE Equity / Derivatives'} · {period.label}
            </p>
          </div>
          <button
            onClick={() => setIsEnlarged(false)}
            className="flex items-center gap-1.5 rounded-lg border border-birch bg-cream px-3 py-1.5 text-xs font-semibold text-ink hover:bg-birch/50 transition-colors"
          >
            <Minimize2 className="h-3.5 w-3.5" />
            <span>Exit Fullscreen</span>
          </button>
        </div>
      )}

      <div className={cn('relative', isEnlarged ? 'flex-1 min-h-0' : '')}>
        <div
          ref={containerRef}
          style={{ height: isEnlarged ? '100%' : height }}
          className="w-full"
        />
        {state !== 'ready' && (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <p className="text-xs text-ink-4">
              {state === 'loading' && 'Loading chart…'}
              {state === 'empty' && 'No price history for this period.'}
              {state === 'error' && 'Chart data is unavailable right now.'}
            </p>
          </div>
        )}
      </div>

      {/* Indicator values at the crosshair, one chip per indicator. */}
      {legend.length > 0 && (
        <div className="flex flex-wrap gap-1.5 border-t border-birch px-4 py-2">
          {legend.map((row) => (
            <span
              key={row.label}
              className="flex items-center gap-2 rounded-md border border-birch bg-cream/50 px-2 py-1"
            >
              <span className="text-[10px] font-semibold uppercase tracking-wide text-ink-4">
                {row.label}
              </span>
              {row.vals.map((v, i) => (
                <span key={i} className="flex items-center gap-1">
                  <span className="h-[7px] w-[7px] rounded-sm" style={{ background: v.color }} />
                  <span className="tnum text-[11px] font-semibold text-ink">
                    {compactValue(v.v)}
                  </span>
                </span>
              ))}
            </span>
          ))}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-1.5 border-t border-birch px-4 py-3">
        {periods.map((p) => (
          <button
            key={p.id}
            onClick={() => setPeriodId(p.id)}
            title={`${p.interval} bars`}
            className={cn(
              'rounded-tag px-2.5 py-1 text-[11px] font-semibold transition-colors',
              period.id === p.id ? 'bg-ink text-white' : 'bg-cream text-ink-4 hover:text-ink',
            )}
          >
            {p.label}
          </button>
        ))}

        <div className="ml-auto flex items-center gap-2">
          <button
            onClick={() => setTrayOpen((v) => !v)}
            className={cn(
              'flex items-center gap-1.5 rounded-tag px-2.5 py-1 text-[11px] font-semibold transition-colors',
              trayOpen || active.size > 0
                ? 'bg-brand text-white'
                : 'bg-cream text-ink-4 hover:text-ink',
            )}
          >
            <SlidersHorizontal className="h-3 w-3" />
            Indicators{active.size > 0 && ` ${active.size}`}
          </button>

          <button
            onClick={() => setIsEnlarged((v) => !v)}
            title={isEnlarged ? 'Minimize chart (Esc)' : 'Enlarge chart'}
            className="flex items-center gap-1.5 rounded-tag bg-cream px-2.5 py-1 text-[11px] font-semibold text-ink-4 hover:text-ink transition-colors"
          >
            {isEnlarged ? (
              <>
                <Minimize2 className="h-3 w-3" />
                <span>Minimize</span>
              </>
            ) : (
              <>
                <Maximize2 className="h-3 w-3" />
                <span>Enlarge</span>
              </>
            )}
          </button>
        </div>
      </div>

      {trayOpen && (
        <div className="flex flex-wrap gap-x-7 gap-y-3 border-t border-birch bg-cream/30 px-4 py-4">
          {groupIndicators().map(([group, specs]) => (
            <div key={group} className="flex flex-col gap-1">
              <h4 className="text-[8.5px] font-semibold uppercase tracking-[0.15em] text-ink-5">
                {group}
              </h4>
              {specs.map((spec) => {
                const params = active.get(spec.id)
                return (
                  <div key={spec.id} className="flex min-h-[24px] items-center gap-2">
                    <label className="flex cursor-pointer items-center gap-2 text-[12.5px] text-ink-3">
                      <input
                        type="checkbox"
                        checked={!!params}
                        onChange={() => toggleIndicator(spec)}
                        className="accent-brand"
                      />
                      {spec.name}
                    </label>
                    {/* Parameter boxes only for what is on: nineteen indicators'
                        worth of inputs at once is a wall nobody reads. */}
                    {params &&
                      spec.params.map((p) => (
                        <input
                          key={p.key}
                          type="number"
                          title={p.label}
                          value={params[p.key] ?? p.default}
                          min={p.min}
                          max={p.max}
                          step={p.kind === 'multiplier' ? 0.1 : 1}
                          onChange={(e) =>
                            setParam(spec, p.key, Number(e.target.value), p.min, p.max)
                          }
                          className="tnum w-12 rounded border border-birch bg-pure-white px-1 py-0.5 text-center text-[11px]"
                        />
                      ))}
                  </div>
                )
              })}
            </div>
          ))}

          {/* Saved strategies */}
          <div className="flex w-full max-w-xs flex-col gap-1.5 border-t border-birch pt-3 lg:w-64 lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0">
            <h4 className="text-[8.5px] font-semibold uppercase tracking-[0.15em] text-ink-5">
              Saved strategies
            </h4>
            <div className="flex gap-1.5">
              <input
                value={tplName}
                onChange={(e) => setTplName(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && onSave()}
                placeholder="Name this setup"
                maxLength={40}
                className="min-w-0 flex-1 rounded-md border border-birch bg-pure-white px-2 py-1 text-[12.5px]"
              />
              <button
                onClick={onSave}
                className="rounded-md border border-birch bg-pure-white px-2.5 py-1 text-[12.5px] font-semibold hover:border-brand hover:text-brand"
              >
                Save
              </button>
            </div>
            {tplMsg && (
              <p className={cn('text-[11px]', tplMsg.ok ? 'text-bull' : 'text-ink-5')}>
                {tplMsg.text}
              </p>
            )}

            {templates.length === 0 ? (
              <p className="text-[11.5px] leading-snug text-ink-5">
                No saved strategies yet. Turn on some indicators, name the set, and save.
              </p>
            ) : (
              templates.map((t) => (
                <div
                  key={t.key}
                  className="flex items-center gap-1 rounded-md border border-birch bg-pure-white p-1"
                >
                  <button
                    onClick={() => onApply(t)}
                    title={`Apply — ${t.entries.map((e) => e.id).join(', ')}`}
                    className="min-w-0 flex-1 truncate px-1 text-left text-[12.5px] font-semibold text-ink hover:text-brand"
                  >
                    {t.name}
                  </button>
                  <span className="tnum rounded-full border border-birch px-1.5 text-[10px] text-ink-5">
                    {t.entries.length}
                  </span>
                  <button
                    title={t.isDefault ? 'Opens by default' : 'Open charts with this by default'}
                    onClick={() => {
                      toggleDefault(t.key)
                      setTemplates(listTemplates())
                    }}
                    className={cn('p-1', t.isDefault ? 'text-brand' : 'text-ink-5 hover:text-ink')}
                  >
                    <Star className="h-3 w-3" fill={t.isDefault ? 'currentColor' : 'none'} />
                  </button>
                  <button
                    title="Rename"
                    onClick={() => {
                      const next = prompt(`Rename “${t.name}” to:`, t.name)
                      if (next === null) return
                      const res = renameTemplate(t.key, next)
                      if (!res.ok) {
                        setTplMsg({ text: res.error ?? 'Could not rename.', ok: false })
                        return
                      }
                      setTemplates(listTemplates())
                    }}
                    className="p-1 text-ink-5 hover:text-ink"
                  >
                    <Pencil className="h-3 w-3" />
                  </button>
                  <button
                    title="Delete"
                    onClick={() => {
                      // Confirmed: there is no undo and the row is one click from Apply.
                      if (!confirm(`Delete the strategy “${t.name}”?`)) return
                      deleteTemplate(t.key)
                      setTemplates(listTemplates())
                    }}
                    className="p-1 text-ink-5 hover:text-bear"
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                </div>
              ))
            )}
            <p className="text-[10.5px] leading-snug text-ink-5">
              Saved in this browser. Star one to have charts open with it.
            </p>
          </div>
        </div>
      )}
    </div>
  )
}

function groupIndicators(): [string, IndicatorSpec[]][] {
  const groups = new Map<string, IndicatorSpec[]>()
  for (const spec of INDICATORS) {
    const list = groups.get(spec.group) ?? []
    list.push(spec)
    groups.set(spec.group, list)
  }
  return [...groups]
}


