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
