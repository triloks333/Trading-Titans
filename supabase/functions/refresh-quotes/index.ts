import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { pooledMap } from "https://deno.land/std@0.177.0/async/pool.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { isUsMarketOpen } from "../_shared/us_market.ts";
import { buildUniverse, isMarketOpen, type UniverseEntry } from "../_shared/quote_universe.ts";
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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

/// A row younger than this is the fast feed's responsibility, not ours.
const SAFETY_NET_STALE_MS = 30_000;

async function staleOnly(supabase: any, universe: UniverseEntry[]): Promise<UniverseEntry[]> {
  const { data, error } = await supabase.from("quotes_cache").select("symbol, market, updated_at");
  if (error || !Array.isArray(data)) return universe;
  const cutoff = Date.now() - SAFETY_NET_STALE_MS;
  const fresh = new Set<string>();
  for (const r of data) {
    if (new Date(r.updated_at).getTime() >= cutoff) fresh.add(`${r.symbol}\u001f${r.market}`);
  }
  return universe.filter((u) => !fresh.has(`${u.symbol}\u001f${u.market}`));
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

    const all = url.searchParams.get("all") === "1";

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const fullUniverse = await buildUniverse(supabase);
    // Safety net behind `price-feed`. While the fast feed is healthy it keeps
    // every row only seconds old, so this pass has nothing to do and makes no
    // `market-quote` calls. A row the feed could not price (a symbol Yahoo's
    // batch endpoint skipped, a feed outage) goes stale and is picked up here,
    // one symbol at a time, exactly as before. `?all=1` restores the old
    // refresh-everything behaviour.
    const universe = all ? fullUniverse : await staleOnly(supabase, fullUniverse);

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
    for (const u of fullUniverse) byMarket[u.market] = (byMarket[u.market] ?? 0) + 1;

    // `failed` is the diagnostic that did not exist before: the old code caught
    // every per-symbol error and returned only a success count, so a pass that
    // refreshed 32 of 54 symbols looked identical to a healthy one. Capped so a
    // provider-wide outage cannot bloat the response.
    return json({
      universe: fullUniverse.length,
      stale: universe.length,
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
