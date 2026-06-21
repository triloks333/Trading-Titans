import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchQuote as yfQuote } from "../_shared/yahoo.ts";
import { fetchQuote as cgQuote } from "../_shared/coingecko.ts";
import { fetchQuote as biQuote } from "../_shared/binance.ts";
import { fetchQuote as cxQuote } from "../_shared/coindcx.ts";

serve(async (req) => {
  const __start = Date.now();
  let __status = 200;
  try {
    const __res = await handleRequest(req);
    __status = __res.status;
    return __res;
  } finally {
    console.log(`[market-overview] ${req.method} ${Date.now() - __start}ms status=${__status}`);
  }
});

async function handleRequest(req: Request): Promise<Response> {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const results: Record<string, unknown>[] = [];

    // Indices
    for (const [sym, display] of Object.entries({
      "^NSEI": "NIFTY 50",
      "^BSESN": "SENSEX",
      "^NSEBANK": "BANK NIFTY",
    })) {
      try {
        const q = await yfQuote(sym);
        results.push({ ...q, display_name: display, category: "index" });
      } catch {
        // skip
      }
    }

    // Top crypto - use CoinDCX/Binance for high performance
    for (const sym of ["BTC", "ETH", "SOL"]) {
      try {
        let q: Record<string, any> | null = null;
        try {
          q = await cxQuote(sym);
        } catch (_) {}
        if (!q) {
          try {
            q = await biQuote(sym);
          } catch (_) {}
        }
        if (!q) {
          try {
            q = await cgQuote(sym);
          } catch (_) {}
        }
        if (q) {
          results.push({ ...q, display_name: q.name || q.display_name, category: "crypto" });
        }
      } catch {
        // skip
      }
    }



    return new Response(JSON.stringify(results), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
