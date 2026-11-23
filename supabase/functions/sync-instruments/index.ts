import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { exchangeFor, monthlyExpiry } from "../_shared/expiry_calendar.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

type Row = {
  fyers_token: string;
  symbol: string;
  name: string;
  market: string;
  instrument_type: string;
  expiry_date: string | null;
  strike_price: number | null;
  option_type: string | null;
  lot_size: number;
  tradeable: boolean;
};

/// Lines of a remote CSV, streamed, so memory stays flat however big the
/// master file is (NSE_FO.csv is ~94k lines).
async function* csvLines(url: string): AsyncGenerator<string> {
  const res = await fetch(url);
  if (!res.ok || !res.body) throw new Error(`${url}: HTTP ${res.status}`);
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  let rest = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    const parts = (rest + value).split("\n");
    rest = parts.pop() ?? "";
    for (const p of parts) yield p;
  }
  if (rest) yield rest;
}

// One invocation cannot parse and upsert all ~110k rows: the worker is killed
// for CPU time (2s budget; logs show "CPU Time exceeded"), which is why the
// contract list could go stale without anyone noticing. The work is split into
// parts, each its own invocation, fired one per minute (03:10-03:19 UTC) by cron
// `fyers-instrument-sync`. Not in parallel: concurrent requests share a worker
// and its CPU budget, and most of them were killed when fired together.
//   ?part=equity      NSE cash symbols
//   ?part=nse&shard=k NSE F&O, every NSE_SHARDS-th line starting at line k
//   ?part=bse         BSE index F&O (SENSEX, BANKEX)
//   ?part=check       03:25 UTC: confirms every part logged success,
//                     cross-checks expiries, writes the `sync-instruments` row
//                     that check_fo_expiry_health() reads.
const NSE_SHARDS = 8;
const CHECK_UNDERLYINGS = ["NIFTY", "BANKNIFTY", "RELIANCE", "SENSEX"];

// deno-lint-ignore no-explicit-any
type Client = any;

function makeUpserter(supabase: Client) {
  let batch: Row[] = [];
  let total = 0;
  const flush = async () => {
    if (batch.length === 0) return;
    const { error } = await supabase.from("instruments").upsert(batch);
    if (error) {
      console.error(`Upsert failed after ${total} rows:`, error);
      throw error;
    }
    total += batch.length;
    batch = [];
  };
  const push = async (row: Row) => {
    batch.push(row);
    if (batch.length >= 1000) await flush();
  };
  return { push, flush, count: () => total };
}

async function syncEquity(supabase: Client): Promise<number> {
  const up = makeUpserter(supabase);
  // Equity format: 0: token, 1: name, 2: inst_type, 3: lot, 4: tick, 9: symbol
  for await (const line of csvLines("https://public.fyers.in/sym_details/NSE_CM.csv")) {
    if (!line.trim()) continue;
    const r = line.split(",");
    if (r.length < 10) continue;
    const sym = r[9].trim();
    await up.push({
      fyers_token: r[0].trim(),
      symbol: sym,
      name: r[1].trim(),
      market: "stock",
      instrument_type: "EQUITY",
      expiry_date: null,
      strike_price: null,
      option_type: null,
      lot_size: Number(r[3]) || 1,
      // Only -EQ and -SM suffixed stocks are tradeable equities
      tradeable: sym.endsWith("-EQ") || sym.endsWith("-SM"),
    });
  }
  await up.flush();
  return up.count();
}

/// NSE and BSE F&O masters share the Fyers column layout, so one parser
/// serves both. [ownsLine] picks this invocation's share of the file by line
/// index (checked before any parsing); [keep] filters by symbol. BSE is kept
/// to the index families the app offers (SENSEX, BANKEX): without them SENSEX
/// had no contracts here at all and the app invented last-Thursday monthlies
/// instead of the real weekly Thursdays.
async function syncFo(
  supabase: Client,
  url: string,
  ownsLine: (i: number) => boolean,
  keep: (symbol: string) => boolean,
): Promise<number> {
  const up = makeUpserter(supabase);
  // Sampled once, not per row, so a sync that straddles midnight cannot flag
  // one half of the CSV against one date and the other half against the next.
  const todayIso = new Date().toISOString().split("T")[0];
  let i = -1;
  for await (const line of csvLines(url)) {
    i++;
    if (!ownsLine(i) || !line.trim()) continue;
    const r = line.split(",");
    if (r.length < 10) continue;

    // FO Format:
    // 0: token, 1: name, 2: inst_type, 3: lot, 8: expiry_epoch, 9: symbol, 15: strike, 16: opt_type
    const symbol = r[9].trim();
    const upper = symbol.toUpperCase();

    // Index families the app does not offer, and which actively break the
    // lot-size lookup for the index it DOES offer.
    //
    // Lot size is resolved with `LIKE 'NSE:<underlying>%'`, a prefix match, so
    // `NSE:NIFTY%` returns NIFTYNXT50 (lot 25) and NIFTYFPI (lot 1100)
    // alongside NIFTY (lot 65). NIFTYNXT50 lists only monthly expiries and
    // outnumbers NIFTY on those dates, so NIFTY monthlies were resolving to 25
    // and users saw the wrong lot size on the order screen.
    //
    // The engine-side resolver now filters on an exact underlying boundary
    // (see _shared/lot_size.ts), but the Flutter client carries its own copy of
    // the prefix query at fo_instruments_service.dart and cannot be fixed
    // without an app release. Keeping these two families out of `instruments`
    // removes the ambiguity at the source, so the shipped client resolves NIFTY
    // correctly with no update. Neither index has ever been traded (zero orders,
    // zero positions) and neither is reachable in the UI, which only maps
    // NIFTY, BANKNIFTY, FINNIFTY, MIDCPNIFTY and SENSEX.
    //
    // ponytail: an exclusion list, not a general rule. The ceiling is that a
    // future NSE index prefixing an offered one has to be added here by hand;
    // the query in docs that enumerates prefix collisions is the early warning.
    // Remove these lines once the client resolver is fixed and shipped.
    if (/^(NIFTYNXT50|NIFTYFPI)\d/.test(upper)) continue;
    if (!keep(upper)) continue;
    const optType = r.length > 16 ? r[16].trim() : "XX";

    let instType = "FUTURE";
    let finalOptType: string | null = null;
    if (optType === "CE" || optType === "PE") {
      instType = "OPTION";
      finalOptType = optType;
    }

    let expiryDate: string | null = null;
    const epoch = Number(r[8].trim());
    if (epoch > 0) expiryDate = new Date(epoch * 1000).toISOString().split("T")[0];

    let strike: number | null = null;
    if (instType === "OPTION") {
      const s = Number(r[15].trim());
      if (Number.isFinite(s)) strike = s;
    }

    await up.push({
      fyers_token: r[0].trim(),
      symbol,
      name: r[1].trim(),
      market: "stock",
      instrument_type: instType,
      expiry_date: expiryDate,
      strike_price: strike,
      option_type: finalOptType,
      lot_size: Number(r[3]) || 1,
      // Was a hard-coded `true`, which is only true of contracts that have not
      // expired yet. This sync runs at 03:20 UTC, after the 18:30 UTC
      // `deactivate_expired_instruments()` sweep, so an expired contract still
      // listed in the CSV got its `tradeable` flag back every morning. ISO
      // dates compare correctly as strings. A contract with no parseable
      // expiry cannot be priced or settled, so it is not tradeable.
      tradeable: expiryDate != null && expiryDate >= todayIso,
    });
  }
  await up.flush();
  return up.count();
}

/// Confirms every part of this morning's sync succeeded and that the
/// exchange's monthly futures expiries match the fallback calendar the app and
/// server use when a symbol is missing. A mismatch means the holiday list or
/// the exchange's rule changed; check_fo_expiry_health() raises it to admins.
async function check(supabase: Client) {
  const since = new Date(Date.now() - 3 * 3600 * 1000).toISOString();
  const { data: runs, error } = await supabase.from("fo_sync_runs")
    .select("source, ok, nse_fo_rows, bse_fo_rows, error")
    .like("source", "sync-instruments:%").gte("run_at", since);
  if (error) throw error;
  const expected = ["equity", "bse", ...Array.from({ length: NSE_SHARDS }, (_, k) => `nse:${k}`)];
  const warnings: string[] = [];
  let nseFoRows = 0;
  let bseFoRows = 0;
  let allOk = true;
  for (const part of expected) {
    // deno-lint-ignore no-explicit-any
    const rows = (runs ?? []).filter((r: any) => r.source === `sync-instruments:${part}`);
    // deno-lint-ignore no-explicit-any
    const good = rows.find((r: any) => r.ok);
    if (!good) {
      allOk = false;
      // deno-lint-ignore no-explicit-any
      const err = rows.find((r: any) => !r.ok)?.error;
      warnings.push(`part ${part} ${err ? `failed: ${err}` : "did not finish"}`);
      continue;
    }
    nseFoRows += Number(good.nse_fo_rows ?? 0);
    bseFoRows += Number(good.bse_fo_rows ?? 0);
  }
  if (nseFoRows === 0) { allOk = false; warnings.push("NSE FO master had no rows"); }
  if (bseFoRows === 0) warnings.push("BSE FO master had no SENSEX/BANKEX rows");

  const today = new Date().toISOString().split("T")[0];
  for (const und of CHECK_UNDERLYINGS) {
    const prefix = `${exchangeFor(und)}:${und}`;
    const { data: futs, error: fe } = await supabase.from("instruments")
      .select("symbol, expiry_date")
      .eq("instrument_type", "FUTURE").like("symbol", `${prefix}2%`).gte("expiry_date", today)
      .limit(10);
    if (fe) throw fe;
    if (!futs || futs.length === 0) {
      warnings.push(`${und}: no live futures in the contract list`);
      continue;
    }
    for (const f of futs) {
      const exp = String(f.expiry_date);
      const [y, m] = exp.split("-").map(Number);
      const rule = monthlyExpiry(y, m, exchangeFor(und));
      if (rule !== exp) warnings.push(`${und} ${y}-${m}: exchange ${exp}, rule ${rule}`);
    }
  }
  if (warnings.length) console.warn("Sync check:", warnings);
  await supabase.from("fo_sync_runs").insert({
    source: "sync-instruments", ok: allOk, nse_fo_rows: nseFoRows, bse_fo_rows: bseFoRows, warnings,
    error: allOk ? null : "one or more sync parts did not succeed",
  });
  return { ok: allOk, nseFoRows, bseFoRows, warnings };
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const params = new URL(req.url).searchParams;
  const part = params.get("part") ?? "";
  const shard = Number(params.get("shard") ?? "0");
  const source = part === "nse" ? `sync-instruments:nse:${shard}` : `sync-instruments:${part}`;
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  try {
    if (part === "check") return json(await check(supabase));

    let rows = 0;
    if (part === "equity") {
      rows = await syncEquity(supabase);
    } else if (part === "nse" && Number.isInteger(shard) && shard >= 0 && shard < NSE_SHARDS) {
      rows = await syncFo(supabase, "https://public.fyers.in/sym_details/NSE_FO.csv", (i) => i % NSE_SHARDS === shard, () => true);
    } else if (part === "bse") {
      rows = await syncFo(supabase, "https://public.fyers.in/sym_details/BSE_FO.csv",
        () => true, (sym) => /^BSE:(SENSEX|BANKEX)\d/.test(sym));
    } else {
      return json({ error: `unknown part; use part=equity|bse|check or part=nse&shard=0..${NSE_SHARDS - 1}` }, 400);
    }
    console.log(`${source}: ${rows} rows`);
    await supabase.from("fo_sync_runs").insert({
      source, ok: true,
      nse_fo_rows: part === "nse" ? rows : null,
      bse_fo_rows: part === "bse" ? rows : null,
    });
    return json({ success: true, part: source, rows });
  } catch (err) {
    const msg = String((err as Error)?.message ?? err);
    try {
      await supabase.from("fo_sync_runs").insert({ source: part === "check" ? "sync-instruments" : source, ok: false, error: msg });
    } catch (_) { /* logging must not mask the original error */ }
    return json({ error: msg }, 500);
  }
});
