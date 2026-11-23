import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  exchangeFor,
  monthlyExpiry,
  upcomingMonthlyExpiries,
  upcomingOptionExpiries,
} from "./expiry_calendar.ts";
import { parseDerivativeSymbol } from "./fo_pricing.ts";

// Expected dates are the real exchange calendar (checked against the Fyers NSE
// contract master in `instruments` on 23 Nov 2026).

Deno.test("NSE monthly = last Tuesday, moved back over holidays", () => {
  assertEquals(monthlyExpiry(2026, 10, "NSE"), "2026-10-27");
  // Tue 24 Nov 2026 is Guru Nanak Jayanti -> Mon 23 Nov.
  assertEquals(monthlyExpiry(2026, 11, "NSE"), "2026-11-23");
  assertEquals(monthlyExpiry(2026, 12, "NSE"), "2026-12-29");
  // Tue 26 Jan 2027 is Republic Day -> Mon 25 Jan.
  assertEquals(monthlyExpiry(2027, 1, "NSE"), "2027-01-25");
});

Deno.test("BSE monthly = last Thursday, moved back over holidays", () => {
  assertEquals(monthlyExpiry(2026, 11, "BSE"), "2026-11-26");
  // Thu 31 Dec 2026 is a trading day.
  assertEquals(monthlyExpiry(2026, 12, "BSE"), "2026-12-31");
  assertEquals(monthlyExpiry(2027, 1, "BSE"), "2027-01-28");
});

Deno.test("exchangeFor routes SENSEX/BANKEX to BSE", () => {
  assertEquals(exchangeFor("SENSEX"), "BSE");
  assertEquals(exchangeFor("^BSESN"), "BSE");
  assertEquals(exchangeFor("BANKEX"), "BSE");
  assertEquals(exchangeFor("NIFTY"), "NSE");
  assertEquals(exchangeFor("RELIANCE"), "NSE");
});

// 23 Nov 2026, 10:00 IST (market open, NSE monthly expiry day).
const MON_MORNING = new Date("2026-11-23T04:30:00Z");
// Same day, 16:00 IST (after the close).
const MON_EVENING = new Date("2026-11-23T10:30:00Z");

Deno.test("NIFTY weeklies are Tuesdays, holiday-shifted, today kept until close", () => {
  assertEquals(upcomingOptionExpiries("NIFTY", 4, MON_MORNING), [
    "2026-11-23", "2026-12-01", "2026-12-08", "2026-12-15",
  ]);
  assertEquals(upcomingOptionExpiries("^NSEI", 3, MON_EVENING), [
    "2026-12-01", "2026-12-08", "2026-12-15",
  ]);
});

Deno.test("SENSEX weeklies are Thursdays", () => {
  assertEquals(upcomingOptionExpiries("SENSEX", 4, MON_MORNING), [
    "2026-11-26", "2026-12-03", "2026-12-10", "2026-12-17",
  ]);
});

Deno.test("BANKNIFTY and stocks have monthly expiries only", () => {
  assertEquals(upcomingOptionExpiries("BANKNIFTY", 4, MON_EVENING), [
    "2026-12-29", "2027-01-25", "2027-02-23",
  ]);
  assertEquals(upcomingMonthlyExpiries("RELIANCE", 3, MON_MORNING), [
    "2026-11-23", "2026-12-29", "2027-01-25",
  ]);
});

Deno.test("futures symbols parse to the real monthly expiry", () => {
  assertEquals(parseDerivativeSymbol("NIFTY26NOVFUT")?.expiry, "2026-11-23");
  assertEquals(parseDerivativeSymbol("RELIANCE26DECFUT")?.expiry, "2026-12-29");
  assertEquals(parseDerivativeSymbol("SENSEX26NOVFUT")?.expiry, "2026-11-26");
});
