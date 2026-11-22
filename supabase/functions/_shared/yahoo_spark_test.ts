import { assertEquals } from "jsr:@std/assert@1";
import { parseSpark } from "./yahoo_spark.ts";

Deno.test("parses v7 spark shape", () => {
  const m = parseSpark({ spark: { result: [{ symbol: "RELIANCE.NS", response: [{
    meta: { regularMarketPrice: 1500.5, chartPreviousClose: 1490, regularMarketDayHigh: 1510, regularMarketDayLow: 1488, longName: "Reliance" },
    indicators: { quote: [{ close: [1495, null, 1500] }] } }] }] } });
  const r = m.get("RELIANCE.NS")!;
  assertEquals(r.price, 1500.5);
  assertEquals(r.previousClose, 1490);
  assertEquals(r.dayHigh, 1510);
  assertEquals(r.name, "Reliance");
});

Deno.test("parses v8 spark shape, falling back to last close", () => {
  const m = parseSpark({ "^NSEI": { symbol: "^NSEI", close: [24000, 24010, null], chartPreviousClose: 23900 } });
  const r = m.get("^NSEI")!;
  assertEquals(r.price, 24010);
  assertEquals(r.previousClose, 23900);
});

Deno.test("skips symbols with no price", () => {
  assertEquals(parseSpark({ spark: { result: [{ symbol: "X.NS", response: [{ meta: {} }] }] } }).size, 0);
  assertEquals(parseSpark(null).size, 0);
});

// Real ^NSEI numbers from Yahoo on Sat 22 Nov 2026 (IST, gmtoffset 19800).
// Spark's chartPreviousClose was 25227.9 (the 18 Nov close); the true previous
// close is 19 Nov's 25514.3.
const day = (iso: string) => Date.parse(iso) / 1000;
Deno.test("previous close comes from the daily bars, not chartPreviousClose", () => {
  const m = parseSpark({ spark: { result: [{ symbol: "^NSEI", response: [{
    meta: { regularMarketPrice: 25800.6, chartPreviousClose: 25227.9, previousClose: 25227.9,
            gmtoffset: 19800, regularMarketTime: day("2026-11-20T10:01:00Z") },
    timestamp: [day("2026-11-16T03:45:00Z"), day("2026-11-17T03:45:00Z"), day("2026-11-18T03:45:00Z"),
                day("2026-11-19T03:45:00Z"), day("2026-11-20T03:45:00Z")],
    indicators: { quote: [{ close: [25291.1, 25387.4, 25227.95, 25514.3, 25800.6] }] } }] }] } });
  const r = m.get("^NSEI")!;
  assertEquals(r.price, 25800.6);
  assertEquals(r.previousClose, 25514.3);
});

Deno.test("during the session today's bar is skipped for the previous close", () => {
  const m = parseSpark({ spark: { result: [{ symbol: "RELIANCE.NS", response: [{
    meta: { regularMarketPrice: 1380, gmtoffset: 19800, regularMarketTime: day("2026-11-23T05:00:00Z") },
    timestamp: [day("2026-11-20T03:45:00Z"), day("2026-11-23T03:45:00Z")],
    indicators: { quote: [{ close: [1377.5, 1380] }] } }] }] } });
  assertEquals(m.get("RELIANCE.NS")!.previousClose, 1377.5);
});
