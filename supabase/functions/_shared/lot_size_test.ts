import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isExactUnderlying, narrowToUnderlying, pickLotSize } from "./lot_size.ts";

// Rows shaped like a real `LIKE 'NSE:NIFTY%'` result on the 2026-08-25 monthly.
// This is the exact situation that gave production NIFTY positions lot_size 25:
// NIFTYNXT50 had 757 rows against NIFTY's 489 on that date.
const niftyPrefixRows = [
  { symbol: "NSE:NIFTYNXT5026AUG100000CE", expiry_date: "2026-08-25", lot_size: 25 },
  { symbol: "NSE:NIFTYFPI26AUG1000CE", expiry_date: "2026-08-25", lot_size: 1100 },
  { symbol: "NSE:NIFTY26AUG24250PE", expiry_date: "2026-08-25", lot_size: 65 },
];

Deno.test("NIFTY resolves to 65 even when its prefix siblings come back first", () => {
  assertEquals(pickLotSize(niftyPrefixRows, "NIFTY", "^NSEI-2026-08-25-24250-PE", "2026-08-25"), 65);
});

Deno.test("the prefix siblings still resolve to their own lot sizes", () => {
  assertEquals(pickLotSize(niftyPrefixRows, "NIFTYNXT", "NSE:NIFTYNXT5026AUG100000CE", "2026-08-25"), 25);
  assertEquals(pickLotSize(niftyPrefixRows, "NIFTYFPI", "NSE:NIFTYFPI26AUG1000CE", "2026-08-25"), 1100);
});

Deno.test("LT is not given LTF's or LTIM's lot size", () => {
  const rows = [
    { symbol: "NSE:LTF26SEP325CE", expiry_date: "2026-09-29", lot_size: 2250 },
    { symbol: "NSE:LTIM26SEP6000CE", expiry_date: "2026-09-29", lot_size: 150 },
    { symbol: "NSE:LT26SEP2000CE", expiry_date: "2026-09-29", lot_size: 175 },
  ];
  assertEquals(pickLotSize(rows, "LT", "NSE:LT26SEP2000CE", "2026-09-29"), 175);
  // The longer names were never broken; assert they stay correct.
  assertEquals(pickLotSize(rows, "LTF", "NSE:LTF26SEP325CE", "2026-09-29"), 2250);
  assertEquals(pickLotSize(rows, "LTIM", "NSE:LTIM26SEP6000CE", "2026-09-29"), 150);
});

Deno.test("PNB is not given PNBHOUSING's lot size", () => {
  const rows = [
    { symbol: "NSE:PNBHOUSING26SEP800CE", expiry_date: "2026-09-29", lot_size: 650 },
    { symbol: "NSE:PNB26SEP120CE", expiry_date: "2026-09-29", lot_size: 8000 },
  ];
  assertEquals(pickLotSize(rows, "PNB", "NSE:PNB26SEP120CE", "2026-09-29"), 8000);
  assertEquals(pickLotSize(rows, "PNBHOUSING", "NSE:PNBHOUSING26SEP800CE", "2026-09-29"), 650);
});

Deno.test("digit-leading underlyings do not regress", () => {
  // 545 F&O symbols start with a digit. extractUnderlying deliberately does NOT
  // truncate those, so the underlying is the whole symbol and no digit follows
  // it -- the boundary test matches nothing and must fall back rather than
  // collapse to 1, which would misprice the trade by orders of magnitude.
  const rows = [{ symbol: "NSE:360ONE26AUG1000CE", expiry_date: "2026-08-25", lot_size: 500 }];
  assertEquals(pickLotSize(rows, "360ONE26AUG1000CE", "NSE:360ONE26AUG1000CE", "2026-08-25"), 500);
  assertEquals(narrowToUnderlying(rows, "360ONE26AUG1000CE").length, 1);
});

Deno.test("an underlying with a regex metacharacter is matched literally", () => {
  const rows = [
    { symbol: "NSE:M&MFIN26SEP300CE", expiry_date: "2026-09-29", lot_size: 1000 },
    { symbol: "NSE:M&M26SEP3000CE", expiry_date: "2026-09-29", lot_size: 350 },
  ];
  assertEquals(pickLotSize(rows, "M&M", "NSE:M&M26SEP3000CE", "2026-09-29"), 350);
});

Deno.test("differing lot sizes across expiries still pick the order's expiry", () => {
  // HDFCBANK Jun=550 / Jul=650 was a real incident: the wrong lot made
  // trunc(qty/lot) collapse to 0 and dropped the whole position.
  const rows = [
    { symbol: "NSE:HDFCBANK26JUN760CE", expiry_date: "2026-06-25", lot_size: 550 },
    { symbol: "NSE:HDFCBANK26JUL760CE", expiry_date: "2026-07-30", lot_size: 650 },
  ];
  assertEquals(pickLotSize(rows, "HDFCBANK", "NSE:HDFCBANK26JUL760CE", "2026-07-30"), 650);
  assertEquals(pickLotSize(rows, "HDFCBANK", "NSE:HDFCBANK26JUN760CE", "2026-06-25"), 550);
});

Deno.test("no rows resolves to 1 rather than throwing", () => {
  assertEquals(pickLotSize([], "NOSUCHUNDERLYING", "NOSUCH-2026-09-29-100-CE", "2026-09-29"), 1);
});

Deno.test("SENSEX resolves to its BSE lot of 20, not the 1 it used to fall back to", () => {
  // SENSEX is a BSE index and absent from the Fyers NSE_FO.csv feed, so it had no
  // OPTION/FUTURE rows at all and both resolvers returned 1 against a real lot of
  // 20. A single non-tradeable reference row now carries the lot size (migration
  // 20260827020000). The expiry deliberately will not match a caller's contract,
  // so this also pins the candidates[0] fallback.
  const rows = [{ symbol: "NSE:SENSEX26SEPFUT", expiry_date: "2026-09-29", lot_size: 20 }];
  assertEquals(pickLotSize(rows, "SENSEX", "^BSESN-2026-08-27-77600-CE", "2026-08-27"), 20);
  assertEquals(pickLotSize(rows, "SENSEX", "^BSESN JUN FUT", null), 20);
});

Deno.test("the SENSEX ETFs cannot be mistaken for a SENSEX derivative", () => {
  // NSE:SENSEXETF-EQ and friends share the prefix. instrument_type filtering
  // excludes them upstream, but the boundary test is the second line of defence:
  // a letter follows SENSEX in an ETF symbol, a digit follows it in a contract.
  assertEquals(isExactUnderlying("NSE:SENSEXETF-EQ", "SENSEX"), false);
  assertEquals(isExactUnderlying("NSE:SENSEXADD-EQ", "SENSEX"), false);
  assertEquals(isExactUnderlying("NSE:SENSEX26SEPFUT", "SENSEX"), true);
});

Deno.test("isExactUnderlying draws the boundary at the expiry digits", () => {
  assertEquals(isExactUnderlying("NSE:NIFTY26AUG24250PE", "NIFTY"), true);
  assertEquals(isExactUnderlying("NSE:NIFTYNXT5026AUG100000CE", "NIFTY"), false);
  assertEquals(isExactUnderlying("NSE:NIFTYFPI26AUG1000CE", "NIFTY"), false);
  assertEquals(isExactUnderlying("NSE:LTF26SEP325CE", "LT"), false);
});
