import { FONT_BRAND, FONT_UI } from './theme'
import type { ThemeMode } from './types'

/*
 * Branding.
 *
 * Two pieces, deliberately:
 *
 *   1. A canvas watermark, applied through lightweight-charts' own
 *      `createTextWatermark`. It is INSIDE the chart canvas, so it survives a
 *      screenshot — which is the whole point of a watermark on a chart people
 *      share.
 *   2. A DOM badge with the mark and the wordmark, pinned to the pane corner.
 *      DOM rather than canvas because it is crisp at any pixel ratio and because
 *      both hosts are a DOM: the React app and the Flutter WebView get the same
 *      badge with no per-platform drawing code.
 *
 * WHICH LOGO
 * The mark below is `website/public/logo.svg` — the amber Surya Yantra, which is
 * what the live site and the Play listing use. Note the mismatch with the UI
 * palette: `theme.dart` moved the brand to blue (#1A73E8) and kept the old
 * identifiers, so `AppColors.imperialGold` is now a blue. The logo file never
 * followed. Using the live mark rather than inventing a blue one is the right call
 * for a chart, but it is worth someone deciding which of the two is the brand.
 *
 * Inlined as a data URI rather than fetched. The Flutter build has to be a single
 * self-contained asset, and a chart that shows its logo only when online is worse
 * than one that never does.
 */

/**
 * The Surya Yantra mark, reduced to what reads at 20px.
 *
 * The full file has 40-odd elements — eight sun rays, two ring circles, eight
 * corona dots, eight lotus petals and a Rupee glyph — and below about 32px they
 * merge into a muddy square. This keeps the silhouette that identifies it: the
 * rounded amber tile, four cardinal rays, the bindu and the Rupee.
 */
const MARK = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" rx="114" fill="#BA7517"/>
<rect x="40" y="40" width="432" height="432" rx="86" fill="#6B3A08"/>
<circle cx="256" cy="256" r="168" fill="none" stroke="#EF9F27" stroke-width="6"/>
<polygon points="256,72 240,138 272,138" fill="#FAC775"/>
<polygon points="256,440 240,374 272,374" fill="#FAC775"/>
<polygon points="72,256 138,240 138,272" fill="#FAC775"/>
<polygon points="440,256 374,240 374,272" fill="#FAC775"/>
<circle cx="256" cy="256" r="88" fill="#EF9F27"/>
<path d="M4 3.06h2.726c1.22 0 2.12.575 2.325 1.724H4v1.051h5.051C8.855 7.001 8 7.558 6.788 7.558H4v1.317L8.437 14h2.11L6.095 8.884h.855c2.316-.018 3.465-1.476 3.688-3.049H12V4.784h-1.345c-.08-.778-.357-1.335-.793-1.732H12V2H4z" fill="#412402" transform="translate(256,256) scale(9.5) translate(-8,-8)"/>
</svg>`

/** The mark as a data URI, safe in a `src` and in CSS `url()`. */
export const MARK_DATA_URI = `data:image/svg+xml;utf8,${encodeURIComponent(MARK)}`

export const BRAND_NAME = 'Trading Titans'

/**
 * Watermark text options for `createTextWatermark`.
 *
 * Two lines: the wordmark, and the instrument underneath. Alpha is low on purpose
 * — a watermark that competes with the candles is a worse chart, and the point is
 * attribution on a screenshot, not decoration.
 */
export function watermarkOptions(mode: ThemeMode, subtitle: string) {
  const tint = mode === 'dark' ? '255, 255, 255' : '11, 27, 43'
  return {
    visible: true,
    horzAlign: 'center' as const,
    vertAlign: 'center' as const,
    lines: [
      {
        text: BRAND_NAME,
        // 0.055, down from 0.10. At the higher value the wordmark read as a layer
        // in front of the candles rather than behind them, and on a dense daily
        // chart it cut straight through the price action. A watermark's job is
        // attribution on a screenshot, not presence.
        color: `rgba(${tint}, 0.055)`,
        fontSize: 46,
        fontStyle: 'italic',
        fontFamily: FONT_BRAND,
      },
      {
        text: subtitle,
        color: `rgba(${tint}, 0.05)`,
        fontSize: 13,
        fontFamily: FONT_UI,
      },
    ],
  }
}

/**
 * Title for a study pane, drawn as that pane's own watermark.
 *
 * Pinned top-left at full weight, which is a different job from the brand
 * watermark and only shares the mechanism. Without this the panes are anonymous:
 * three stacked oscillators with no way to tell RSI from Stochastic except by
 * matching colours against the legend. It is the single biggest readability gap
 * in the chart, and lightweight-charts already has a per-pane text layer, so it
 * costs nothing to close.
 */
export function paneTitleOptions(mode: ThemeMode, title: string) {
  const tint = mode === 'dark' ? '145, 163, 184' : '98, 125, 152'
  return {
    visible: true,
    horzAlign: 'left' as const,
    vertAlign: 'top' as const,
    lines: [
      {
        text: title,
        color: `rgba(${tint}, 0.95)`,
        fontSize: 11,
        fontFamily: FONT_UI,
      },
    ],
  }
}

/**
 * The corner badge: mark plus wordmark.
 *
 * Positioned absolutely inside the chart container, and `pointer-events: none` so
 * it never eats a pan or a pinch — on a phone the top-left of the chart is exactly
 * where a thumb lands.
 *
 * The wordmark is italic serif to match the site's Playfair treatment. Playfair
 * itself is not loaded here: pulling a web font into an asset that has to work
 * offline in a WebView is not worth it, and Georgia falls back close enough at
 * 12px.
 */
export function createBrandBadge(mode: ThemeMode): HTMLElement {
  const wrap = document.createElement('div')
  wrap.className = 'tt-brand'
  wrap.setAttribute('aria-hidden', 'true')
  wrap.style.cssText = [
    'position:absolute',
    'top:10px',
    'left:12px',
    'z-index:3',
    'display:flex',
    'align-items:center',
    'gap:6px',
    'pointer-events:none',
    'user-select:none',
  ].join(';')

  const img = document.createElement('img')
  img.src = MARK_DATA_URI
  img.alt = ''
  img.width = 18
  img.height = 18
  img.style.cssText = 'width:18px;height:18px;border-radius:5px;display:block;opacity:.95'

  const name = document.createElement('span')
  name.textContent = BRAND_NAME
  name.style.cssText = [
    `font:italic 600 12.5px/1 ${FONT_BRAND}`,
    'letter-spacing:.01em',
    `color:${mode === 'dark' ? 'rgba(244,247,251,.66)' : 'rgba(11,27,43,.56)'}`,
  ].join(';')

  wrap.append(img, name)
  return wrap
}
