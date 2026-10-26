import { createTitanChart, type TitanChart } from '../core/chart'
import { INDICATOR_BY_ID, defaultParams } from '../core/registry'
import { DEFAULT_PERIOD, periodFor } from '../core/periods'
import { palette } from '../core/theme'
import { defaultTemplate } from '../data/templates'
import { loadPrefs, savePrefs } from '../data/prefs'
import { sanitise, type TemplateEntry } from '../core/templates'
import { cacheKeyFor } from '../core/symbols'
import { fetchHistory } from '../data/history'
import { fetchLiveQuote } from '../data/quote'
import { mountControls, setActiveEntries } from './controls'
import { compactValue, readLegend } from '../core/chart'
import { fxFactor, scalePrices } from '../core/aggregate'
import { loadDrawings, saveDrawings } from '../core/drawings'
import type { DrawingKind } from '../core/drawings'
import type { HoverState } from '../core/chart'
import type { IndicatorResult } from '../core/indicators'
import type { Candle, Currency, Market, SeriesStyle, ThemeMode } from '../core/types'

/*
 * The bridge between Flutter and the chart.
 *
 * Flutter owns every control — the timeframe row, the indicator picker, the saved
 * strategies — because those are widgets that should match the rest of the app and
 * take a thumb properly. This file owns drawing and fetching, and exposes a small
 * command surface on `window.ttChart` that Flutter calls with `runJavaScript`.
 *
 * Every entry point is defensive. `runJavaScript` is a stringly-typed channel from
 * Dart: a typo in a symbol, a stale template id or a renamed indicator arrives here
 * as ordinary data, and the only sane failure is to report it back and keep
 * drawing. A thrown exception inside a WebView is invisible to the user and to
 * Flutter alike — they just see a chart that stopped.
 */

declare global {
  interface Window {
    ttChart: TtChartApi
    /** Injected by webview_flutter as a JavaScriptChannel. */
    TitanChartHost?: { postMessage(message: string): void }
  }
}

interface TtChartApi {
  setTheme(mode: string): void
  setStyle(style: string): void
  setIndicators(json: string): void
  /** Omitting the period leaves the default to `periods.ts`, so Flutter holds no
   * second copy of it. */
  load(symbol: string, market: string, periodId?: string): void
  refreshQuote(): void
  pushTick(price: number, time?: number): void
  /**
   * The currency to draw in, and rupees per dollar to get there.
   *
   * Both from the host because the host already has them: in the app they are
   * `CurrencyService.displayCurrency` and `.usdInr`, the same pair `Money` formats
   * the header price with. Pass a rate of 0 to mean "unknown", which draws the
   * instrument's own currency rather than guessing one.
   */
  setCurrency(display: string, usdInr: number): void
}

const container = document.getElementById('chart')!
const controlsRoot = document.getElementById('controls')!
const legendRoot = document.getElementById('legend')!
let chart: TitanChart | null = null
let mode: ThemeMode = 'light'
/** Bar size and series style as this device last left them. See data/prefs.ts. */
const savedPrefs = loadPrefs()
let style: SeriesStyle = savedPrefs.style ?? 'candles'
let symbol = ''
let market: Market = 'stock'
// The saved bar size, normalised through periodFor so this is ALWAYS a real id.
//
// Never a literal, and never a raw stored string. This was initialised to '3M', an
// id that stopped existing when the period row became bar sizes only. periodFor
// falls back when drawing, so the canvas was always right and the bug was
// invisible there — but currentPeriod() handed '3M' to the chip row, which matches
// nothing, so the chart opened with no timeframe highlighted at all. A retired id
// coming back out of localStorage would reproduce that exactly, so it is
// normalised on the way in rather than trusted. Every market offers the same set,
// so 'stock' is a safe lens to validate through before the real market is known.
let periodId: string = periodFor('stock', savedPrefs.period ?? DEFAULT_PERIOD).id
let entries: TemplateEntry[] = []
let results: IndicatorResult[] = []
/** Guards against a slow fetch landing after the user has moved on. */
let loadToken = 0
/** What the user chose to read prices in. Rupees until the host says otherwise. */
let display: Currency = 'INR'
/** Rupees per dollar, from the host. 0 means unknown, so do not convert. */
let usdInr = 0

/**
 * The currency this instrument's own prices arrive in.
 *
 * `quotes_cache` holds US equities in dollars and everything else in rupees —
 * crypto included, because `market-quote` converts it upstream before caching.
 * Same rule as `Money.sourceFor` in the app and `currencyFor` in the web app.
 */
function nativeCurrency(): Currency {
  return market === 'us_stock' ? 'USD' : 'INR'
}

/** Multiplier from the instrument's own currency into the one being displayed. */
function factor(): number {
  return fxFactor(nativeCurrency(), display, usdInr)
}

/**
 * The currency to LABEL the axis with.
 *
 * Derived from the factor rather than from the preference, so the label can never
 * outrun the arithmetic: with no rate the factor is 1, the prices are still the
 * instrument's own, and this says so instead of putting a dollar sign on rupees.
 */
function shownCurrency(): Currency {
  return factor() === 1 ? nativeCurrency() : display
}

const NO_HOVER: HoverState = { bar: null, values: new Map() }

/**
 * The last crosshair state, so a live tick can refresh the legend without
 * stomping what the user is currently holding a finger on.
 *
 * Re-rendering with the same state is a no-op visually; re-rendering with
 * NO_HOVER re-reads the latest bar, which is what makes the OHLC close track the
 * live price.
 */
let lastHover: HoverState = NO_HOVER

/**
 * Indicator values, as chips above the chart.
 *
 * Rendered here rather than posted to Flutter for Dart to draw: the crosshair fires
 * on every pointer move, and a bridge message per move to redraw a widget tree is a
 * lot of traffic for a row of text that the page already has the numbers for. The
 * rows themselves come from `readLegend`, the same function the web app uses, so the
 * two clients read a legend identically.
 */
/**
 * A price with as many decimals as it actually needs.
 *
 * Mirrors `precisionFor` in core/chart.ts, which sets the axis, but decides per
 * value rather than per series. `compactValue` is wrong for prices: it rounds
 * anything under 1 to four places, which flattens SHIB at 0.00002 to "0.0000".
 */
function priceText(v: number): string {
  const a = Math.abs(v)
  return v.toFixed(a >= 1 ? 2 : a >= 0.01 ? 4 : 8)
}

/**
 * The tapped bar's open, high, low and close, as one chip.
 *
 * The crosshair already handed us the whole bar — `HoverState.bar` is read from
 * the chart's own candle array precisely so it still carries a full OHLC in line
 * mode — but `readLegend` only ever looked at indicator plot values, so the bar
 * was thrown away and a tap showed nothing but the axis price label.
 *
 * Built from the existing `.tt-leg*` classes so it needs no new CSS and sits in
 * the same row as the indicator chips.
 */
function ohlcChip(bar: Candle): HTMLElement {
  const chip = document.createElement('span')
  chip.className = 'tt-leg'
  const colours = palette(mode)
  for (const [label, v] of [
    ['O', bar.open],
    ['H', bar.high],
    ['L', bar.low],
    ['C', bar.close],
  ] as [string, number][]) {
    const name = document.createElement('span')
    name.className = 'tt-leg-name'
    name.textContent = label
    const num = document.createElement('span')
    num.className = 'tt-leg-num'
    num.textContent = priceText(v)
    // Only the close is tinted. Colouring all four reads as four separate
    // signals when it is one candle, and the direction is a property of the
    // candle, not of its high. palette() rather than the --up/--down CSS vars
    // because the dark theme does not override those, so a dark chart would tint
    // the close with the light palette while the candle beside it used the dark.
    if (label === 'C') {
      num.style.color = bar.close >= bar.open ? colours.up : colours.down
    }
    chip.append(name, num)
  }
  return chip
}

function renderLegend(state: HoverState): void {
  lastHover = state
  const rows = readLegend(results, state)
  // The bar under the crosshair, or the most recent one when the pointer is
  // away, so lifting a thumb leaves the last price readable instead of blanking
  // the row.
  const bar = state.bar ?? chart?.lastBar() ?? null
  if (!bar && rows.length === 0) {
    legendRoot.hidden = true
    legendRoot.textContent = ''
    return
  }
  legendRoot.hidden = false
  // textContent per node rather than one interpolated string: an indicator label
  // is our own, but building HTML by concatenation is the habit that eventually
  // meets a value that is not.
  legendRoot.textContent = ''
  // Price first, indicators after: the bar is what the tap was aimed at.
  if (bar) legendRoot.append(ohlcChip(bar))
  for (const row of rows) {
    const chip = document.createElement('span')
    chip.className = 'tt-leg'
    const name = document.createElement('span')
    name.className = 'tt-leg-name'
    name.textContent = row.label
    chip.append(name)
    for (const v of row.vals) {
      const dot = document.createElement('i')
      dot.className = 'tt-leg-dot'
      dot.style.background = v.color
      const num = document.createElement('span')
      num.className = 'tt-leg-num'
      num.textContent = compactValue(v.v)
      chip.append(dot, num)
    }
    legendRoot.append(chip)
  }
}

/** Tells Flutter what happened. Silent when the channel is absent, as in a browser. */
function send(type: string, payload: Record<string, unknown> = {}): void {
  try {
    window.TitanChartHost?.postMessage(JSON.stringify({ type, ...payload }))
  } catch {
    // The host is gone or the payload is not serialisable. Nothing useful to do
    // from inside the page.
  }
}

function ensureChart(): TitanChart {
  if (chart) return chart
  chart = createTitanChart(container, {
    mode,
    style,
    timeframe: periodFor(market, periodId).interval,
    currency: shownCurrency(),
    onHover: renderLegend,
  })
  return chart
}

/** Applies the current entry list to the chart. */
function paintIndicators(): void {
  const c = ensureChart()
  const bars = [...c.bars()]
  results = []
  for (const entry of entries) {
    const spec = INDICATOR_BY_ID.get(entry.id)
    // A retired or misspelled id is dropped, not fatal.
    if (!spec) continue
    try {
      results.push(spec.build(bars, { ...defaultParams(spec), ...entry.params }, mode))
    } catch (e) {
      send('warn', { message: `indicator ${entry.id} failed`, detail: String(e) })
    }
  }
  c.setIndicators(results)
  renderLegend(NO_HOVER)
}

async function load(): Promise<void> {
  if (!symbol) return
  const token = ++loadToken
  const period = periodFor(market, periodId)
  const c = ensureChart()
  c.setCurrency(shownCurrency())
  c.setTimeframe(period.interval)
  // The instrument actually drawn, not the string Flutter passed. An option
  // charts its underlying, so captioning it `NIFTY-2026-09-30-25000-CE` would
  // name a contract whose price is nowhere on the chart. `cacheKeyFor` already
  // collapses derivatives, index aliases and CoinDCX perpetuals to the plain
  // name, which is exactly the human label wanted here.
  c.setSubtitle(`${cacheKeyFor(symbol, market)} · ${period.label}`)
  send('loading')

  try {
    // Both at once: history is the body of the chart, the quote is its edge.
    const [candles, quote] = await Promise.all([
      fetchHistory(symbol, market, period),
      fetchLiveQuote(symbol, market).catch(() => null),
    ])
    // A later request has already started; this result is stale.
    if (token !== loadToken) return

    // Converted once, here, on the way in. Everything downstream — the axis, the
    // crosshair, the legend, the last-price badge and every price-pane indicator —
    // then reads the same units without knowing a conversion happened.
    const k = factor()
    c.setCandles(scalePrices(candles, k))
    if (quote) c.pushTick({ time: quote.time, price: quote.price * k })
    paintIndicators()
    // After the series, so the price scale exists to place anchors against.
    restoreDrawings()

    send('loaded', {
      bars: c.bars().length,
      empty: candles.length === 0,
      currency: shownCurrency(),
      price: quote?.price ?? null,
      previousClose: quote?.previousClose ?? null,
      name: quote?.name ?? null,
      source: quote?.source ?? null,
      fromCache: quote?.fromCache ?? false,
      interval: period.interval,
    })
  } catch (e) {
    if (token !== loadToken) return
    // Reported, never thrown: Flutter shows the retry, and a throw here would be
    // invisible on both sides.
    send('error', { message: e instanceof Error ? e.message : String(e) })
  }
}

window.ttChart = {
  setTheme(next) {
    const wanted: ThemeMode = next === 'dark' ? 'dark' : 'light'
    if (wanted === mode) return
    mode = wanted
    // The class, not an inline background: every colour on this page — the period
    // chips, the legend, the indicators sheet — comes from a custom property under
    // `html.dark`. Setting only the background turned the canvas dark and left the
    // controls around it light.
    document.documentElement.classList.toggle('dark', mode === 'dark')
    if (chart) {
      chart.drawings().setMode(mode)
      chart.setMode(mode)
      // Several indicators take their colours from the palette.
      paintIndicators()
    }
  },

  setStyle(next) {
    const wanted: SeriesStyle = next === 'line' ? 'line' : 'candles'
    if (wanted === style) return
    style = wanted
    savePrefs({ style: wanted })
    chart?.setStyle(style)
  },

  /**
   * Replaces the indicator set.
   *
   * Takes JSON rather than a Dart list because `runJavaScript` carries a string.
   * Reused through `sanitise` so the WebView applies exactly the same rules as the
   * web app: unknown ids dropped, parameters clamped to the spec's range, missing
   * parameters defaulted.
   */
  setIndicators(json) {
    try {
      const parsed: unknown = JSON.parse(json)
      const list = Array.isArray(parsed) ? parsed : []
      // `sanitise` wants a whole template, so wrap the entries in a throwaway one.
      // Its name is never shown; it exists to satisfy the shared validator rather
      // than to duplicate it here.
      const t = sanitise({ name: 'live', entries: list })
      entries = t?.entries ?? []
    } catch (e) {
      send('warn', { message: 'setIndicators: bad JSON', detail: String(e) })
      entries = []
    }
    paintIndicators()
  },

  setCurrency(nextDisplay, nextRate) {
    const wanted: Currency = String(nextDisplay).toUpperCase() === 'USD' ? 'USD' : 'INR'
    const rate = Number(nextRate)
    const cleanRate = Number.isFinite(rate) && rate > 0 ? rate : 0
    if (wanted === display && cleanRate === usdInr) return
    display = wanted
    usdInr = cleanRate
    // A refetch rather than rescaling what is already drawn. The chart holds one
    // candle array and rescaling in place would mean keeping a second copy in the
    // instrument's own currency to convert from — two arrays of the same bars, the
    // desync this package's own notes warn about. A currency change is a settings
    // toggle, not something that happens while reading a chart, so one more fetch
    // is the cheaper mistake.
    if (symbol) void load()
  },

  load(nextSymbol, nextMarket, nextPeriod) {
    symbol = String(nextSymbol ?? '').trim().toUpperCase()
    market = (['stock', 'us_stock', 'crypto'] as const).includes(nextMarket as Market)
      ? (nextMarket as Market)
      : 'stock'
    // Falls back to the CURRENT period, not to the default. Flutter calls this
    // without a period on every instrument change, so defaulting here is what used
    // to snap the chart back to 1D every time you opened a different stock — the
    // selected timeframe never survived leaving the screen.
    periodId = String(nextPeriod ?? periodId)
    // Rebuild the chips for the new instrument. Every market now offers the same
    // seven bar sizes — crypto included, since history moved to CoinDCX — so this
    // no longer changes the list, only the highlighted chip.
    controls.refresh()
    void load()
  },

  refreshQuote() {
    if (!symbol) return
    void fetchLiveQuote(symbol, market)
      .then((q) => {
        if (!q || !chart) return
        // Same conversion as the series it folds into. A raw tick here would put
        // one rupee bar on the end of a dollar chart, which reads as a spike.
        chart.pushTick({ time: q.time, price: q.price * factor() })
        renderLegend(lastHover)
      })
      .catch(() => {
        // A failed poll is not worth reporting: another one is coming and the
        // chart still holds the last good price.
      })
  },

  pushTick(price: number, time?: number) {
    if (!chart || price <= 0) return
    const t = time ?? Math.floor(Date.now() / 1000)
    chart.pushTick({ time: t, price: price * factor() })
    renderLegend(lastHover)
  },
}

// A starred strategy is what "default" means: the chart opens with it applied,
// before the first fetch, so it is never drawn twice.
const startup = defaultTemplate()
if (startup) {
  entries = startup.entries
  setActiveEntries(startup.entries)
}

const controls = mountControls(controlsRoot, {
  market: () => market,
  currentPeriod: () => periodId,
  onPeriod(id) {
    periodId = id
    savePrefs({ period: id })
    void load()
  },
  onIndicators(next) {
    entries = next
    paintIndicators()
  },
  onStyle(next) {
    style = next
    savePrefs({ style: next })
    chart?.setStyle(next)
  },
})

/*
 * Drawing tools.
 *
 * Anchored in time and price, so a level drawn on the 1h chart is the same level on
 * the 5m one — which is why they are keyed on the symbol alone and reloaded on every
 * `load` rather than being tied to a timeframe.
 */
const drawBar = document.getElementById('draw')!

function wireDrawing(): void {
  const layer = ensureChart().drawings()
  layer.onChange((all) => {
    if (symbol) saveDrawings(cacheKeyFor(symbol, market), all)
  })

  const buttons = drawBar.querySelectorAll<HTMLButtonElement>('[data-tool]')

  // Driven by the layer rather than set on click: finishing a line disarms the tool
  // from inside, and a button left lit for an inactive tool is how a user ends up
  // tapping the chart expecting to draw.
  layer.onToolChange((kind) => {
    for (const b of buttons) b.classList.toggle('on', b.dataset.tool === kind)
  })

  for (const b of buttons) {
    b.addEventListener('click', () => {
      const kind = b.dataset.tool as DrawingKind
      // Tapping the armed tool again disarms it, so a mis-tap does not leave the
      // chart unpannable with no obvious way out.
      layer.setTool(layer.activeTool() === kind ? null : kind)
    })
  }

  document.getElementById('drawDel')!.addEventListener('click', () => {
    // Falls back to clearing when nothing is selected: on a phone, selecting a thin
    // line to delete it is fiddly, and a dead button is worse than a broad one.
    if (!layer.deleteSelected()) layer.clear()
  })
}

/** Restores this instrument's drawings. Called after each successful load. */
function restoreDrawings(): void {
  if (!symbol) return
  ensureChart().drawings().replaceAll(loadDrawings(cacheKeyFor(symbol, market)))
}

wireDrawing()

// Flutter waits for this before issuing its first `load`, so a command cannot
// arrive before `window.ttChart` exists.
send('ready')
