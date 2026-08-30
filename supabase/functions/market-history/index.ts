import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchHistory as yfHistory } from "../_shared/yahoo.ts";
import { fetchHistory as cgHistory } from "../_shared/coingecko.ts";
import { US_MARKET, toUsYahooSymbol } from "../_shared/us_market.ts";

serve(async (req) => {
  const __start = Date.now();
  let __status = 200;
  try {
    const __res = await handleRequest(req);
    __status = __res.status;
    return __res;
  } finally {
    console.log(`[market-history] ${req.method} ${Date.now() - __start}ms status=${__status}`);
  }
});

async function handleRequest(req: Request): Promise<Response> {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const symbol = url.searchParams.get("symbol") ?? "";
    const market = url.searchParams.get("market") ?? "stock";
    const range = url.searchParams.get("range") ?? "1mo";
    const interval = url.searchParams.get("interval") ?? "";
    // Opt-in: respect `range` and `interval` exactly as supplied. See the note on
    // `strict` in _shared/yahoo.ts for why this is not simply the default.
    const strict = url.searchParams.get("strict") === "1";

    if (!symbol) {
      return new Response(JSON.stringify({ error: "symbol required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let data;
    if (market === "crypto") {
      data = await cgHistory(symbol, range, interval || undefined);
    } else if (market === US_MARKET) {
      // US charts were failing for EVERY symbol and every timeframe with a 500.
      // `toYfSymbol` appends ".NS" to anything without a suffix, so the request
      // went to Yahoo as AAPL.NS — a listing that does not exist. market-quote
      // already resolved US tickers correctly via toUsYahooSymbol; this path
      // never did, so no US instrument has ever had a working chart.
      data = await yfHistory(symbol, range, interval || undefined, {
        yfSymbol: toUsYahooSymbol(symbol),
        strict,
      });
    } else {
      data = await yfHistory(symbol, range, interval || undefined, { strict });
    }

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
