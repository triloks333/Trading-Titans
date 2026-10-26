import { assertEquals, assert } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  parseDerivativeSymbol,
  blackScholes,
  normalCDF,
  getDaysToExpiry,
} from "./fo_pricing.ts";

Deno.test("parseDerivativeSymbol: option symbol", () => {
  const p1 = parseDerivativeSymbol("^NSEI-2026-10-06-21850-PE");
  assert(p1 !== null);
  assertEquals(p1?.type, "OPTION");
  assertEquals(p1?.underlying, "^NSEI");
  assertEquals(p1?.expiry, "2026-10-06");
  assertEquals(p1?.strike, 21850);
  assertEquals(p1?.optionType, "PE");

  const p2 = parseDerivativeSymbol("RELIANCE-2026-10-06-2500-CE");
  assert(p2 !== null);
  assertEquals(p2?.underlying, "RELIANCE");
  assertEquals(p2?.strike, 2500);
  assertEquals(p2?.optionType, "CE");

  const p3 = parseDerivativeSymbol("BAJAJ-AUTO-2026-10-06-9500-PE");
  assert(p3 !== null);
  assertEquals(p3?.underlying, "BAJAJ-AUTO");
  assertEquals(p3?.strike, 9500);
  assertEquals(p3?.optionType, "PE");
});

Deno.test("parseDerivativeSymbol: futures symbol", () => {
  const f1 = parseDerivativeSymbol("NIFTY OCT FUT");
  assert(f1 !== null);
  assertEquals(f1?.type, "FUTURE");
  assertEquals(f1?.underlying, "NIFTY");
  assertEquals(f1?.month, "OCT");

  const f2 = parseDerivativeSymbol("RELIANCE-FUT");
  assert(f2 !== null);
  assertEquals(f2?.type, "FUTURE");
  assertEquals(f2?.underlying, "RELIANCE");
});

Deno.test("blackScholes: ITM / OTM properties", () => {
  const spot = 25000;
  const T = 7 / 365.0; // 7 days

  // Deep ITM Call (strike 24000) > intrinsic 1000
  const itmCall = blackScholes(spot, 24000, T, "CE");
  assert(itmCall >= 1000, `itmCall was ${itmCall}`);

  // Deep OTM Call (strike 26000) < 50
  const otmCall = blackScholes(spot, 26000, T, "CE");
  assert(otmCall < 100, `otmCall was ${otmCall}`);

  // Deep ITM Put (strike 26000) > intrinsic 1000
  const itmPut = blackScholes(spot, 26000, T, "PE");
  assert(itmPut >= 1000, `itmPut was ${itmPut}`);

  // Minimum floor
  const deadPut = blackScholes(spot, 10000, T, "PE");
  assertEquals(deadPut, 0.05);
});
