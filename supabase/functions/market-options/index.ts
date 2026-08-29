import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
// The Zerodha and Fyers option-chain providers used to be tried first. Both are
// dead: there are no broker credentials in this project (`fyers_tokens` expired
// 2026-06-05 and was never renewed) and the product does not use any broker API.
// Every request therefore paid for two guaranteed-failing round trips and then
// reported "Verify Fyers/Zerodha auth" — an auth error for something that is not
// an auth problem, which is what users saw over a ₹0.00 spot. Only the strike
// generator is still needed from the Fyers module.
import { generateMockFyersChainAndFutures } from "../_shared/fyers.ts";
import { fetchFuturesChain as coindcxFuturesChain } from "../_shared/coindcx.ts";
import { fetchQuote as yfQuote } from "../_shared/yahoo.ts";

serve(async (req) => {
  const __start = Date.now();
  let __status = 200;
  try {
    const __res = await handleRequest(req);
    __status = __res.status;
    return __res;
  } finally {
    console.log(`[market-options] ${req.method} ${Date.now() - __start}ms status=${__status}`);
  }
});

async function handleRequest(req: Request): Promise<Response> {
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
      // A CONTRACT symbol is not an underlying. Tapping through from a futures
      // position sent `ONGC26OCTFUT` here verbatim, which has no spot quote, so
      // the chain was built around a ₹0.00 spot. Only rewrites something that is
      // unambiguously a contract (letters, digits, then a FUT/CE/PE tail), so
      // real underlyings that contain hyphens or digits — `BAJAJ-AUTO`, `M&M`,
      // `360ONE` — pass through untouched. Mirrors public.fo_contract_underlying()
      // on the SQL side; keep the two in step.
      s = s.replace(/^([A-Z][A-Z&-]*?)\d.*(?:FUT|CE|PE)$/, "$1");
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

    // This endpoint is the LAST resort, and it is important to be honest about
    // that. The client tries `get_option_chain_quotes` first, which serves real
    // NSE open interest and closing prices from the daily bhavcopy; it only lands
    // here when that has nothing. Premiums below are a Black-Scholes estimate at a
    // flat 25% implied volatility, so they will not match the real board —
    // DIXON 15000CE priced at ₹419 here against ₹309 on the exchange. The
    // response carries `is_estimate` so the UI can say so rather than presenting
    // a model output as a market price.
    let chain = null;
    let spotUsed = 0;
    try {
      const quote = await yfQuote(normalized);
      if (quote) {
        const spotPrice = (quote.price as number) ?? 0;
        // A zero or negative spot cannot produce a meaningful chain. This used to
        // fall through to a default of 100.0, which invented a whole board of
        // strikes around a price the instrument never had.
        if (spotPrice > 0) {
          spotUsed = spotPrice;
          const change = (quote.change as number) ?? 0.0;
          const changePct = (quote.change_pct as number) ?? 0.0;
          const mockChain = generateMockFyersChainAndFutures(normalized, spotPrice, change, changePct, resolvedStrikeCount);
          if (mockChain) {
            chain = {
              ...mockChain,
              source: "black_scholes_estimate",
              is_estimate: true,
              estimate_note: "Premiums are model estimates at 25% implied volatility, not live exchange prices.",
            };
          }
        } else {
          providerErrors.spot = `no usable spot price for ${normalized}`;
        }
      } else {
        providerErrors.spot = `no quote for ${normalized}`;
      }
    } catch (err) {
      providerErrors.spot = String(err?.message ?? err);
      console.error("Spot lookup for estimated chain failed:", err);
    }

    if (!chain) {
      return json({
        error: `No option chain available for ${normalized}. This symbol may have no listed derivatives, or no spot price could be resolved for it.`,
        derivative_type: "options",
        source: "none",
        requested_symbol: symbol,
        resolved_underlying: normalized,
        spot: spotUsed,
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
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
