import type { SeriesStyle } from '../core/types'

/*
 * The two chart settings that were never remembered: bar size and series style.
 *
 * Saved indicator templates and drawings already persist (see templates.ts and
 * core/drawings.ts). Timeframe and candles-vs-line did not, so every chart opened
 * on 1D candles no matter what the user had been looking at a second earlier —
 * pick 15m, tap into another instrument, and you were back on daily.
 *
 * LOCAL STORAGE, PER DEVICE, DELIBERATELY
 * Same reasoning as templates.ts, and the user chose it explicitly: works for
 * guests, works offline, works in the WebView, needs no table, no RLS and no
 * migration. The upgrade path is the same `chart_*` table keyed on `user_id`.
 *
 * GLOBAL, NOT PER SYMBOL
 * A bar size is how someone reads a chart, not a property of the instrument, and
 * it is how Zerodha, Groww and TradingView all behave: set 15m once and every
 * chart opens on 15m. Keying this per symbol would mean the timeframe silently
 * changed as you moved between instruments, which is the complaint the timeframe
 * row already had.
 */

const KEY = 'tt.chart.prefs.v1'

export interface ChartPrefs {
  /**
   * A period id, kept as a plain string rather than PeriodId on purpose.
   *
   * Storage can hold an id that has since been retired — exactly what happened
   * with '3M' when the row became bar sizes only. Validating it here would mean a
   * second copy of the period list; instead the caller passes it through
   * `periodFor`, which already falls back to the default for anything it does not
   * recognise. One validator, and it is the one the chart actually uses.
   */
  period?: string
  style?: SeriesStyle
}

/** Never let a storage failure take the chart down with it. */
export function loadPrefs(): ChartPrefs {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return {}
    const parsed: unknown = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') return {}
    const p = parsed as Record<string, unknown>
    return {
      period: typeof p.period === 'string' && p.period ? p.period : undefined,
      // Only the two real values. Anything else — a typo, a style from a newer
      // build — is dropped so the chart falls back to candles rather than being
      // handed a series type it cannot construct.
      style: p.style === 'line' || p.style === 'candles' ? p.style : undefined,
    }
  } catch {
    // Private browsing, a full quota, or hand-mangled JSON.
    return {}
  }
}

/**
 * Merges [patch] into what is already stored.
 *
 * A merge rather than a replace so saving the timeframe cannot wipe the style,
 * which is what a `setItem(JSON.stringify({period}))` would quietly do the first
 * time only one of them changed.
 */
export function savePrefs(patch: ChartPrefs): void {
  try {
    localStorage.setItem(KEY, JSON.stringify({ ...loadPrefs(), ...patch }))
  } catch {
    // The setting is already applied in memory, so the chart is correct; only
    // remembering it for next time is lost, which is not worth interrupting for.
  }
}
