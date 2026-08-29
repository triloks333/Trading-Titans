import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { cryptoUnderlying } from "./crypto_symbol.ts";

// The bug this exists to prevent: a pending crypto FUTURES order priced off a
// lookup keyed by its contract symbol, which never matches and never fills.
Deno.test("CoinDCX perpetual maps to the bare coin", () => {
  assertEquals(cryptoUnderlying("B-BTC_USDT"), "BTC");
  assertEquals(cryptoUnderlying("B-ETH_USDT"), "ETH");
  assertEquals(cryptoUnderlying("B-1000PEPE_USDT"), "1000PEPE");
  // Both spellings of the quote currency.
  assertEquals(cryptoUnderlying("B-SOL_USD"), "SOL");
});

Deno.test("spot symbols pass through untouched", () => {
  assertEquals(cryptoUnderlying("BTC"), "BTC");
  assertEquals(cryptoUnderlying("DOGE"), "DOGE");
  assertEquals(cryptoUnderlying("btc"), "BTC");
  assertEquals(cryptoUnderlying(" eth "), "ETH");
});

Deno.test("near-misses are not mangled", () => {
  // No `B-` prefix: not a CoinDCX perpetual, so it must survive intact rather
  // than being silently truncated to something that resolves to a real coin.
  assertEquals(cryptoUnderlying("BTC_USDT"), "BTC_USDT");
  // Prefix but no quote-currency suffix.
  assertEquals(cryptoUnderlying("B-BTC"), "B-BTC");
  // A dated contract is deliberately NOT handled yet; it must not half-match.
  assertEquals(cryptoUnderlying("B-BTC_USDT_240628"), "B-BTC_USDT_240628");
  assertEquals(cryptoUnderlying(""), "");
});
