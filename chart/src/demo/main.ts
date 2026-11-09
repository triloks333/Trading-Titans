import {
  compactValue as compact,
  createTitanChart,
  type HoverState,
  type TitanChart,
} from '../core/chart'
import { isHonestCandleTimeframe } from '../core/aggregate'
import { MARK_DATA_URI } from '../core/brand'
import { CURRENCY_SYMBOL } from '../core/theme'
import { INDICATORS, defaultParams, type IndicatorSpec } from '../core/registry'
import { forDisplay, type ChartTemplate, type TemplateEntry } from '../core/templates'
import { DEFAULT_PERIOD, periodFor, periodsFor } from '../core/periods'
import type { Candle, Currency, Market, SeriesStyle, ThemeMode } from '../core/types'
import type { IndicatorResult } from '../core/indicators'
import { fetchHistory } from '../data/history'
import { fetchLiveQuote, type LiveQuote } from '../data/quote'
import {
  defaultTemplate,
  deleteTemplate,
  listTemplates,
  renameTemplate,
  saveTemplate,
  toggleDefault,
} from '../data/templates'

/*
 * Dev harness wiring. None of this belongs in either client — it exists so the
 * chart can be exercised against real symbols, real history, our own live price,
 * every indicator and saved strategies before anything depends on it.
 */

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T

const el = {
  brandMark: $<HTMLImageElement>('brandMark'),
  symbol: $<HTMLInputElement>('symbol'),
  market: $<HTMLSelectElement>('market'),
  load: $<HTMLButtonElement>('load'),
  timeframes: $<HTMLDivElement>('timeframes'),
  indicatorsBtn: $<HTMLButtonElement>('indicatorsBtn'),
  indCount: $<HTMLSpanElement>('indCount'),
  tray: $<HTMLDivElement>('tray'),
  picker: $<HTMLDivElement>('picker'),
  tplName: $<HTMLInputElement>('tplName'),
  tplSave: $<HTMLButtonElement>('tplSave'),
  tplList: $<HTMLDivElement>('tplList'),
  tplMsg: $<HTMLDivElement>('tplMsg'),
  styleCandles: $<HTMLButtonElement>('styleCandles'),
  styleLine: $<HTMLButtonElement>('styleLine'),
  live: $<HTMLButtonElement>('live'),
  theme: $<HTMLButtonElement>('theme'),
  chart: $<HTMLDivElement>('chart'),
  legend: $<HTMLDivElement>('legend'),
  barSymbol: $<HTMLDivElement>('barSymbol'),
  barName: $<HTMLDivElement>('barName'),
  barLast: $<HTMLDivElement>('barLast'),
  barChange: $<HTMLDivElement>('barChange'),
  barOhlc: $<HTMLDivElement>('barOhlc'),
  statBars: $<HTMLSpanElement>('statBars'),
  statSource: $<HTMLSpanElement>('statSource'),
  statTick: $<HTMLSpanElement>('statTick'),
  statNote: $<HTMLSpanElement>('statNote'),
  statErr: $<HTMLSpanElement>('statErr'),
}

el.brandMark.src = MARK_DATA_URI

/**
 * The span the user picked. The chart buckets by `period.interval`; the feed is
 * asked for `period.range`. See core/periods.ts for why those are separate.
 */
let periodId: string = DEFAULT_PERIOD
let style: SeriesStyle = 'candles'
let mode: ThemeMode = 'light'
let live = false
let liveTimer: number | undefined
let quote: LiveQuote | null = null

/**
 * Active indicators and their parameters, in the order they were switched on.
 *
 * A Map rather than a Set of ids, because parameters are part of what makes a
 * strategy: "EMA 21" and "EMA 200" are different tools, and a saved template that
 * only remembered *which* indicators would collapse them into the same thing.
 */
const active = new Map<string, Record<string, number>>()
/** Computed results, kept so the legend can label plots without recomputing. */
let results: IndicatorResult[] = []
/** The template currently applied, for the "modified" hint. */
let appliedTemplate: string | null = null

/** US listings are quoted in dollars; everything else our backend hands us is rupees. */
const currencyFor = (m: Market): Currency => (m === 'us_stock' || m === 'commodity' ? 'USD' : 'INR')
const market = () => el.market.value as Market
const symbol = () => el.symbol.value.trim().toUpperCase()

const period = () => periodFor(market(), periodId)

const chart: TitanChart = createTitanChart(el.chart, {
  mode,
  style,
  timeframe: period().interval,
  currency: currencyFor(market()),
  subtitle: `RELIANCE · ${DEFAULT_PERIOD}`,
  onHover: showLegend,
})

function fmt(v: number | null | undefined, digits = 2): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—'
  return `${CURRENCY_SYMBOL[currencyFor(market())]}${v.toFixed(digits)}`
}

function showOhlc(bar: Candle | null) {
  const b = bar ?? chart.lastBar()
  if (!b) {
    el.barOhlc.textContent = ''
    return
  }
  const cells: string[] = []
  for (const [k, v] of [['O', b.open], ['H', b.high], ['L', b.low], ['C', b.close]] as const) {
    cells.push(`<span>${k} <b>${compact(v)}</b></span>`)
  }
  el.barOhlc.innerHTML = cells.join('')
}

/**
 * Indicator readout at the crosshair, or the latest value when not hovering.
 *
 * One chip per indicator with its plots inside, rather than one entry per plot.
 * Flat, six indicators produced nineteen little dashes in a row that wrapped
 * across two lines with no grouping — you could not see where Bollinger ended and
 * MACD began. The chip carries the indicator's name once and its values together.
 */
function showLegend(state: HoverState) {
  showOhlc(state.bar)

  const chips: string[] = []
  for (const r of results) {
    const vals: string[] = []
    for (const plot of r.plots) {
      const v = state.values.get(plot.key) ?? plot.data[plot.data.length - 1]?.value
      if (v === undefined) continue
      vals.push(
        `<span class="v" title="${plot.label}">` +
          `<span class="swatch" style="background:${plot.color}"></span>` +
          `<span class="n">${compact(v)}</span></span>`,
      )
    }
    if (vals.length === 0) continue
    chips.push(
      `<span class="chip"><span class="title">${r.label}</span>` +
        `<span class="vals">${vals.join('')}</span></span>`,
    )
  }
  el.legend.innerHTML = chips.join('')
}

function showHeader() {
  el.barSymbol.textContent = symbol() || '—'
  el.barName.textContent = quote?.name ?? ''

  const series = chart.bars()
  const last = quote?.price ?? series[series.length - 1]?.close ?? null
  el.barLast.textContent = fmt(last)

  const prev = quote?.previousClose ?? series[series.length - 2]?.close ?? null
  if (last !== null && prev !== null && prev > 0) {
    const diff = last - prev
    const pct = (diff / prev) * 100
    const sign = diff >= 0 ? '+' : '−'
    el.barChange.textContent = `${sign}${Math.abs(diff).toFixed(2)} (${sign}${Math.abs(pct).toFixed(2)}%)`
    el.barChange.className = `chg ${diff >= 0 ? 'up' : 'down'}`
  } else {
    el.barChange.textContent = ''
  }
  showLegend({ bar: null, values: new Map() })
}

// ── Indicators ──────────────────────────────────────────────────────────────

function recomputeIndicators() {
  const bars = [...chart.bars()]
  results = []
  // Catalogue order, not click order, so panes do not shuffle when a template is
  // applied in a different sequence than the user first switched things on.
  for (const spec of INDICATORS) {
    const params = active.get(spec.id)
    if (!params) continue
    try {
      results.push(spec.build(bars, params, mode))
    } catch (e) {
      // One bad indicator must not blank the chart.
      console.error(`indicator ${spec.id} failed`, e)
    }
  }
  chart.setIndicators(results)
  el.indCount.textContent = active.size ? `${active.size}` : ''
  el.indicatorsBtn.className = active.size ? 'on' : ''
  showLegend({ bar: null, values: new Map() })
}

/** The active set as a template payload. */
function currentEntries(): TemplateEntry[] {
  const out: TemplateEntry[] = []
  for (const spec of INDICATORS) {
    const params = active.get(spec.id)
    if (params) out.push({ id: spec.id, params: { ...params } })
  }
  return out
}

function renderPicker() {
  const groups = new Map<string, IndicatorSpec[]>()
  for (const spec of INDICATORS) {
    const list = groups.get(spec.group) ?? []
    list.push(spec)
    groups.set(spec.group, list)
  }

  el.picker.innerHTML = ''
  for (const [group, specs] of groups) {
    const box = document.createElement('div')
    box.className = 'grp'
    const h = document.createElement('h4')
    h.textContent = group
    box.append(h)

    for (const spec of specs) {
      const row = document.createElement('div')
      row.className = 'row'

      const label = document.createElement('label')
      const cb = document.createElement('input')
      cb.type = 'checkbox'
      cb.checked = active.has(spec.id)
      cb.onchange = () => {
        if (cb.checked) active.set(spec.id, defaultParams(spec))
        else active.delete(spec.id)
        markModified()
        renderPicker()
        recomputeIndicators()
      }
      const text = document.createElement('span')
      text.textContent = spec.name
      label.append(cb, text)
      row.append(label)

      // Parameter boxes, only for what is switched on. Showing nineteen
      // indicators' worth of inputs at once is a wall nobody reads.
      const params = active.get(spec.id)
      if (params) {
        const ps = document.createElement('span')
        ps.className = 'params'
        for (const p of spec.params) {
          const input = document.createElement('input')
          input.type = 'number'
          input.className = 'p'
          input.value = String(params[p.key] ?? p.default)
          input.min = String(p.min)
          input.max = String(p.max)
          input.step = p.kind === 'multiplier' ? '0.1' : '1'
          input.title = p.label
          input.onchange = () => {
            const raw = Number(input.value)
            // Clamped here as well as in `sanitise`: a length of 100000 typed in
            // spins every bar through a window that can never fill.
            const v = Number.isFinite(raw) ? Math.min(p.max, Math.max(p.min, raw)) : p.default
            input.value = String(v)
            active.set(spec.id, { ...params, [p.key]: v })
            markModified()
            recomputeIndicators()
          }
          ps.append(input)
        }
        row.append(ps)
      }
      box.append(row)
    }
    el.picker.append(box)
  }
}

// ── Saved strategies ────────────────────────────────────────────────────────

function markModified() {
  // Applying a template then changing something means what is on screen is no
  // longer that template. Saying so avoids "I starred it but it opens different".
  if (appliedTemplate) {
    el.tplMsg.textContent = `Changed since “${appliedTemplate}” — save to keep it.`
    el.tplMsg.className = 'msg'
  }
}

function applyTemplate(t: ChartTemplate) {
  active.clear()
  for (const e of t.entries) active.set(e.id, { ...e.params })
  appliedTemplate = t.name
  el.tplName.value = t.name
  el.tplMsg.textContent = `Applied “${t.name}”.`
  el.tplMsg.className = 'msg ok'
  renderPicker()
  renderTemplates()
  recomputeIndicators()
}

function renderTemplates() {
  const templates = forDisplay(listTemplates())
  el.tplList.innerHTML = ''

  if (templates.length === 0) {
    const empty = document.createElement('p')
    empty.className = 'empty'
    empty.textContent = 'No saved strategies yet. Turn on some indicators, name the set, and save.'
    el.tplList.append(empty)
    return
  }

  for (const t of templates) {
    const row = document.createElement('div')
    row.className = 'tpl'

    const apply = document.createElement('button')
    apply.className = 'name'
    apply.textContent = t.name
    apply.title = `Apply — ${t.entries.map((e) => e.id).join(', ')}`
    apply.onclick = () => applyTemplate(t)

    const count = document.createElement('span')
    count.className = 'count'
    count.textContent = String(t.entries.length)

    const star = document.createElement('button')
    star.className = `icon${t.isDefault ? ' starred' : ''}`
    star.textContent = t.isDefault ? '★' : '☆'
    star.title = t.isDefault ? 'Opens by default — click to unset' : 'Open charts with this by default'
    star.onclick = () => {
      toggleDefault(t.key)
      renderTemplates()
    }

    const rename = document.createElement('button')
    rename.className = 'icon'
    rename.textContent = '✎'
    rename.title = 'Rename'
    rename.onclick = () => {
      const next = prompt(`Rename “${t.name}” to:`, t.name)
      if (next === null) return
      const res = renameTemplate(t.key, next)
      if (!res.ok) {
        el.tplMsg.textContent = res.error ?? 'Could not rename that.'
        el.tplMsg.className = 'msg bad'
        return
      }
      if (appliedTemplate === t.name) appliedTemplate = next.trim()
      renderTemplates()
    }

    const del = document.createElement('button')
    del.className = 'icon danger'
    del.textContent = '🗑'
    del.title = 'Delete'
    del.onclick = () => {
      // Confirmed because there is no undo and the row is one click from Apply.
      if (!confirm(`Delete the strategy “${t.name}”?`)) return
      deleteTemplate(t.key)
      if (appliedTemplate === t.name) appliedTemplate = null
      renderTemplates()
    }

    row.append(apply, count, star, rename, del)
    el.tplList.append(row)
  }
}

el.tplSave.onclick = () => {
  const res = saveTemplate(el.tplName.value, currentEntries())
  if (!res.ok) {
    el.tplMsg.textContent = res.error ?? 'Could not save that.'
    el.tplMsg.className = 'msg bad'
    return
  }
  appliedTemplate = res.template!.name
  el.tplMsg.textContent = `Saved “${res.template!.name}”.`
  el.tplMsg.className = 'msg ok'
  renderTemplates()
}

el.tplName.onkeydown = (e) => {
  if (e.key === 'Enter') el.tplSave.click()
}

// ── Data ────────────────────────────────────────────────────────────────────

async function load() {
  if (!symbol()) return
  el.load.disabled = true
  el.statErr.textContent = ''
  const p = period()
  chart.setCurrency(currencyFor(market()))
  chart.setTimeframe(p.interval)
  chart.setSubtitle(`${symbol()} · ${p.label}`)

  try {
    // Both at once: history is the body of the chart, the quote is its edge.
    const [history, q] = await Promise.all([
      fetchHistory(symbol(), market(), p),
      fetchLiveQuote(symbol(), market()),
    ])
    quote = q

    chart.setCandles(history)
    if (q) chart.pushTick({ time: q.time, price: q.price })
    recomputeIndicators()

    el.statBars.textContent = `${chart.bars().length} bars · ${p.interval}`
    el.statSource.textContent = q
      ? `${q.source}${q.fromCache ? ' · quotes_cache (engine price)' : ' · live'}`
      : 'history only'
    if (history.length === 0) {
      el.statErr.textContent = 'No history for that symbol and timeframe.'
    }
    showHeader()
  } catch (e) {
    el.statErr.textContent = e instanceof Error ? e.message : String(e)
  } finally {
    el.load.disabled = false
  }
}

async function tick() {
  const q = await fetchLiveQuote(symbol(), market())
  if (!q) return
  quote = q
  chart.pushTick({ time: q.time, price: q.price })
  el.statTick.textContent = `tick ${new Date().toLocaleTimeString()} · ${fmt(q.price)}`
  showHeader()
}

function noteHonesty() {
  el.statNote.textContent = isHonestCandleTimeframe(period().interval)
    ? ''
    : 'Our own samples are 1/min, so OHLC at this bar size is vendor data only'
}

function renderTimeframes() {
  el.timeframes.innerHTML = ''
  // Periods, not intervals: "3M" is what someone wants to say, and it also carries
  // the bar size and the vendor range that make it work.
  for (const p of periodsFor(market())) {
    const b = document.createElement('button')
    b.textContent = p.label
    b.title = `${p.interval} bars`
    b.className = p.id === period().id ? 'on' : ''
    b.onclick = () => {
      periodId = p.id
      renderTimeframes()
      noteHonesty()
      void load()
    }
    el.timeframes.append(b)
  }
}

// ── Controls ────────────────────────────────────────────────────────────────

el.load.onclick = () => void load()
el.symbol.onkeydown = (e) => {
  if (e.key === 'Enter') void load()
}
el.market.onchange = () => {
  // Crypto offers fewer periods, so the buttons are rebuilt: a 5Y selection made
  // on a stock is not something CoinGecko will serve.
  renderTimeframes()
  noteHonesty()
  void load()
}

el.indicatorsBtn.onclick = () => el.tray.classList.toggle('open')

function setStyle(next: SeriesStyle) {
  style = next
  chart.setStyle(next)
  el.styleCandles.className = next === 'candles' ? 'on' : ''
  el.styleLine.className = next === 'line' ? 'on' : ''
}
el.styleCandles.onclick = () => setStyle('candles')
el.styleLine.onclick = () => setStyle('line')

el.live.onclick = () => {
  live = !live
  el.live.className = live ? 'on' : ''
  if (!live) el.statTick.textContent = ''
  if (live) {
    // 5s, not 1s. `refresh-quotes` rewrites a row once a minute, so polling
    // faster only burns requests reading the same number back.
    void tick()
    liveTimer = window.setInterval(() => void tick(), 5000)
  } else if (liveTimer) {
    clearInterval(liveTimer)
    liveTimer = undefined
  }
}

el.theme.onclick = () => {
  mode = mode === 'light' ? 'dark' : 'light'
  el.theme.textContent = mode === 'light' ? 'Dark' : 'Light'
  document.body.classList.toggle('dark', mode === 'dark')
  chart.setMode(mode)
  // Several indicators take their colours from the palette, so they are rebuilt.
  recomputeIndicators()
}

// A starred strategy is what "default" means: the chart opens with it already on.
const startup = defaultTemplate()
if (startup) {
  for (const e of startup.entries) active.set(e.id, { ...e.params })
  appliedTemplate = startup.name
  el.tplName.value = startup.name
}

renderTimeframes()
renderPicker()
renderTemplates()
noteHonesty()
void load()
