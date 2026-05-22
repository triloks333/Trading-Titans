import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchQuote as yfQuote } from "../_shared/yahoo.ts";
import { fetchQuote as cgQuote } from "../_shared/coingecko.ts";

serve(async (req) => {
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

    // Top crypto
    for (const sym of ["BTC", "ETH", "SOL"]) {
      try {
        const q = await cgQuote(sym);
        results.push({ ...q, display_name: q.name, category: "crypto" });
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
});
