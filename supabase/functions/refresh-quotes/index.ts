import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { US_MARKET, isUsMarketOpen } from "../_shared/us_market.ts";
// Shared session window: the old inline copy closed at 15:15, so quotes stopped
// refreshing 15 minutes before the exchange did -- which also starved the
// engine's stale-price guard at the end of every session.
import { isStockOpen as isStockMarketOpen } from "../_shared/market_hours.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function extractUnderlying(symbolRaw: string): string {
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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Is this market's session live right now?
 *
 * Previously every non-crypto market was gated on the *Indian* session, which
 * got US equities exactly backwards: they were refreshed while NSE was open (the
 * US market shut, so a stale close kept being restamped as fresh) and skipped
 * once the US market actually opened. Crypto trades 24/7.
 */
function isMarketOpen(market: string, stockOpen: boolean, usOpen: boolean): boolean {
  if (market === "crypto") return true;
  if (market === US_MARKET) return usOpen;
  return stockOpen;
}

/**
 * Symbols the Trade screen offers before the user searches for anything.
 *
 * These are not in anybody's watchlist or holdings by default, so without them
 * the popular rows miss the cache and each client fetches them live — which is
 * why rows in one list moved at different rates. Mirrors the three `_popular*`
 * lists in `app/lib/screens/main/trade_screen.dart`; keep them in step.
 *
 * ponytail: duplicated across Dart and TS rather than fetched from a table. The
 * ceiling is that a new popular symbol needs editing in two files; if these
 * lists ever become user-editable, move them into a `popular_symbols` table and
 * read it here instead.
 */
const POPULAR: { symbol: string; market: string }[] = [
  ...["RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK", "TMCV", "TMPV",
      "ADANIENT", "ETERNAL"]
    .map((symbol) => ({ symbol, market: "stock" })),
  ...["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "POL"]
    .map((symbol) => ({ symbol, market: "crypto" })),
  ...["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "TSLA", "NFLX"]
    .map((symbol) => ({ symbol, market: US_MARKET })),
];

async function buildUniverse(supabase: any): Promise<{ symbol: string; market: string }[]> {
  const universe = new Map<string, { symbol: string; market: string }>();
  const add = (symbol: string | null, market: string | null) => {
    if (!symbol) return;
    const mkt = (market || "stock").toLowerCase();
    const sym = mkt === "crypto" ? symbol.toUpperCase() : extractUnderlying(symbol);
    if (!sym) return;
    universe.set(`${sym}\u001f${mkt}`, { symbol: sym, market: mkt });
  };
  const [watch, holds, fo, alerts, pend] = await Promise.all([
    supabase.from("watchlist").select("symbol, market"),
    supabase.from("holdings").select("symbol, market"),
    supabase.from("fo_positions").select("symbol").eq("is_settled", false),
    supabase.from("price_alerts").select("symbol, market").eq("status", "active"),
    supabase.from("orders").select("symbol, market").eq("status", "pending"),
  ]);
  for (const r of (watch.data ?? [])) add(r.symbol, r.market);
  for (const r of (holds.data ?? [])) add(r.symbol, r.market);
  for (const r of (fo.data ?? [])) add(r.symbol, "stock");
  for (const r of (alerts.data ?? [])) add(r.symbol, r.market);
  for (const r of (pend.data ?? [])) add(r.symbol, r.market);
  add("NIFTY", "stock");
  add("BANKNIFTY", "stock");
  add("SENSEX", "stock");
  for (const p of POPULAR) add(p.symbol, p.market);
  return [...universe.values()];
}

async function refreshOnce(supabase: any, universe: { symbol: string; market: string }[], stockOpen: boolean, usOpen: boolean): Promise<number> {
  const rows: Record<string, unknown>[] = [];
  await Promise.all(universe.map(async (u) => {
    if (!isMarketOpen(u.market, stockOpen, usOpen)) return;
    try {
      const qurl = `${SUPABASE_URL}/functions/v1/market-quote?symbol=${encodeURIComponent(u.symbol)}&market=${encodeURIComponent(u.market)}`;
      const r = await fetch(qurl, { headers: { Authorization: `Bearer ${ANON}`, apikey: ANON } });
      if (!r.ok) return;
      const q = await r.json();
      if (!q || typeof q.price !== "number" || q.price <= 0) return;
      rows.push({
        symbol: u.symbol, market: u.market, price: q.price,
        previous_close: q.previous_close ?? null, name: q.name ?? u.symbol,
        change: q.change ?? null, change_pct: q.change_pct ?? null,
        day_low: q.day_low ?? null, day_high: q.day_high ?? null, open: q.open ?? null,
        source: q.source ?? null, updated_at: new Date().toISOString(),
      });
    } catch (_) { /* ignore */ }
  }));
  if (rows.length > 0) {
    await supabase.from("quotes_cache").upsert(rows, { onConflict: "symbol,market" });
  }
  return rows.length;
}

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";
    const single = url.searchParams.get("single") === "1";
    const stockOpen = isStockMarketOpen() || force;
    const usOpen = isUsMarketOpen() || force;

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const universe = await buildUniverse(supabase);

    // Internal refresh loop so a once-per-minute cron yields sub-minute
    // freshness: refresh, then repeat every ~18s for up to ~54s.
    let passes = 0;
    let lastCount = 0;
    const started = Date.now();
    const maxWindowMs = single ? 0 : 54000;
    do {
      lastCount = await refreshOnce(supabase, universe, stockOpen, usOpen);
      passes++;
      if (Date.now() - started >= maxWindowMs) break;
      await sleep(18000);
    } while (Date.now() - started < maxWindowMs);

    // Per-market counts make a silent skip (wrong session gate, symbol never
    // added to the universe) visible without reading the function logs.
    const byMarket: Record<string, number> = {};
    for (const u of universe) byMarket[u.market] = (byMarket[u.market] ?? 0) + 1;

    return json({
      universe: universe.length,
      byMarket,
      refreshed: lastCount,
      passes,
      stockOpen,
      usOpen,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
