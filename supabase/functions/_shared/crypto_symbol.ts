/**
 * Maps a CoinDCX perpetual-futures symbol back to the coin the quote feed knows.
 *
 * CoinDCX names its perpetuals `B-<COIN>_USDT` (e.g. `B-BTC_USDT`), but both
 * `quotes_cache` and `market-quote` are keyed by the bare coin (`BTC`). Nothing
 * bridged the two, so a crypto futures order carried its contract symbol all the
 * way into the pricing lookup, found nothing, and was skipped every single run:
 * a market order for `B-BTC_USDT` sat pending for six days without ever filling,
 * and the symbol also showed up as a permanent `http_404` in the refresher.
 *
 * Kept in `_shared` rather than copied into each caller on purpose. The engine
 * and the refresher already carry their own duplicated `extractUnderlying`, and
 * the last time those two drifted apart it resolved NIFTY to the wrong lot size.
 *
 * ponytail: recognises the one contract shape CoinDCX actually publishes today.
 * The ceiling is a new venue or a quarterly-dated contract (`B-BTC_USDT_240628`)
 * needing another branch; the upgrade path is a `derivative_symbols` mapping
 * table. Non-matching input is returned upper-cased and otherwise untouched, so
 * plain spot symbols are unaffected.
 */
export function cryptoUnderlying(symbolRaw: string): string {
  const s = (symbolRaw ?? "").toUpperCase().trim();
  // `USDT?` is "USD" plus an optional "T", covering both quote-currency spellings.
  const m = s.match(/^B-([A-Z0-9]+)_USDT?$/);
  return m ? m[1] : s;
}
