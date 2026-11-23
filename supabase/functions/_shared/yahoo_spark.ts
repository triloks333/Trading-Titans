// deno-lint-ignore-file no-explicit-any
/**
 * Parsing for Yahoo's multi-symbol "spark" endpoint and the chart meta block,
 * used by the price-feed edge function. Kept separate so it can be unit-tested
 * without the function's environment.
 */

export const num = (v: unknown): number | null => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
};

export type Parsed = {
  price: number;
  previousClose: number | null;
  dayLow: number | null;
  dayHigh: number | null;
  open: number | null;
  name: string | null;
  marketTime: number | null;
};

/**
 * Converts a quote from Yahoo's contract unit into the unit we store and trade.
 *
 * Yahoo quotes COMEX Gold (GC=F) and Silver (SI=F) per troy ounce, but the app,
 * the order engine and every existing holding price them per gram
 * (`commodityUnitDivisor`). `market-quote` always divided; the batched feed did
 * not, so from the 22 Nov switch to the feed it wrote gold at ~31x its real
 * price. Users could then sell a few rupees of gold for ~31x what it cost (one
 * user showed ~2000% on the Weekly League from it). Every price field is scaled,
 * not just `price`, so the previous close and day range stay comparable.
 */
export function scaleParsed(p: Parsed, divisor: number): Parsed {
  if (!(divisor > 0) || divisor === 1) return p;
  const d = (v: number | null) => (v === null ? null : v / divisor);
  return {
    ...p,
    price: p.price / divisor,
    previousClose: d(p.previousClose),
    dayLow: d(p.dayLow),
    dayHigh: d(p.dayHigh),
    open: d(p.open),
  };
}

/** Exchange-local calendar day of an epoch-seconds timestamp. */
function localDay(epochS: number, gmtOffsetS: number): number {
  return Math.floor((epochS + gmtOffsetS) / 86400);
}

/**
 * Builds a quote from a chart/spark `meta` block plus the series beside it.
 *
 * The previous close comes from the DAILY bars, not from `chartPreviousClose`:
 * that field is the close before the requested window starts, so its meaning
 * shifts with `range`, and for indices Yahoo's spark even returns the close from
 * two sessions back (checked 2026-11-22: ^NSEI gave the 18 Nov close on a
 * Saturday, when the previous close was 19 Nov's). With daily bars the previous
 * close is simply the last close on a day before the latest trading day.
 * `chartPreviousClose` is used only when no bars came back.
 */
export function fromMeta(meta: any, closes: unknown[] = [], timestamps: unknown[] = []): Parsed | null {
  if (!meta) return null;
  const last = [...closes].reverse().find((c) => num(c) !== null);
  const price = num(meta.regularMarketPrice) ?? num(last);
  if (!price) return null;

  const offset = Number(meta.gmtoffset) || 0;
  const marketTime = num(meta.regularMarketTime);
  let previousClose: number | null = null;
  if (timestamps.length === closes.length && timestamps.length > 0) {
    let lastIdx = -1;
    for (let i = closes.length - 1; i >= 0; i--) {
      if (num(closes[i]) !== null && num(timestamps[i]) !== null) { lastIdx = i; break; }
    }
    if (lastIdx >= 0) {
      const sessionDay = localDay(marketTime ?? (timestamps[lastIdx] as number), offset);
      for (let i = closes.length - 1; i >= 0; i--) {
        const c = num(closes[i]);
        const t = num(timestamps[i]);
        if (c !== null && t !== null && localDay(t, offset) < sessionDay) { previousClose = c; break; }
      }
    }
  }
  previousClose ??= num(meta.previousClose) ?? num(meta.regularMarketPreviousClose) ?? num(meta.chartPreviousClose);

  return {
    price,
    previousClose,
    dayLow: num(meta.regularMarketDayLow),
    dayHigh: num(meta.regularMarketDayHigh),
    open: num(meta.regularMarketOpen),
    name: meta.longName ?? meta.shortName ?? null,
    marketTime,
  };
}

/**
 * Reads either spark response shape:
 *   v7: { spark: { result: [ { symbol, response: [ { meta, indicators } ] } ] } }
 *   v8: { "<SYM>": { symbol, close: [...], chartPreviousClose, previousClose } }
 */
export function parseSpark(body: any): Map<string, Parsed> {
  const out = new Map<string, Parsed>();
  const results = body?.spark?.result;
  if (Array.isArray(results)) {
    for (const r of results) {
      const resp = r?.response?.[0];
      const parsed = fromMeta(resp?.meta, resp?.indicators?.quote?.[0]?.close ?? [], resp?.timestamp ?? []);
      if (r?.symbol && parsed) out.set(String(r.symbol).toUpperCase(), parsed);
    }
    return out;
  }
  if (body && typeof body === "object") {
    for (const [sym, v] of Object.entries<any>(body)) {
      if (!v || typeof v !== "object") continue;
      const closes: unknown[] = Array.isArray(v.close) ? v.close : [];
      const parsed = fromMeta(
        {
          regularMarketPrice: v.regularMarketPrice,
          chartPreviousClose: v.chartPreviousClose,
          previousClose: v.previousClose,
          gmtoffset: v.gmtoffset,
        },
        closes,
        Array.isArray(v.timestamp) ? v.timestamp : [],
      );
      if (parsed) out.set(sym.toUpperCase(), parsed);
    }
  }
  return out;
}
