// deno-lint-ignore-file no-explicit-any
/**
 * The set of symbols the server keeps fresh in `quotes_cache`.
 *
 * Shared by `price-feed` (the batched, every-few-seconds fetcher) and
 * `refresh-quotes` (the per-symbol safety net), so both write rows under exactly
 * the same keys. The keys must also match `MarketService.cacheKeyFor` in the app.
 */
import { COMMODITIES, COMMODITY_MARKET, US_MARKET, isCommodityOpen } from "./us_market.ts";
import { cryptoUnderlying } from "./crypto_symbol.ts";

export type UniverseEntry = { symbol: string; market: string };

export function extractUnderlying(symbolRaw: string): string {
  let s = (symbolRaw || "").toUpperCase().trim();
  if (s.startsWith("NSE:")) s = s.slice(4);
  if (s.startsWith("BSE:")) s = s.slice(4);
  s = s.replace("-EQ-", "-");
  if (s.endsWith("-EQ")) s = s.slice(0, -3);
  if (s.includes(" ")) s = s.split(" ")[0];
  if (s.includes("-")) s = s.split("-")[0];
  if (s === "^NSEI" || s === "NSEI" || s === "NIFTY50") return "NIFTY";
  if (s === "^NSEBANK" || s === "NSEBANK") return "BANKNIFTY";
  if (s === "^BSESN" || s === "SENSEX") return "SENSEX";
  const m = s.match(/\d/);
  if (m && (m.index ?? 0) > 0) s = s.slice(0, m.index);
  return s;
}

/**
 * Is this market's session live right now? Crypto trades 24/7; US equities and
 * commodities follow their own sessions; everything else follows NSE.
 */
export function isMarketOpen(market: string, stockOpen: boolean, usOpen: boolean): boolean {
  if (market === "crypto") return true;
  if (market === US_MARKET) return usOpen;
  if (market === COMMODITY_MARKET) return isCommodityOpen();
  return stockOpen;
}

/**
 * Symbols the Trade screen offers before the user searches for anything.
 *
 * Mirrors the India, crypto and US lists in `kMoverUniverse` in
 * `app/lib/screens/main/trade_screen.dart`; keep them in step.
 */
export const POPULAR: UniverseEntry[] = [
  ...["RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK", "SBIN", "BHARTIARTL",
      "ITC", "LT", "HINDUNILVR", "KOTAKBANK", "AXISBANK", "BAJFINANCE", "MARUTI",
      "SUNPHARMA", "TITAN", "ASIANPAINT", "WIPRO", "HCLTECH", "TATASTEEL", "NTPC",
      "POWERGRID", "ONGC", "ADANIENT", "ETERNAL", "TMPV", "TMCV"]
    .map((symbol) => ({ symbol, market: "stock" })),
  ...["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "POL", "AVAX", "DOT",
      "LINK", "LTC", "TRX"]
    .map((symbol) => ({ symbol, market: "crypto" })),
  ...["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "TSLA", "NFLX", "AMD",
      "INTC", "JPM", "V", "WMT", "DIS", "ORCL", "AVGO"]
    .map((symbol) => ({ symbol, market: US_MARKET })),
  ...COMMODITIES.map(({ symbol }) => ({ symbol, market: COMMODITY_MARKET })),
];

/** How far back a symbol someone merely opened stays in the universe. */
const HOT_SYMBOL_WINDOW_MS = 10 * 60 * 1000;
/** Cap on browsed symbols, so a burst of searching cannot balloon each tick. */
const HOT_SYMBOL_LIMIT = 100;

/**
 * Everything someone holds, watches, has an order or alert on, or opened in the
 * last few minutes, plus the indices and the popular lists.
 *
 * Symbols carrying a resting order come first, so a run cut short by a deadline
 * drops a watchlist row, never a live order.
 */
export async function buildUniverse(supabase: any): Promise<UniverseEntry[]> {
  const universe = new Map<string, UniverseEntry>();
  const add = (symbol: string | null, market: string | null): string | null => {
    if (!symbol) return null;
    const mkt = (market || "stock").toLowerCase();
    // Crypto perpetuals arrive as `B-BTC_USDT` from pending F&O orders; the feed
    // only knows `BTC`.
    const sym = mkt === "crypto" ? cryptoUnderlying(symbol) : extractUnderlying(symbol);
    if (!sym) return null;
    const key = `${sym}\u001f${mkt}`;
    universe.set(key, { symbol: sym, market: mkt });
    return key;
  };
  const priority = new Set<string>();
  const hotSince = new Date(Date.now() - HOT_SYMBOL_WINDOW_MS).toISOString();
  const [watch, holds, fo, alerts, pend, hot] = await Promise.all([
    supabase.from("watchlist").select("symbol, market"),
    supabase.from("holdings").select("symbol, market"),
    supabase.from("fo_positions").select("symbol").eq("is_settled", false),
    supabase.from("price_alerts").select("symbol, market").eq("status", "active"),
    supabase.from("orders").select("symbol, market").eq("status", "pending"),
    supabase.from("hot_symbols").select("symbol, market")
      .gte("seen_at", hotSince).order("seen_at", { ascending: false }).limit(HOT_SYMBOL_LIMIT),
  ]);
  for (const r of (watch.data ?? [])) add(r.symbol, r.market);
  for (const r of (holds.data ?? [])) add(r.symbol, r.market);
  for (const r of (fo.data ?? [])) add(r.symbol, "stock");
  for (const r of (alerts.data ?? [])) add(r.symbol, r.market);
  for (const r of (pend.data ?? [])) { const k = add(r.symbol, r.market); if (k) priority.add(k); }
  // `hot_symbols` may not exist yet on a database that has not run the
  // migration; its error is ignored and the universe is built without it.
  for (const r of (hot.data ?? [])) add(r.symbol, r.market);
  add("NIFTY", "stock");
  add("BANKNIFTY", "stock");
  add("SENSEX", "stock");
  for (const p of POPULAR) add(p.symbol, p.market);
  return [...universe.entries()]
    .sort((a, b) => Number(priority.has(b[0])) - Number(priority.has(a[0])))
    .map(([, u]) => u);
}
