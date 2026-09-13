import type { ThemeMode } from './types'

/*
 * Palette, transcribed from app/lib/core/theme.dart.
 *
 * Same hexes as the app, both modes, so a chart never looks pasted in from
 * somewhere else. Note the legacy names in the Dart: `imperialGold` is
 * #1A73E8 — blue. The brand moved from gold to blue and the identifiers did not
 * follow, so the values here are named for what they ARE rather than what the
 * Dart calls them.
 *
 * ponytail: hand-transcribed rather than generated from the Dart. The ceiling is
 * that a palette change needs editing in two places; the upgrade path is emitting
 * a shared JSON of tokens from theme.dart at build time, which is not worth it
 * for eleven colours that have changed once in the project's life.
 */

export interface ChartPalette {
  /** Pane background. AppColors.pureWhite. */
  background: string
  /** Surrounding surface, for the harness and any chrome. AppColors.parchment. */
  surface: string
  /** Primary text. AppColors.ink. */
  text: string
  /** Secondary text and axis labels. AppColors.ink4. */
  textMuted: string
  /** Axis borders and pane separators. AppColors.birch. */
  border: string
  /**
   * Grid lines, deliberately fainter than [border].
   *
   * At full birch the grid competes with the candles and the chart reads as a
   * spreadsheet. This is the same hue at low alpha so it recedes.
   */
  gridLine: string
  /** Brand accent, used for the line series. AppColors.imperialGold (#1A73E8). */
  accent: string
  /** Rising. AppColors.bull. */
  up: string
  /** Falling. AppColors.bear. */
  down: string
  /** Crosshair. */
  crosshair: string
  /**
   * Candle wicks, a shade deeper than the bodies.
   *
   * With wick and body the same colour a long wick reads as a separate mark
   * floating above the candle. Deepening it keeps the two visually attached while
   * still letting the body dominate.
   */
  wickUp: string
  wickDown: string
}

const LIGHT: ChartPalette = {
  background: '#FFFFFF',
  surface: '#F4F7FB',
  text: '#0B1B2B',
  textMuted: '#627D98',
  border: '#DDE7F2',
  gridLine: 'rgba(221, 231, 242, 0.55)',
  accent: '#1A73E8',
  up: '#0F9D58',
  down: '#D93025',
  crosshair: '#627D98',
  wickUp: '#0B7040',
  wickDown: '#A2211A',
}

const DARK: ChartPalette = {
  background: '#162544',
  surface: '#0D1527',
  text: '#F4F7FB',
  textMuted: '#91A3B8',
  border: '#2D4676',
  gridLine: 'rgba(45, 70, 118, 0.5)',
  accent: '#3B8BF2',
  up: '#26B36C',
  down: '#EF4A3F',
  crosshair: '#91A3B8',
  // Brighter than the bodies on dark, not deeper: on #162544 a darker wick
  // disappears into the background instead of reading as part of the candle.
  wickUp: '#5AD095',
  wickDown: '#F5837A',
}

export function palette(mode: ThemeMode): ChartPalette {
  return mode === 'dark' ? DARK : LIGHT
}

/** Currency symbols, matching Money.rupee / Money.dollar in the app. */
export const CURRENCY_SYMBOL = { INR: '\u20b9', USD: '\u0024' } as const

/*
 * Type.
 *
 * No web fonts, and that is a hard constraint rather than a preference: the
 * Flutter build has to be one self-contained asset that works offline, so a
 * chart whose axis labels only render correctly when online is not shippable.
 *
 * Both stacks below therefore name faces that are ALREADY on the machine — IBM
 * Plex where a developer has it, then the platform's own monospace (SF Mono on
 * macOS, Consolas on Windows, Roboto Mono on Android). Nothing is fetched, and
 * the fallback is never Courier.
 */

/** UI text: labels, the axis, anything that is words. */
export const FONT_UI =
  '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif'

/**
 * Every number on the chart.
 *
 * Monospaced for a real reason, not for the look: a price axis where the digits
 * do not share a width makes 1,322 and 1,822 different lengths, and the column
 * shimmers as the last bar updates. Tabular figures hold the axis still.
 */
export const FONT_NUM =
  '"IBM Plex Mono", ui-monospace, "SF Mono", SFMono-Regular, "Cascadia Mono", Consolas, "Roboto Mono", monospace'

/** The wordmark. Serif italic, matching the site's Playfair treatment. */
export const FONT_BRAND = '"Playfair Display", Georgia, "Times New Roman", serif'
