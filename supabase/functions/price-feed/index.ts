// deno-lint-ignore-file no-explicit-any
/**
 * price-feed: the one place that fetches live prices.
 *
 * pg_cron starts this once a minute. Each run builds the symbol universe once,
 * then loops for about a minute: every TICK_MS it fetches every open market in a
 * handful of batched requests (Yahoo for stocks, indices, US, commodities and
 * the other Yahoo markets; one CoinDCX ticker call for all crypto), upserts
 * `quotes_cache`, and every BROADCAST_MS pushes the prices that changed to the
 * app over Supabase Realtime Broadcast on the public `prices` topic.
 *
 * Replaces the old pattern of one `market-quote` invocation (two sequential
 * Yahoo requests) per symbol per minute. `refresh-quotes` stays on as a safety
 * net for any row this feed leaves stale.
 *
 * Query parameters:
 *   dry=1             one tick, no writes, no broadcast; returns what it parsed.
 *   force=1           treat every market as open (testing outside hours).
 *   tick_ms=3000      fetch interval.
 *   broadcast_ms=5000 push interval (keeps Realtime messages inside the Pro quota).
 *   duration_s=58     how long one run loops.
 */
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { buildUniverse, isMarketOpen, type UniverseEntry } from "../_shared/quote_universe.ts";
import {
  COMMODITY_MARKET,
  US_MARKET,
  commodityUnitDivisor,
  fromUsYahooSymbol,
  isUsMarketOpen,
  toUsYahooSymbol,
} from "../_shared/us_market.ts";
import { isStockOpen } from "../_shared/market_hours.ts";
import { type Parsed, fromMeta, num, parseSpark, scaleParsed } from "../_shared/yahoo_spark.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";
const YAHOO_HOSTS = ["https://query1.finance.yahoo.com", "https://query2.finance.yahoo.com"];
const COINDCX_TICKER = "https://api.coindcx.com/exchange/ticker";

/** Realtime topic the app subscribes to. Public: these are public prices. */
export const PRICE_TOPIC = "prices";

/** Symbols per Yahoo spark request. Yahoo rejects much larger lists. */
const SPARK_CHUNK = 20;
/** Spark chunks in flight at once. */
const SPARK_CONCURRENCY = 4;
/** Per-request timeout, so one slow call cannot eat a whole tick. */
const FETCH_TIMEOUT_MS = 6000;
/** Per-symbol chart fallbacks allowed per tick, for symbols the batch skipped. */
const FALLBACKS_PER_TICK = 8;
/** A symbol the batch keeps skipping is retried one-by-one at most this often. */
const FALLBACK_EVERY_MS = 60_000;
/** Backoff ladder after Yahoo throttles or blocks us. */
const BACKOFF_MS = [10_000, 30_000, 60_000, 120_000];
/** A second run starting this soon after the last one is ignored (abuse guard). */
const MIN_RUN_GAP_MS = 20_000;

type Row = {
  symbol: string;
  market: string;
  price: number;
  previous_close: number | null;
  name: string;
  change: number | null;
  change_pct: number | null;
  day_low: number | null;
  day_high: number | null;
  open: number | null;
  source: string;
  updated_at: string;
};

const round2 = (n: number) => Math.round(n * 100) / 100;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// ---------------------------------------------------------------------------
// Symbol mapping. Must agree with market-quote, which wrote these rows before.
// ---------------------------------------------------------------------------

function toYahoo(u: UniverseEntry): string | null {
  const s = u.symbol.toUpperCase();
  switch (u.market) {
    case "stock":
      if (s === "NIFTY" || s === "NIFTY50" || s === "^NSEI") return "^NSEI";
      if (s === "BANKNIFTY" || s === "^NSEBANK") return "^NSEBANK";
      if (s === "SENSEX" || s === "^BSESN") return "^BSESN";
      if (s.endsWith(".NS") || s.endsWith(".BO") || s.startsWith("^")) return s;
      return `${s === "ZOMATO" ? "ETERNAL" : s}.NS`;
    case US_MARKET:
    case COMMODITY_MARKET:
      return toUsYahooSymbol(s);
    case "pakistan_stock":
      return s.endsWith(".KA") ? s : `${s}.KA`;
    case "italy_stock":
      return s.endsWith(".MI") ? s : `${s}.MI`;
    default:
      return null;
  }
}

const CRYPTO_ALIAS: Record<string, string> = { MATIC: "POL" };

// ---------------------------------------------------------------------------
// Yahoo
// ---------------------------------------------------------------------------

class YahooThrottled extends Error {
  constructor(status: number) {
    super(`yahoo_${status}`);
  }
}

/**
 * Yahoo's CDN serves spark responses with `max-age=300` (plus 120s
 * stale-while-revalidate), so the same URL fetched every few seconds returns
 * the same price for up to 7 minutes (seen 23 Nov: the cache held NIFTY at
 * 25879.1 while Yahoo itself said 25830.9). A unique query parameter makes
 * every request miss that cache and reach the origin.
 */
function bust(url: string): string {
  return `${url}${url.includes("?") ? "&" : "?"}_=${Date.now()}${Math.floor(Math.random() * 1000)}`;
}

async function getJson(url: string): Promise<any> {
  const res = await fetch(bust(url), {
    headers: { "User-Agent": UA, Accept: "application/json", "Cache-Control": "no-cache" },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (res.status === 429 || res.status === 403) throw new YahooThrottled(res.status);
  if (!res.ok) throw new Error(`http_${res.status}`);
  return res.json();
}

/** Which spark flavour worked last; remembered for the rest of the run. */
let sparkPath = "/v7/finance/spark";
let hostIdx = 0;

async function sparkChunk(symbols: string[]): Promise<Map<string, Parsed>> {
  // Daily bars over 5 days: enough to find the previous session's close even
  // after a long weekend (see fromMeta for why chartPreviousClose is not used).
  const qs = `symbols=${symbols.map(encodeURIComponent).join(",")}&range=5d&interval=1d`;
  const paths = sparkPath === "/v7/finance/spark"
    ? ["/v7/finance/spark", "/v8/finance/spark"]
    : ["/v8/finance/spark", "/v7/finance/spark"];
  let lastErr: unknown = null;
  for (const path of paths) {
    try {
      const body = await getJson(`${YAHOO_HOSTS[hostIdx]}${path}?${qs}`);
      const parsed = parseSpark(body);
      if (parsed.size > 0) {
        sparkPath = path;
        return parsed;
      }
      lastErr = new Error("empty_spark");
    } catch (e) {
      if (e instanceof YahooThrottled) throw e;
      lastErr = e;
    }
  }
  hostIdx = (hostIdx + 1) % YAHOO_HOSTS.length;
  throw lastErr ?? new Error("spark_failed");
}

async function chartOne(yf: string): Promise<Parsed | null> {
  const body = await getJson(
    `${YAHOO_HOSTS[hostIdx]}/v8/finance/chart/${encodeURIComponent(yf)}?range=5d&interval=1d`,
  );
  const r = body?.chart?.result?.[0];
  return fromMeta(r?.meta, r?.indicators?.quote?.[0]?.close ?? [], r?.timestamp ?? []);
}

async function inPool<T, R>(items: T[], size: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = [];
  let i = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx]);
    }
  });
  await Promise.all(workers);
  return out;
}

// ---------------------------------------------------------------------------
// CoinDCX (all crypto in one request)
// ---------------------------------------------------------------------------

async function fetchCrypto(symbols: string[]): Promise<Map<string, Parsed>> {
  const out = new Map<string, Parsed>();
  if (symbols.length === 0) return out;
  const res = await fetch(COINDCX_TICKER, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`coindcx_${res.status}`);
  const tickers = await res.json();
  if (!Array.isArray(tickers)) return out;
  const byMarket = new Map<string, any>();
  for (const t of tickers) if (t?.market) byMarket.set(String(t.market), t);
  for (const sym of symbols) {
    const t = byMarket.get(`${CRYPTO_ALIAS[sym] ?? sym}INR`);
    const price = num(t?.last_price);
    if (!price) continue;
    const pct = Number(t.change_24_hour);
    out.set(sym, {
      price,
      previousClose: Number.isFinite(pct) && pct ? price / (1 + pct / 100) : price,
      dayLow: num(t.low),
      dayHigh: num(t.high),
      open: null,
      name: null,
      marketTime: null,
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// The feed
// ---------------------------------------------------------------------------

type TickResult = {
  rows: Row[];
  missing: string[];
  errors: string[];
  yahooMs: number;
  cryptoMs: number;
  throttled: boolean;
};

class Feed {
  private names = new Map<string, string>();
  /** Last known day range, kept when a response omits it rather than blanked. */
  private ranges = new Map<string, { l: number | null; h: number | null; o: number | null }>();
  private lastFallback = new Map<string, number>();
  private backoffLevel = -1;
  private backoffUntil = 0;

  constructor(private universe: UniverseEntry[]) {}

  async loadNames(supabase: any) {
    const { data } = await supabase.from("quotes_cache").select("symbol, market, name, day_low, day_high, open");
    for (const r of data ?? []) {
      const key = `${r.symbol}\u001f${r.market}`;
      if (r.name) this.names.set(key, r.name);
      // Rows written before the per-gram fix hold an ounce-sized day range for
      // Gold/Silver; never carry those forward.
      if (r.market === COMMODITY_MARKET && commodityUnitDivisor(r.symbol) !== 1) continue;
      this.ranges.set(key, { l: num(r.day_low), h: num(r.day_high), o: num(r.open) });
    }
  }

  async tick(force: boolean): Promise<TickResult> {
    const stockOpen = force || isStockOpen();
    const usOpen = force || isUsMarketOpen();
    const due = this.universe.filter((u) => force || isMarketOpen(u.market, stockOpen, usOpen));
    const now = Date.now();
    const nowIso = new Date(now).toISOString();
    const rows: Row[] = [];
    const missing: string[] = [];
    const errors: string[] = [];
    let throttled = false;

    const yahooEntries: { u: UniverseEntry; yf: string }[] = [];
    const cryptoEntries: UniverseEntry[] = [];
    for (const u of due) {
      if (u.market === "crypto") cryptoEntries.push(u);
      else {
        const yf = toYahoo(u);
        if (yf) yahooEntries.push({ u, yf });
      }
    }

    const build = (u: UniverseEntry, raw: Parsed, source: string): Row => {
      const key = `${u.symbol}\u001f${u.market}`;
      // Gold and Silver are stored per gram; Yahoo quotes them per troy ounce.
      // Must match market-quote, which priced every order and holding before.
      const p = u.market === COMMODITY_MARKET ? scaleParsed(raw, commodityUnitDivisor(u.symbol)) : raw;
      const prev = p.previousClose ?? p.price;
      const change = p.price - prev;
      const known = this.ranges.get(key);
      const range = {
        l: p.dayLow ?? known?.l ?? null,
        h: p.dayHigh ?? known?.h ?? null,
        o: p.open ?? known?.o ?? null,
      };
      this.ranges.set(key, range);
      return {
        symbol: u.symbol,
        market: u.market,
        price: round2(p.price),
        previous_close: round2(prev),
        // The cached name was chosen deliberately (curated list, long name);
        // keep it, and only fill a name for a symbol seen for the first time.
        name: this.names.get(key) ?? p.name ?? (u.market === US_MARKET ? fromUsYahooSymbol(u.symbol) : u.symbol),
        change: round2(change),
        change_pct: round2(prev ? (change / prev) * 100 : 0),
        day_low: range.l !== null ? round2(range.l) : null,
        day_high: range.h !== null ? round2(range.h) : null,
        open: range.o !== null ? round2(range.o) : null,
        source,
        updated_at: nowIso,
      };
    };

    // Yahoo and CoinDCX in parallel.
    const yahooStart = Date.now();
    const yahooTask = (async () => {
      if (yahooEntries.length === 0 || now < this.backoffUntil) return;
      const unique = [...new Set(yahooEntries.map((e) => e.yf))];
      const chunks: string[][] = [];
      for (let i = 0; i < unique.length; i += SPARK_CHUNK) chunks.push(unique.slice(i, i + SPARK_CHUNK));
      const got = new Map<string, Parsed>();
      try {
        const parts = await inPool(chunks, SPARK_CONCURRENCY, async (c) => {
          try {
            return await sparkChunk(c);
          } catch (e) {
            if (e instanceof YahooThrottled) throw e;
            errors.push(`spark:${e instanceof Error ? e.message : e}`);
            return new Map<string, Parsed>();
          }
        });
        for (const m of parts) for (const [k, v] of m) got.set(k, v);
        // A few one-by-one fallbacks for symbols the batch did not return,
        // pending-order symbols first because the universe is sorted that way.
        let budget = FALLBACKS_PER_TICK;
        for (const { yf } of yahooEntries) {
          if (got.has(yf.toUpperCase()) || budget <= 0) continue;
          if (now - (this.lastFallback.get(yf) ?? 0) < FALLBACK_EVERY_MS) continue;
          this.lastFallback.set(yf, now);
          budget--;
          try {
            const p = await chartOne(yf);
            if (p) got.set(yf.toUpperCase(), p);
          } catch (e) {
            if (e instanceof YahooThrottled) throw e;
          }
        }
        this.backoffLevel = -1;
      } catch (e) {
        if (!(e instanceof YahooThrottled)) throw e;
        throttled = true;
        this.backoffLevel = Math.min(this.backoffLevel + 1, BACKOFF_MS.length - 1);
        this.backoffUntil = Date.now() + BACKOFF_MS[this.backoffLevel];
        errors.push(`${e.message}: backing off ${BACKOFF_MS[this.backoffLevel] / 1000}s`);
      }
      for (const { u, yf } of yahooEntries) {
        const p = got.get(yf.toUpperCase());
        if (p) rows.push(build(u, p, "yahoo_batch"));
        else missing.push(`${u.symbol}:${u.market}`);
      }
    })();

    const cryptoStart = Date.now();
    let cryptoMs = 0;
    const cryptoTask = (async () => {
      try {
        const got = await fetchCrypto(cryptoEntries.map((u) => u.symbol));
        for (const u of cryptoEntries) {
          const p = got.get(u.symbol);
          if (p) rows.push(build(u, p, "coindcx"));
          else missing.push(`${u.symbol}:crypto`);
        }
      } catch (e) {
        errors.push(`crypto:${e instanceof Error ? e.message : e}`);
      } finally {
        cryptoMs = Date.now() - cryptoStart;
      }
    })();

    let yahooMs = 0;
    await Promise.all([
      yahooTask.catch((e) => errors.push(`yahoo:${e instanceof Error ? e.message : e}`)).finally(() => {
        yahooMs = Date.now() - yahooStart;
      }),
      cryptoTask,
    ]);
    return { rows, missing, errors, yahooMs, cryptoMs, throttled };
  }
}

/** Sends one broadcast with every changed price. One message per listening phone. */
async function broadcast(rows: Row[]): Promise<void> {
  if (rows.length === 0) return;
  const q = rows.map((r) => ({
    s: r.symbol, m: r.market, p: r.price, pc: r.previous_close,
    c: r.change, cp: r.change_pct, l: r.day_low, h: r.day_high, o: r.open, n: r.name,
  }));
  const res = await fetch(`${SUPABASE_URL}/realtime/v1/api/broadcast`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messages: [{ topic: PRICE_TOPIC, event: "tick", payload: { t: Date.now(), q }, private: false }],
    }),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`broadcast_${res.status}`);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function run(opts: { runId: string; force: boolean; tickMs: number; broadcastMs: number; durationMs: number }) {
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  const started = Date.now();
  const universe = await buildUniverse(supabase);
  const feed = new Feed(universe);
  await feed.loadNames(supabase);

  const lastSent = new Map<string, string>();
  const pending = new Map<string, Row>();
  let lastBroadcast = 0;
  let ticks = 0;

  while (Date.now() - started < opts.durationMs) {
    const tickStart = Date.now();
    const res = await feed.tick(opts.force);
    ticks++;

    if (res.rows.length > 0) {
      const { error } = await supabase.from("quotes_cache").upsert(res.rows, { onConflict: "symbol,market" });
      if (error) res.errors.push(`upsert:${error.message}`);
    }

    for (const r of res.rows) {
      const key = `${r.symbol}\u001f${r.market}`;
      const sig = `${r.price}|${r.day_low}|${r.day_high}`;
      if (lastSent.get(key) !== sig) pending.set(key, r);
    }
    if (pending.size > 0 && Date.now() - lastBroadcast >= opts.broadcastMs) {
      const batch = [...pending.values()];
      try {
        await broadcast(batch);
        for (const r of batch) lastSent.set(`${r.symbol}\u001f${r.market}`, `${r.price}|${r.day_low}|${r.day_high}`);
        pending.clear();
        lastBroadcast = Date.now();
      } catch (e) {
        res.errors.push(e instanceof Error ? e.message : String(e));
      }
    }

    // Heartbeat and lease in one write: a newer run has taken over when this
    // update matches no row, and this loop then stops.
    const { data: lease } = await supabase
      .from("price_feed_state")
      .update({
        last_tick_at: new Date().toISOString(),
        last_tick_ms: Date.now() - tickStart,
        last_rows: res.rows.length,
        last_missing: res.missing.slice(0, 50),
        last_errors: res.errors.slice(0, 20),
        yahoo_ms: res.yahooMs,
        crypto_ms: res.cryptoMs,
        ticks,
      })
      .eq("id", 1)
      .eq("run_id", opts.runId)
      .select("id");
    if (!lease || lease.length === 0) break;

    const jitter = Math.floor(Math.random() * 400) - 200;
    await sleep(Math.max(250, opts.tickMs + jitter - (Date.now() - tickStart)));
  }
}

serve(async (req) => {
  const url = new URL(req.url);
  const p = (k: string, d: number, min: number, max: number) => {
    const v = Number(url.searchParams.get(k));
    return Number.isFinite(v) && v > 0 ? Math.min(max, Math.max(min, v)) : d;
  };
  const force = url.searchParams.get("force") === "1";
  const dry = url.searchParams.get("dry") === "1";
  const tickMs = p("tick_ms", 3000, 1000, 30_000);
  const broadcastMs = p("broadcast_ms", 5000, 1000, 60_000);
  const durationMs = p("duration_s", 58, 5, 300) * 1000;

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    if (dry) {
      const universe = await buildUniverse(supabase);
      const feed = new Feed(universe);
      await feed.loadNames(supabase);
      const t0 = Date.now();
      const res = await feed.tick(force);
      return json({
        dry: true,
        universe: universe.length,
        rows: res.rows.length,
        tick_ms: Date.now() - t0,
        yahoo_ms: res.yahooMs,
        crypto_ms: res.cryptoMs,
        spark_path: sparkPath,
        throttled: res.throttled,
        missing: res.missing,
        errors: res.errors,
        sample: res.rows.slice(0, 40),
      });
    }

    // Take the lease. A run that started less than MIN_RUN_GAP_MS ago keeps it,
    // so stray extra invocations cost one cheap request each and nothing else.
    const runId = crypto.randomUUID();
    const { data: state } = await supabase.from("price_feed_state").select("run_started_at").eq("id", 1).maybeSingle();
    const lastStart = state?.run_started_at ? new Date(state.run_started_at).getTime() : 0;
    if (!force && Date.now() - lastStart < MIN_RUN_GAP_MS) {
      return json({ skipped: "a run started moments ago" }, 202);
    }
    const { error } = await supabase
      .from("price_feed_state")
      .upsert({ id: 1, run_id: runId, run_started_at: new Date().toISOString() }, { onConflict: "id" });
    if (error) return json({ error: error.message }, 500);

    const work = run({ runId, force, tickMs, broadcastMs, durationMs }).catch((e) =>
      console.error("[price-feed] run failed", e)
    );
    if (typeof EdgeRuntime !== "undefined") {
      EdgeRuntime.waitUntil(work);
      return json({ started: runId }, 202);
    }
    await work;
    return json({ finished: runId });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
