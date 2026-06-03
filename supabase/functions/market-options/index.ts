import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchOptionChain as fyersOptionChain, generateMockFyersChainAndFutures } from "../_shared/fyers.ts";
import { fetchFuturesChain as coindcxFuturesChain } from "../_shared/coindcx.ts";
import { fetchQuote as yfQuote } from "../_shared/yahoo.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const symbol = url.searchParams.get("symbol") ?? "";
    const market = url.searchParams.get("market") ?? "stock";
    const strikeCount = Number(url.searchParams.get("strike_count") ?? "25");

    if (!symbol) {
      return json({ error: "symbol required" }, 400);
    }

    if (market === "crypto") {
      const futures = await coindcxFuturesChain(symbol);
      if (!futures) {
        return json({
          error: "No CoinDCX futures contracts found for this crypto symbol.",
          derivative_type: "futures",
          source: "coindcx",
        }, 404);
      }
      return json(futures);
    }

    let chain = await fyersOptionChain(symbol, Number.isFinite(strikeCount) ? strikeCount : 25);
    if (!chain) {
      // Fallback: Fetch spot price from Yahoo Finance and generate mock chain & futures
      try {
        const quote = await yfQuote(symbol);
        if (quote) {
          const spotPrice = (quote.price as number) ?? 100.0;
          const change = (quote.change as number) ?? 0.0;
          const changePct = (quote.change_pct as number) ?? 0.0;
          chain = generateMockFyersChainAndFutures(symbol, spotPrice, change, changePct, strikeCount);
        }
      } catch (_) {}
    }

    if (!chain) {
      return json({
        error: "Fyers option chain unavailable and fallback failed. Check Fyers auth/token or try an F&O-enabled NSE/BSE symbol.",
        derivative_type: "options",
        source: "fyers",
      }, 404);
    }

    return json(chain);
  } catch (err) {
    return json({ error: err?.message ?? "Unable to fetch derivatives data" }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
