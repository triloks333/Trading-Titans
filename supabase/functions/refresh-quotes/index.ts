import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { pooledMap } from "https://deno.land/std@0.177.0/async/pool.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { US_MARKET, isUsMarketOpen } from "../_shared/us_market.ts";
import { cryptoUnderlying } from "../_shared/crypto_symbol.ts";
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
 * why rows in one list moved at different rates. Mirrors the India, crypto and US
 * lists in `kMoverUniverse` in `app/lib/screens/main/trade_screen.dart`; keep them in step.
 *
 * ponytail: duplicated across Dart and TS rather than fetched from a table. The
 * ceiling is that a new popular symbol needs editing in two files; if these
 * lists ever become user-editable, move them into a `popular_symbols` table and
 * read it here instead.
 */
const POPULAR: { symbol: string; market: string }[] = [
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
];

async function buildUniverse(supabase: any): Promise<{ symbol: string; market: string }[]> {
  const universe = new Map<string, { symbol: string; market: string }>();
  const add = (symbol: string | null, market: string | null): string | null => {
    if (!symbol) return null;
    const mkt = (market || "stock").toLowerCase();
    // Crypto perpetuals arrive as `B-BTC_USDT` from pending F&O orders; the feed
    // only knows `BTC`, so without this the symbol was requested verbatim and
    // returned a permanent 404 on every pass.
    const sym = mkt === "crypto" ? cryptoUnderlying(symbol) : extractUnderlying(symbol);
    if (!sym) return null;
    const key = `${sym}\u001f${mkt}`;
    universe.set(key, { symbol: sym, market: mkt });
    return key;
  };
  // Symbols carrying a resting order are refreshed first. The pool below works
  // through the universe in order, so if a pass is cut short by the function
  // deadline it is a watchlist row that goes unrefreshed, never a live order.
  const priority = new Set<string>();
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
  for (const r of (pend.data ?? [])) { const k = add(r.symbol, r.market); if (k) priority.add(k); }
  add("NIFTY", "stock");
  add("BANKNIFTY", "stock");
  add("SENSEX", "stock");
  for (const p of POPULAR) add(p.symbol, p.market);
  return [...universe.entries()]
    .sort((a, b) => Number(priority.has(b[0])) - Number(priority.has(a[0])))
    .map(([, u]) => u);
}

/// How many `market-quote` calls to have in flight at once.
///
/// This used to be "all of them": a bare `Promise.all` over the whole universe,
/// which is ~74 symbols in production. Every one of those lands on the same
/// upstream provider at the same instant, so a slice of them got rate-limited or
/// timed out, the `catch` swallowed it, and those symbols quietly kept whatever
/// price they had — the freshness split behind the missed AEROENTER fill was 32
/// fresh dynamic symbols against 22 stale ones.
///
/// ponytail: one flat concurrency for every market rather than a per-provider
/// budget. The ceiling is that the slowest provider in the universe sets the
/// pace for everyone; the upgrade path is one pool per market.
const QUOTE_CONCURRENCY = 8;

/// A single hung upstream request must not hold a pool slot for the whole run.
const QUOTE_TIMEOUT_MS = 8000;

/// Throws on any outcome that must not be written to the cache, so the retry in
/// `refreshOnce` sees a failure rather than a silently dropped symbol.
async function fetchQuoteRow(u: { symbol: string; market: string }): Promise<Record<string, unknown>> {
  const qurl = `${SUPABASE_URL}/functions/v1/market-quote?symbol=${encodeURIComponent(u.symbol)}&market=${encodeURIComponent(u.market)}`;
  const r = await fetch(qurl, {
    headers: { Authorization: `Bearer ${ANON}`, apikey: ANON },
    signal: AbortSignal.timeout(QUOTE_TIMEOUT_MS),
  });
  // 429 is marked non-retryable. Supabase's per-function limiter answers with a
  // retry-after in the tens of seconds, so the 400ms retry below could never
  // clear it -- it would just double the load at the exact moment we are already
  // over the limit. The next cron minute is the right place to try again.
  if (r.status === 429) throw Object.assign(new Error("rate_limited"), { noRetry: true });
  if (!r.ok) throw new Error(`http_${r.status}`);
  const q = await r.json();
  if (!q || typeof q.price !== "number" || q.price <= 0) throw new Error("no_price");
  return {
    symbol: u.symbol, market: u.market, price: q.price,
    previous_close: q.previous_close ?? null, name: q.name ?? u.symbol,
    change: q.change ?? null, change_pct: q.change_pct ?? null,
    day_low: q.day_low ?? null, day_high: q.day_high ?? null, open: q.open ?? null,
    source: q.source ?? null, updated_at: new Date().toISOString(),
  };
}

async function refreshOnce(
  supabase: any,
  universe: { symbol: string; market: string }[],
  stockOpen: boolean,
  usOpen: boolean,
): Promise<{ refreshed: number; failed: string[] }> {
  const due = universe.filter((u) => isMarketOpen(u.market, stockOpen, usOpen));
  const rows: Record<string, unknown>[] = [];
  const failed: string[] = [];

  // One retry, because the common failure here is a transient upstream throttle
  // rather than a symbol that does not exist.
  const results = pooledMap(QUOTE_CONCURRENCY, due, async (u) => {
    let err = "unknown";
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await sleep(400);
      try {
        return { u, row: await fetchQuoteRow(u) };
      } catch (e) {
        err = e instanceof Error ? e.message : String(e);
        if ((e as { noRetry?: boolean })?.noRetry) break;
      }
    }
    return { u, row: null as Record<string, unknown> | null, err };
  });
  for await (const res of results) {
    if (res.row) rows.push(res.row);
    else failed.push(`${res.u.symbol}:${res.u.market}=${res.err}`);
  }

  if (rows.length > 0) {
    await supabase.from("quotes_cache").upsert(rows, { onConflict: "symbol,market" });
  }
  return { refreshed: rows.length, failed };
}

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";
    const stockOpen = isStockMarketOpen() || force;
    const usOpen = isUsMarketOpen() || force;

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const universe = await buildUniverse(supabase);

    // One pass per invocation.
    //
    // This used to refresh, sleep 18s, and repeat for ~54s, so a once-per-minute
    // cron fired roughly three passes -- about 180 `market-quote` invocations a
    // minute on a 60-symbol universe. That tripped Supabase's own per-function
    // rate limit, which answered "Retry after 56804ms" and left whole symbols
    // unrefreshed. The extra passes existed to get sub-minute freshness back when
    // the cron only ran during a narrow window; the cron is now `* * * * *`, so
    // one pass per tick already keeps every row under ~60s old -- an order of
    // magnitude inside the engine's 10-minute staleness guard, which itself now
    // falls back to a live quote. Three times less load for freshness nobody was
    // using. A `?single=1` from an existing caller is now simply the default, so
    // the parameter is no longer read.
    const pass = await refreshOnce(supabase, universe, stockOpen, usOpen);
    const passes = 1;
    const lastCount = pass.refreshed;
    const lastFailed = pass.failed;

    // Per-market counts make a silent skip (wrong session gate, symbol never
    // added to the universe) visible without reading the function logs.
    const byMarket: Record<string, number> = {};
    for (const u of universe) byMarket[u.market] = (byMarket[u.market] ?? 0) + 1;

    // `failed` is the diagnostic that did not exist before: the old code caught
    // every per-symbol error and returned only a success count, so a pass that
    // refreshed 32 of 54 symbols looked identical to a healthy one. Capped so a
    // provider-wide outage cannot bloat the response.
    return json({
      universe: universe.length,
      byMarket,
      refreshed: lastCount,
      failedCount: lastFailed.length,
      failed: lastFailed.slice(0, 25),
      passes,
      stockOpen,
      usOpen,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
