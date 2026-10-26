import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { IST_CLOSE_MINUTES, IST_OPEN_MINUTES, isStockOpen } from "./market_hours.ts";

/// IST wall-clock helper: builds the UTC instant for a given IST time.
/// IST is UTC+5:30, so 09:15 IST is 03:45 UTC.
function utcForIst(year: number, month: number, day: number, h: number, m: number): Date {
  return new Date(Date.UTC(year, month - 1, day, h, m) - 5.5 * 3600 * 1000);
}

// 2026-08-27 is a Thursday; 2026-08-29 a Saturday; 2026-08-30 a Sunday.
Deno.test("the session closes at 15:30 IST, not 15:15", () => {
  // The exact quarter hour that used to be dead: the app advertised "Market
  // Open" via market-status while nothing could trade.
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 15, 15)), true);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 15, 20)), true);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 15, 29)), true);
});

Deno.test("the close is exclusive and the open inclusive", () => {
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 9, 14)), false);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 9, 15)), true);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 15, 30)), false);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 15, 31)), false);
});

Deno.test("closed outside the session and at weekends", () => {
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 3, 0)), false);
  assertEquals(isStockOpen(utcForIst(2026, 8, 27, 20, 0)), false);
  assertEquals(isStockOpen(utcForIst(2026, 8, 29, 11, 0)), false); // Saturday
  assertEquals(isStockOpen(utcForIst(2026, 8, 30, 11, 0)), false); // Sunday
});

Deno.test("the window constants are the NSE session", () => {
  assertEquals(IST_OPEN_MINUTES, 9 * 60 + 15);
  assertEquals(IST_CLOSE_MINUTES, 15 * 60 + 30);
});

Deno.test("closed on exchange holidays like Dussehra", () => {
  // 2026-10-20 is a Tuesday (Dussehra), within session hours (11:00 AM IST)
  assertEquals(isStockOpen(utcForIst(2026, 10, 20, 11, 0)), false);
});

