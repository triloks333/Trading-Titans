/*
 * The public surface of the chart package.
 *
 * Both clients import from here and nothing else, so `src/core` and `src/data`
 * stay free to move. `src/demo` is the dev harness and is deliberately NOT
 * exported — it is not part of the product.
 *
 * Nothing in this package imports React or knows it might be inside a WebView.
 * That is what lets the web app wrap it in a component and the Flutter client load
 * it as a bundled asset while both render from one implementation. The chart this
 * replaces existed three times over — a TradingView embed on Android,
 * `interactive_chart` on Flutter web, `lightweight-charts` in the React app — and
 * the three disagreed about prices, styling and which symbol was even shown.
 */

export { compactValue, createTitanChart, readLegend } from './core/chart'
export type { HoverState, LegendRow, TitanChart, TitanChartOptions } from './core/chart'

export { loadDrawings, sanitiseDrawings, saveDrawings } from './core/drawings'
export type { Drawing, DrawingAnchor, DrawingKind, DrawingLayer } from './core/drawings'

export { DEFAULT_PERIOD, periodFor, periodsFor } from './core/periods'
export type { ChartPeriod, PeriodId } from './core/periods'

export { INDICATORS, INDICATOR_BY_ID, defaultParams } from './core/registry'
export type { IndicatorSpec, ParamSpec } from './core/registry'
export type { IndicatorResult } from './core/indicators'

export {
  defaultTemplate,
  deleteTemplate,
  listTemplates,
  renameTemplate,
  saveTemplate,
  toggleDefault,
} from './data/templates'
export type { ChartTemplate, TemplateEntry } from './core/templates'
export { cleanName, forDisplay, MAX_NAME_LENGTH } from './core/templates'

export { fetchHistory } from './data/history'
export { fetchLiveQuote } from './data/quote'
export type { LiveQuote } from './data/quote'

export { fxFactor, isHonestCandleTimeframe, scalePrices } from './core/aggregate'
export { cacheKeyFor, historySymbol } from './core/symbols'
export { BRAND_NAME, MARK_DATA_URI } from './core/brand'
export { CURRENCY_SYMBOL, FONT_BRAND, FONT_NUM, FONT_UI, palette } from './core/theme'
export type { ChartPalette } from './core/theme'

export { TIMEFRAMES } from './core/types'
export type {
  Candle,
  Currency,
  Market,
  Sample,
  SeriesStyle,
  ThemeMode,
  Timeframe,
} from './core/types'
