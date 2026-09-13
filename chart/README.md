# chart

Trading Titans' own chart. One implementation, framework-free, so the React web
app and the Flutter WebView can both render from it instead of keeping a copy each.

Nothing imports this yet. It is deliberately standalone until it has been looked
at, because the chart it replaces existed three times over — a TradingView embed
on Android, `interactive_chart` on Flutter web, `lightweight-charts` in the React
app — and the three disagreed about prices, styling and which symbol was even
being shown.

## Run it

```bash
npm install
npm run dev      # http://localhost:5180
npm test         # 20 assert-based checks, no framework
npm run build    # production bundle
```

The harness at `/` loads live data from the production project, so it needs no
setup and no login. Type a symbol, pick a market, pick a timeframe. **Live: on**
polls our own quote every five seconds.

## What it draws

| Part of the chart | Comes from | Ours? |
|---|---|---|
| Historical bars | `market-history` → Yahoo Finance / CoinGecko | no |
| The live bar | `quotes_cache.price` | **yes** |

That second row is the point. `quotes_cache` is the table `execute-pending-orders`
prices fills from and the table `MarketService` renders the app from, so the
right-hand edge of this chart is the exact number a user gets filled at. The
TradingView embed drew a different feed entirely, so its candles and our fills
could disagree with nothing to explain the gap.

The history is still the vendor's and will not agree to the paisa. That seam is
known. Closing it means recording our own series — see `aggregate.ts`, which is
already written for it.

## Indicators

Nineteen, all computed from OHLC alone, all pure functions in `indicators.ts`:

| Group | Indicators |
|---|---|
| Moving averages | SMA, EMA, WMA |
| Bands & channels | Bollinger, Donchian, Keltner |
| Trend | Parabolic SAR, Supertrend, Ichimoku Cloud, ADX/DMI |
| Momentum | RSI, MACD, Stochastic, Stochastic RSI, Williams %R, CCI, Rate of Change, Momentum |
| Volatility | ATR |

Overlays draw on the price pane; oscillators each get their own pane. Adding one
is a function in `indicators.ts` plus an entry in `registry.ts` — the picker reads
the registry, so a new indicator appears in both clients with no UI change.

**No volume indicators.** VWAP, OBV, Money Flow and Accumulation/Distribution all
need per-bar volume, and `market-history` returns only `{t,o,h,l,c}` — the edge
function reads Yahoo's volume and throws it away. Adding them means changing that
function, not this package. Inventing volume to fill the gap would make all four
lie.

## Branding

Three places, all in `brand.ts`:

- a corner badge with the Surya Yantra mark and the wordmark, as DOM so it stays
  crisp at any pixel ratio and works identically in the browser and the WebView
- a centred canvas watermark via lightweight-charts' own `createTextWatermark`, so
  it survives a screenshot
- `attributionLogo: false` on the chart. Apache-2.0 does not require a visible
  TradingView mark, and the branding here is ours

The mark is inlined as a data URI, not fetched: the Flutter build has to be one
self-contained asset, and a logo that only appears online is worse than none.

Worth someone deciding: the logo is amber (`website/public/logo.svg`, which the
live site and Play listing use) while `theme.dart` moved the UI to blue and kept
the old names — `AppColors.imperialGold` is now `#1A73E8`. The chart uses the live
amber mark with the blue UI. That is the current state of the brand, not a choice
made here.

## Layout

```
src/core/        no I/O, no framework, testable
  types.ts       Candle, Sample, Timeframe. Read the note on Seconds.
  theme.ts       palette transcribed from app/lib/core/theme.dart
  brand.ts       mark, wordmark, watermark
  symbols.ts     our name <-> the feed's name, both directions
  aggregate.ts   samples -> OHLC, and the live-tick merge
  indicators.ts  the maths, 19 of them
  registry.ts    catalogue: labels, defaults, plot wiring
  chart.ts       the chart
src/data/        everything that touches the network
src/demo/        the harness. Not shipped.
```

## Two things to know before changing anything

**Time is seconds, not milliseconds.** `market-history` returns milliseconds and
lightweight-charts wants seconds. The division happens once, in `data/history.ts`.
Mixing them puts every bar in 1970 and renders an empty chart with no error.

**A 1-minute candle from our own data would be a lie.** `refresh-quotes` samples
once a minute, so there is one observation per minute and no intra-minute high or
low to read. 5 minutes and up aggregate honestly; 1 minute is drawn as a line. See
`isHonestCandleTimeframe`.

## Not done yet

- Neither client imports it. That is the next step and it is deliberate.
- Indicator parameters are fixed at their defaults. The registry already carries
  each parameter's range, so a settings popover is UI work, not maths.
- No drawing tools. [lightweight-charts-drawing](https://github.com/deepentropy/lightweight-charts-drawing)
  covers 68 of them for v5.
- No volume pane, for the reason above.
- Options chart their underlying, because `market-quote` returns the underlying
  spot for an option symbol rather than the premium.
