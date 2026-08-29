import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { unzipSync } from "https://esm.sh/fflate@0.8.2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
};

const HEADERS: Record<string, string> = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
  // Akamai fronts nsearchives and serves a 404 -- not a 403 -- to requests that
  // arrive without a browsing context. The same URLs that answered 404 here
  // returned 200 with a ~900KB payload from a residential connection, which is
  // what sent this chasing a date-format bug that did not exist. A Referer plus
  // the session cookies primed below is what makes the archive answer.
  "Referer": "https://www.nseindia.com/all-reports-derivatives",
};

/// NSE hands out session cookies on its HTML pages and its CDN expects them on
/// the archive request. Returns a `Cookie` header value, or "" if priming failed
/// (in which case the download is still attempted bare -- it costs nothing to
/// try, and NSE has served these files unauthenticated in the past).
///
/// ponytail: primed once per invocation, not cached across invocations. The
/// ceiling is one extra HTML fetch per daily run; the upgrade path is stashing
/// the cookie jar in a table with its expiry if this ever runs per-minute.
async function primeNseCookies(): Promise<string> {
  const jar: string[] = [];
  for (const page of ["https://www.nseindia.com/", "https://www.nseindia.com/all-reports-derivatives"]) {
    try {
      const r = await fetch(page, { headers: HEADERS, redirect: "follow", signal: AbortSignal.timeout(15000) });
      // Deno exposes repeated Set-Cookie via getSetCookie(); fall back to the
      // single-header form on older runtimes.
      const raw = typeof (r.headers as any).getSetCookie === "function"
        ? (r.headers as any).getSetCookie() as string[]
        : [r.headers.get("set-cookie") ?? ""];
      for (const c of raw) {
        const pair = (c ?? "").split(";")[0].trim();
        if (pair.includes("=")) jar.push(pair);
      }
      await r.body?.cancel();
    } catch (e) {
      console.log(`Cookie priming failed for ${page}: ${e}`);
    }
  }
  // Later pages win on duplicate names.
  const dedup = new Map<string, string>();
  for (const pair of jar) dedup.set(pair.slice(0, pair.indexOf("=")), pair);
  const cookie = [...dedup.values()].join("; ");
  console.log(`Primed ${dedup.size} NSE cookies.`);
  return cookie;
}

function bhavcopyUrl(dateStr: string): string {
  return `https://nsearchives.nseindia.com/content/fo/BhavCopy_NSE_FO_0_0_0_${dateStr}_F_0000.csv.zip`;
}

/// Candidate dates, newest first: today in IST then up to `lookback` calendar
/// days back.
///
/// The old code asked for today and nothing else, so one 404 -- a weekend, a
/// holiday, or the exchange publishing late -- left the table at whatever it last
/// held. Production sat on 2026-08-21 for eight days while five trading days went
/// by, which is why option premiums fell through to the Black-Scholes estimate.
/// Weekends and NSE holidays need no calendar here: a non-trading day simply has
/// no file, so it 404s and the walk continues.
function candidateDates(lookback: number): string[] {
  const istNow = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
  const out: string[] = [];
  for (let i = 0; i <= lookback; i++) {
    const d = new Date(istNow.getTime() - i * 86400000);
    out.push(
      `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}${String(d.getUTCDate()).padStart(2, "0")}`,
    );
  }
  return out;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const url = new URL(req.url);
    const explicitDate = url.searchParams.get("date"); // Format: YYYYMMDD
    const lookback = Number(url.searchParams.get("lookback") ?? "7");
    const dates = explicitDate ? [explicitDate] : candidateDates(Number.isFinite(lookback) ? lookback : 7);

    const cookie = await primeNseCookies();
    const dlHeaders = cookie ? { ...HEADERS, Cookie: cookie } : HEADERS;

    // Walk the candidates newest-first and take the first one that answers. Each
    // date gets two attempts, because Akamai's first response to a fresh session
    // is sometimes a 404 that a retry on the same cookies then satisfies.
    let response: Response | null = null;
    let dateStr = "";
    const attempts: string[] = [];
    outer:
    for (const d of dates) {
      for (let attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await new Promise((r) => setTimeout(r, 1200));
        try {
          const r = await fetch(bhavcopyUrl(d), { headers: dlHeaders, signal: AbortSignal.timeout(30000) });
          if (r.ok) { response = r; dateStr = d; break outer; }
          await r.body?.cancel();
          attempts.push(`${d}:http_${r.status}`);
        } catch (e) {
          attempts.push(`${d}:${e instanceof Error ? e.message : String(e)}`);
        }
      }
    }

    if (!response) {
      // 502, not 404: the upstream is unreachable, which is a different problem
      // from "this function was called wrongly" and should page differently.
      console.error(`No bhavcopy available. Attempts: ${attempts.join(", ")}`);
      return new Response(
        JSON.stringify({
          success: false,
          error: "No NSE bhavcopy could be downloaded for any candidate date.",
          tried: attempts,
          cookies_primed: cookie.length > 0,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Downloaded NSE F&O Bhavcopy for ${dateStr} (after ${attempts.length} miss(es)).`);
    const zipBytes = await response.arrayBuffer();
    console.log(`Extracting zip data of size ${zipBytes.byteLength} bytes...`);

    const decompressed = unzipSync(new Uint8Array(zipBytes));
    const csvFilename = Object.keys(decompressed).find(name => name.endsWith('.csv'));
    
    if (!csvFilename) {
      throw new Error("No CSV file found inside the zip archive.");
    }

    const csvText = new TextDecoder().decode(decompressed[csvFilename]);
    
    let newlineIndex = csvText.indexOf("\n");
    if (newlineIndex === -1) {
      throw new Error("Invalid CSV: No newline found.");
    }
    const headerLine = csvText.substring(0, newlineIndex).trim();

    console.log("Parsing CSV text and sending in chunks to Postgres RPC...");
    
    let chunkStart = 0;
    let lineCount = 0;
    let searchIndex = 0;
    let totalUploaded = 0;
    let chunkCount = 0;

    while (true) {
      const nextNewline = csvText.indexOf("\n", searchIndex);
      if (nextNewline === -1) {
        const lastChunk = csvText.substring(chunkStart);
        if (lastChunk.trim()) {
          chunkCount++;
          console.log(`Sending final chunk ${chunkCount} to Postgres...`);
          const payload = (chunkStart === 0) ? lastChunk : (headerLine + "\n" + lastChunk);
          const { error } = await supabase.rpc("import_fo_bhavcopy_csv", { csv_text: payload });
          if (error) {
            console.error(`RPC error for final chunk:`, error);
            throw error;
          }
        }
        break;
      }
      lineCount++;
      searchIndex = nextNewline + 1;
      if (lineCount >= 15000) {
        chunkCount++;
        console.log(`Sending chunk ${chunkCount} to Postgres...`);
        const chunk = csvText.substring(chunkStart, nextNewline);
        const payload = (chunkStart === 0) ? chunk : (headerLine + "\n" + chunk);
        const { error } = await supabase.rpc("import_fo_bhavcopy_csv", { csv_text: payload });
        if (error) {
          console.error(`RPC error for chunk ${chunkCount}:`, error);
          throw error;
        }
        totalUploaded += lineCount;
        chunkStart = nextNewline + 1;
        lineCount = 0;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
    }

    console.log(`Finished uploading CSV in ${chunkCount} chunks.`);

    // Call staging sync to cascade values to instruments/fo_instruments directly from nse_fo_bhavcopy
    const { error: rpcError } = await supabase.rpc("sync_lots_from_staging");
    if (rpcError) {
      console.error("Sync RPC failed:", rpcError);
      throw rpcError;
    }

    return new Response(
      JSON.stringify({ success: true, message: "Successfully synced F&O bhavcopy and updated instruments.", date: dateStr }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("sync-nse-bhavcopy fatal error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
