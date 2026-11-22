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

export function fromMeta(meta: any, closes: unknown[] = []): Parsed | null {
  if (!meta) return null;
  const last = [...closes].reverse().find((c) => num(c) !== null);
  const price = num(meta.regularMarketPrice) ?? num(last);
  if (!price) return null;
  return {
    price,
    previousClose: num(meta.chartPreviousClose) ?? num(meta.previousClose) ?? num(meta.regularMarketPreviousClose),
    dayLow: num(meta.regularMarketDayLow),
    dayHigh: num(meta.regularMarketDayHigh),
    open: num(meta.regularMarketOpen),
    name: meta.longName ?? meta.shortName ?? null,
    marketTime: num(meta.regularMarketTime),
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
      const parsed = fromMeta(resp?.meta, resp?.indicators?.quote?.[0]?.close ?? []);
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
        },
        closes,
      );
      if (parsed) out.set(sym.toUpperCase(), parsed);
    }
  }
  return out;
}
