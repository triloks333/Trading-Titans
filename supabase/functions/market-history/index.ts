import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { fetchHistory as yfHistory, CandleData } from "../_shared/yahoo.ts";
import { fetchHistory as cgHistory } from "../_shared/coingecko.ts";
import { fetchHistory as dcxHistory } from "../_shared/coindcx.ts";
import { COMMODITY_MARKET, US_MARKET, toUsYahooSymbol } from "../_shared/us_market.ts";
import {
  parseDerivativeSymbol,
  blackScholes,
  calculateFuturePrice,
  ParsedDerivative,
} from "../_shared/fo_pricing.ts";

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
    const isCrypto = market === "crypto" || ["BTC", "ETH", "SOL", "USDT", "DOGE", "XRP", "ADA", "BNB"].includes(symbol.toUpperCase().trim());
    const effectiveMarket = isCrypto ? "crypto" : market;
    const derivative = effectiveMarket === "stock" ? parseDerivativeSymbol(symbol) : null;

    if (effectiveMarket === "crypto") {
      // CoinDCX first: it serves real OHLC at the interval asked for, and it is the
      // venue the live price already comes from. CoinGecko ignores `interval`
      // entirely and picks granularity from the day count, which is why a 1m crypto
      // chart used to draw 30-minute bars.
      try {
        data = await dcxHistory(symbol, range, interval || undefined);
        if (!data.candles.length) throw new Error("CoinDCX returned no candles");
      } catch (dcxErr) {
        console.log(`[market-history] CoinDCX failed for ${symbol}, falling back to CG: ${dcxErr.message}`);
        data = await cgHistory(symbol, range, interval || undefined);
      }
    } else if (effectiveMarket === US_MARKET || effectiveMarket === COMMODITY_MARKET) {
      data = await yfHistory(symbol, range, interval || undefined, {
        yfSymbol: toUsYahooSymbol(symbol),
        strict,
      });
    } else if (effectiveMarket === "pakistan_stock") {
      const yfSymbol = symbol.toUpperCase().endsWith(".KA") ? symbol.toUpperCase() : `${symbol.toUpperCase()}.KA`;
      data = await yfHistory(symbol, range, interval || undefined, {
        yfSymbol,
        strict,
      });
    } else if (effectiveMarket === "italy_stock") {
      const yfSymbol = symbol.toUpperCase().endsWith(".MI") ? symbol.toUpperCase() : `${symbol.toUpperCase()}.MI`;
      data = await yfHistory(symbol, range, interval || undefined, {
        yfSymbol,
        strict,
      });
    } else if (derivative) {
      // Derivative contract (Option or Future): synthesize candle history from underlying index/stock
      const underlyingData = await yfHistory(derivative.underlying, range, interval || undefined, { strict });
      data = synthesizeDerivativeHistory(derivative, underlyingData);
    } else {
      data = await yfHistory(symbol, range, interval || undefined, { strict });
    }

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(`[market-history] Uncaught error: ${err.message}`);
    return new Response(JSON.stringify({ symbol: "", points: [], candles: [], error: err.message }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

function synthesizeDerivativeHistory(
  d: ParsedDerivative,
  underlyingData: { symbol: string; points: { t: number; v: number }[]; candles: CandleData[] }
) {
  const candles: CandleData[] = [];
  const points: { t: number; v: number }[] = [];

  let expiryMs = Date.now() + 30 * 24 * 60 * 60 * 1000;
  if (d.expiry) {
    const parsedExpiry = Date.parse(`${d.expiry}T15:30:00+05:30`);
    if (Number.isFinite(parsedExpiry)) {
      expiryMs = parsedExpiry;
    }
  }

  for (const c of underlyingData.candles) {
    const candleTime = c.t;
    const daysLeft = Math.max(0.0001, (expiryMs - candleTime) / (24 * 60 * 60 * 1000));
    const T = daysLeft / 365.0;

    let o = 0.05;
    let h = 0.05;
    let l = 0.05;
    let cl = 0.05;

    if (d.type === "OPTION" && d.strike && d.optionType) {
      if (d.optionType === "CE") {
        o = blackScholes(c.o, d.strike, T, "CE");
        h = blackScholes(c.h, d.strike, T, "CE");
        l = blackScholes(c.l, d.strike, T, "CE");
        cl = blackScholes(c.c, d.strike, T, "CE");
      } else {
        // For put options, price moves inversely with spot price
        o = blackScholes(c.o, d.strike, T, "PE");
        h = blackScholes(c.l, d.strike, T, "PE");
        l = blackScholes(c.h, d.strike, T, "PE");
        cl = blackScholes(c.c, d.strike, T, "PE");
      }
    } else if (d.type === "FUTURE") {
      o = calculateFuturePrice(c.o, daysLeft);
      h = calculateFuturePrice(c.h, daysLeft);
      l = calculateFuturePrice(c.l, daysLeft);
      cl = calculateFuturePrice(c.c, daysLeft);
    }

    const finalHigh = Math.round(Math.max(h, o, cl) * 100) / 100;
    const finalLow = Math.max(0.05, Math.round(Math.min(l, o, cl) * 100) / 100);
    const finalOpen = Math.round(o * 100) / 100;
    const finalClose = Math.round(cl * 100) / 100;

    candles.push({
      t: candleTime,
      o: finalOpen,
      h: finalHigh,
      l: finalLow,
      c: finalClose,
    });
    points.push({
      t: candleTime,
      v: finalClose,
    });
  }

  return {
    symbol: d.symbol,
    points,
    candles,
  };
}
