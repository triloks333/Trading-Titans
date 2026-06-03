import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchQuote as yfQuote } from "../_shared/yahoo.ts";
import { fetchQuote as cgQuote } from "../_shared/coingecko.ts";
import { fetchQuote as uxQuote } from "../_shared/upstox.ts";
import { fetchQuote as fyQuote } from "../_shared/fyers.ts";
import { fetchQuote as biQuote } from "../_shared/binance.ts";
import { fetchQuote as cxQuote } from "../_shared/coindcx.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const symbol = url.searchParams.get("symbol") ?? "";
    const market = url.searchParams.get("market") ?? "stock";

    if (!symbol) {
      return new Response(JSON.stringify({ error: "symbol required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let quote: Record<string, unknown> | null = null;

    if (market === "crypto") {
      try {
        quote = await cxQuote(symbol);
      } catch (_) {}
      if (!quote) {
        try {
          quote = await biQuote(symbol);
        } catch (_) {}
      }
      if (!quote) {
        try {
          quote = await cgQuote(symbol);
        } catch (_) {}
      }
    } else {
      try {
        quote = await fyQuote(symbol);
      } catch (_) {}
      if (!quote) {
        try {
          quote = await uxQuote(symbol);
        } catch (_) {}
      }
      if (!quote) {
        try {
          quote = await yfQuote(symbol);
        } catch (_) {}
      }
    }

    if (!quote) {
      return new Response(JSON.stringify({ error: "No data for symbol" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(quote), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

