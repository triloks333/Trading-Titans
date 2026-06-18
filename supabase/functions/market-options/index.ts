import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchOptionChain as zerodhaOptionChain } from "../_shared/zerodha.ts";
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

    function normalizeSymbol(sym: string): string {
      let s = sym.toUpperCase().trim();
      const colonIndex = s.indexOf(":");
      if (colonIndex !== -1) {
        s = s.substring(colonIndex + 1);
      }
      if (s.endsWith("-EQ")) s = s.substring(0, s.length - 3);
      if (s.endsWith("-BE")) s = s.substring(0, s.length - 3);
      if (s.endsWith("-SM")) s = s.substring(0, s.length - 3);
      return s;
    }

    const normalized = normalizeSymbol(symbol);

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

    const resolvedStrikeCount = Number.isFinite(strikeCount) ? strikeCount : 25;
    const providerErrors: Record<string, string> = {};

    // Try Zerodha Option Chain first
    let chain = null;
    try {
      const zerodhaChain = await zerodhaOptionChain(normalized, resolvedStrikeCount);
      if (zerodhaChain) {
        chain = zerodhaChain;
      }
    } catch (err) {
      providerErrors.zerodha = String(err?.message ?? err);
      console.error("Zerodha option chain failed:", err);
    }

    // Fall back to Fyers
    if (!chain) {
      try {
        const fyersChain = await fyersOptionChain(normalized, resolvedStrikeCount);
        if (fyersChain) {
          chain = fyersChain;
        }
      } catch (err) {
        providerErrors.fyers = String(err?.message ?? err);
        console.error("Fyers option chain failed:", err);
      }
    }

    // Fall back to Yahoo Finance mock
    if (!chain) {
      try {
        const quote = await yfQuote(normalized);
        if (quote) {
          const spotPrice = (quote.price as number) ?? 100.0;
          const change = (quote.change as number) ?? 0.0;
          const changePct = (quote.change_pct as number) ?? 0.0;
          const mockChain = generateMockFyersChainAndFutures(normalized, spotPrice, change, changePct, resolvedStrikeCount);
          if (mockChain) {
            chain = { ...mockChain, source: "yahoo_mock" };
          }
        }
      } catch (err) {
        providerErrors.yahoo = String(err?.message ?? err);
        console.error("Yahoo mock fallback failed:", err);
      }
    }

    if (!chain) {
      return json({
        error: "Option chain providers all failed. Verify Fyers/Zerodha auth or use a valid NSE/BSE F&O symbol.",
        derivative_type: "options",
        source: "fallback",
        tried_providers: Object.keys(providerErrors),
        details: providerErrors,
      }, 404);
    }

    // Explicitly preference and label as NSE in metadata
    if (typeof chain === "object" && chain !== null) {
      (chain as any).exchange = "NSE";
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
