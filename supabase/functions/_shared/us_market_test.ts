// Checks for the US session helper.
//
// This rule is implemented twice — here for the edge functions, and in
// app/lib/core/market_hours.dart for the client. The boundary instants asserted
// below are deliberately identical to the ones in app/test/us_stocks_test.dart,
// so if the two implementations ever drift, one of the two suites fails.
//
//   deno test supabase/functions/_shared/us_market_test.ts

import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fromUsYahooSymbol,
  isUsDst,
  isUsMarketOpen,
  toUsYahooSymbol,
  usEasternNow,
} from "./us_market.ts";

const utc = (y: number, m: number, d: number, h = 0, min = 0) =>
  new Date(Date.UTC(y, m - 1, d, h, min));

Deno.test("2026 DST runs 8 March to 1 November", () => {
  assertFalse(isUsDst(utc(2026, 3, 8, 6, 59)));
  assert(isUsDst(utc(2026, 3, 8, 7, 0)));
  assert(isUsDst(utc(2026, 11, 1, 5, 59)));
  assertFalse(isUsDst(utc(2026, 11, 1, 6, 0)));
});

Deno.test("deep winter and summer land on the right side", () => {
  assertFalse(isUsDst(utc(2026, 1, 15, 12)));
  assert(isUsDst(utc(2026, 7, 15, 12)));
  assertFalse(isUsDst(utc(2026, 12, 25, 12)));
});

Deno.test("Eastern offset follows DST", () => {
  // 17:00 UTC is 13:00 EDT in July, 12:00 EST in January.
  assertEquals(usEasternNow(utc(2026, 7, 15, 17)).getUTCHours(), 13);
  assertEquals(usEasternNow(utc(2026, 1, 15, 17)).getUTCHours(), 12);
});

Deno.test("EDT session is 13:30-20:00 UTC", () => {
  assertFalse(isUsMarketOpen(utc(2026, 7, 15, 13, 29)));
  assert(isUsMarketOpen(utc(2026, 7, 15, 13, 30)));
  assert(isUsMarketOpen(utc(2026, 7, 15, 19, 59)));
  assertFalse(isUsMarketOpen(utc(2026, 7, 15, 20, 0)));
});

Deno.test("EST session is 14:30-21:00 UTC", () => {
  assertFalse(isUsMarketOpen(utc(2026, 1, 15, 14, 29)));
  assert(isUsMarketOpen(utc(2026, 1, 15, 14, 30)));
  assert(isUsMarketOpen(utc(2026, 1, 15, 20, 59)));
  assertFalse(isUsMarketOpen(utc(2026, 1, 15, 21, 0)));
});

Deno.test("closed at the weekend", () => {
  assertFalse(isUsMarketOpen(utc(2026, 7, 18, 15))); // Saturday
  assertFalse(isUsMarketOpen(utc(2026, 7, 19, 15))); // Sunday
});

Deno.test("Friday evening UTC is still a Friday session", () => {
  // 19:00 UTC Friday = 15:00 EDT Friday. In IST this is already Saturday, which
  // is the trap: the day must be judged in Eastern, not IST.
  const friday = utc(2026, 7, 17, 19);
  assertEquals(friday.getUTCDay(), 5);
  assert(isUsMarketOpen(friday));
});

Deno.test("the cron window covers both DST offsets", () => {
  // The migration schedules execute-pending-orders for 13-21 UTC, Mon-Fri.
  // Assert the session can never open before 13:00 or close after 21:00 UTC.
  for (const [month, openUtc, closeUtc] of [[7, 13.5, 20], [1, 14.5, 21]] as const) {
    assert(openUtc >= 13, `session opens before the cron window in month ${month}`);
    assert(closeUtc <= 21, `session closes after the cron window in month ${month}`);
  }
});

Deno.test("US symbols are not given an Indian suffix", () => {
  assertEquals(toUsYahooSymbol("AAPL"), "AAPL");
  assertEquals(toUsYahooSymbol("aapl"), "AAPL");
  assertEquals(toUsYahooSymbol("NASDAQ:MSFT"), "MSFT");
  // A stray Indian suffix is stripped rather than passed through.
  assertEquals(toUsYahooSymbol("AAPL.NS"), "AAPL");
});

Deno.test("class shares round-trip between storage and Yahoo form", () => {
  assertEquals(toUsYahooSymbol("BRK-B"), "BRK.B");
  assertEquals(fromUsYahooSymbol("BRK.B"), "BRK-B");
  assertEquals(fromUsYahooSymbol(toUsYahooSymbol("BRK-B")), "BRK-B");
  assertEquals(toUsYahooSymbol(fromUsYahooSymbol("BRK.B")), "BRK.B");
  // Plain tickers are unaffected by the round trip.
  assertEquals(fromUsYahooSymbol(toUsYahooSymbol("AAPL")), "AAPL");
});
