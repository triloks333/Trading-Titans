import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  COMMODITY_MARKET,
  US_MARKET,
  commodityDisplayName,
  commodityUnitDivisor,
  fromUsYahooSymbol,
  getUsdInrRate,
  getPkrInrRate,
  getEurInrRate,
  toUsYahooSymbol,
} from "../_shared/us_market.ts";
import {
  parseDerivativeSymbol,
  blackScholes,
  calculateFuturePrice,
  getDaysToExpiry,
  ParsedDerivative,
} from "../_shared/fo_pricing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const YAHOO_QUOTE = "https://query1.finance.yahoo.com/v7/finance/quote";
const COINGECKO_BASE = "https://api.coingecko.com/api/v3";
const COINDCX_TICKER = "https://api.coindcx.com/exchange/ticker";
const BINANCE_TICKER = "https://api.binance.com/api/v3/ticker/24hr";
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

const STOCK_NAMES: Record<string, string> = {
  RELIANCE: "Reliance Industries",
  TCS: "Tata Consultancy Services",
  HDFCBANK: "HDFC Bank",
  INFY: "Infosys",
  ICICIBANK: "ICICI Bank",
  TMCV: "Tata Motors (Commercial)",
  TMPV: "Tata Motors (Passenger)",
  ADANIENT: "Adani Enterprises",
  ETERNAL: "Eternal (Zomato)",
  ZOMATO: "Eternal (Zomato)",
};

const CRYPTO_IDS: Record<string, string> = {
  BTC: "bitcoin",
  ETH: "ethereum",
  SOL: "solana",
  ADA: "cardano",
  XRP: "ripple",
  DOGE: "dogecoin",
  BNB: "binancecoin",
  DOT: "polkadot",
  AVAX: "avalanche-2",
  POL: "polygon-ecosystem-token",
  LTC: "litecoin",
  LINK: "chainlink",
  UNI: "uniswap",
  ATOM: "cosmos",
  TRX: "tron",
  NEAR: "near-protocol",
  APT: "aptos",
};

type Quote = {
  symbol: string;
  yf_symbol: string;
  name: string;
  price: number;
  previous_close: number;
  change: number;
  change_pct: number;
  currency: string;
  market: string;
  source: string;
  display_name?: string;
  category?: string;
  day_low?: number;
  day_high?: number;
  open?: number;
  volume?: number;
  /// USD -> INR rate, present only on non-INR quotes. Lets the order screen show
  /// the rupee amount that will actually leave the wallet.
  fx_rate?: number;
};

serve(async (req) => {
  const __start = Date.now();
  let __status = 200;
  try {
    const __res = await handleRequest(req);
    __status = __res.status;
    return __res;
  } finally {
    // Timing instrumentation (no behavior change): surfaces slow requests in
    // the function logs so we can spot the slowest endpoints.
    console.log(`[market-quote] ${req.method} ${Date.now() - __start}ms status=${__status}`);
  }
});

async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const rawSymbol = url.searchParams.get("symbol") ?? "";
    const market = (url.searchParams.get("market") ?? "stock").toLowerCase();

    // FX needs no symbol — there is only one pair — so answer before the
    // symbol guard below.
    if (market === "fx") {
      const symUpper = (rawSymbol || "").toUpperCase();
      let rate = 0;
      let sym = "USDINR";
      let yfSym = "USDINR=X";
      let name = "US Dollar / Indian Rupee";

      if (symUpper.includes("EUR")) {
        rate = await getEurInrRate();
        sym = "EURINR";
        yfSym = "EURINR=X";
        name = "Euro / Indian Rupee";
      } else if (symUpper.includes("PKR")) {
        rate = await getPkrInrRate();
        sym = "PKRINR";
        yfSym = "PKRINR=X";
        name = "Pakistani Rupee / Indian Rupee";
      } else {
        rate = await getUsdInrRate();
      }

      return json({
        symbol: sym,
        yf_symbol: yfSym,
        name: name,
        price: round(rate, 4),
        previous_close: round(rate, 4),
        change: 0,
        change_pct: 0,
        currency: "INR",
        market: "fx",
        source: "yahoo",
        fx_rate: round(rate, 4),
      });
    }

    if (!rawSymbol.trim()) {
      return json({ error: "symbol required" }, 400);
    }

    const symbol = normalizeSymbol(rawSymbol, market);
    const errors: Record<string, string> = {};
    let quote: Quote | null = null;

    const derivative = market === "stock" ? (parseDerivativeSymbol(rawSymbol) ?? parseDerivativeSymbol(symbol)) : null;

    if (market === "crypto") {
      quote = await attempt(() => fetchCoinDcxQuote(symbol), errors, "coindcx");
      quote ??= await attempt(() => fetchBinanceQuote(symbol), errors, "binance");
      quote ??= await attempt(() => fetchCoinGeckoQuote(symbol), errors, "coingecko");
    } else if (market === US_MARKET) {
      quote = await attempt(() => fetchUsStockQuote(symbol), errors, "yahoo");
    } else if (market === COMMODITY_MARKET) {
      // Yahoo continuous futures (GC=F, SI=F) are quoted per troy ounce (31.1035g) on COMEX;
      // scale Gold and Silver to per-1-gram so Indian prices match the 1g retail/bullion rate.
      const divisor = commodityUnitDivisor(symbol);
      const q = await attempt(() => fetchUsStockQuote(symbol, divisor), errors, "yahoo");
      const cleanName = commodityDisplayName(symbol);
      quote = q && {
        ...q,
        name: cleanName ?? q.name,
        display_name: cleanName ?? q.display_name,
        market: COMMODITY_MARKET,
      };
    } else if (market === "pakistan_stock") {
      quote = await attempt(() => fetchPakistanStockQuote(symbol), errors, "yahoo");
    } else if (market === "italy_stock") {
      quote = await attempt(() => fetchItalyStockQuote(symbol), errors, "yahoo");
    } else if (derivative) {
      quote = await attempt(() => fetchDerivativeQuote(derivative, rawSymbol), errors, "synthetic_fo");
    } else {
      quote = await attempt(() => fetchYahooStockQuote(symbol), errors, "yahoo");
    }

    if (!quote || quote.price <= 0) {
      console.error(`Quote failed for ${rawSymbol} (${symbol}). Provider errors:`, errors);
      return json(
        { error: "No data for symbol", tried_providers: Object.keys(errors), details: errors },
        404,
      );
    }

    return json(quote);
  } catch (err) {
    console.error("market-quote fatal error:", err);
    return json({ error: errorMessage(err) }, 500);
  }
}

async function attempt<T>(
  fn: () => Promise<T | null>,
  errors: Record<string, string>,
  provider: string,
): Promise<T | null> {
  try {
    return await fn();
  } catch (err) {
    errors[provider] = errorMessage(err);
    return null;
  }
}

async function fetchCachedStockQuote(symbol: string): Promise<Quote | null> {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnonKey) return null;
    const cleanSym = symbol.replace(/^\^/, "").replace(/\.(NS|BO)$/i, "");
    const res = await fetch(
      `${supabaseUrl}/rest/v1/quotes_cache?symbol=eq.${encodeURIComponent(cleanSym)}&market=eq.stock&limit=1`,
      {
        headers: {
          apikey: supabaseAnonKey,
          Authorization: `Bearer ${supabaseAnonKey}`,
        },
      }
    );
    if (!res.ok) return null;
    const rows = await res.json();
    if (!Array.isArray(rows) || rows.length === 0) return null;
    const r = rows[0];
    const price = Number(r.price ?? 0);
    if (price <= 0) return null;
    return {
      symbol: cleanSym,
      yf_symbol: `${cleanSym}.NS`,
      name: r.name ?? cleanSym,
      price: round(price, 2),
      previous_close: round(Number(r.previous_close ?? price), 2),
      change: round(Number(r.change ?? 0), 2),
      change_pct: round(Number(r.change_pct ?? 0), 2),
      currency: "INR",
      market: "stock",
      source: "quotes_cache",
    };
  } catch {
    return null;
  }
}

async function fetchDerivativeQuote(d: ParsedDerivative, originalSymbol: string): Promise<Quote> {
  let spotQuote: Quote | null = null;
  try {
    spotQuote = await fetchYahooStockQuote(d.underlying);
  } catch (err) {
    spotQuote = await fetchCachedStockQuote(d.underlying);
    if (!spotQuote) throw err;
  }
  const spotPrice = spotQuote.price;
  const spotPrevClose = spotQuote.previous_close || spotPrice;

  if (d.type === "OPTION" && d.strike && d.optionType && d.expiry) {
    const daysLeft = getDaysToExpiry(d.expiry);
    const T = daysLeft / 365.0;
    const T_prev = (daysLeft + 1.0) / 365.0;

    const price = blackScholes(spotPrice, d.strike, T, d.optionType);
    const prevClose = blackScholes(spotPrevClose, d.strike, T_prev, d.optionType);
    const change = round(price - prevClose, 2);
    const changePct = prevClose > 0 ? round((change / prevClose) * 100, 2) : 0;

    let dayHigh = price;
    let dayLow = price;
    if (spotQuote.day_high && spotQuote.day_low) {
      if (d.optionType === "CE") {
        dayHigh = blackScholes(spotQuote.day_high, d.strike, T, "CE");
        dayLow = blackScholes(spotQuote.day_low, d.strike, T, "CE");
      } else {
        dayHigh = blackScholes(spotQuote.day_low, d.strike, T, "PE");
        dayLow = blackScholes(spotQuote.day_high, d.strike, T, "PE");
      }
    }

    const cleanUnderlying = d.underlying.replace(/^\^/, "");
    const cleanName = `${cleanUnderlying} ${d.expiry} ${d.strike} ${d.optionType}`;

    return {
      symbol: originalSymbol,
      yf_symbol: originalSymbol,
      name: cleanName,
      price: round(price, 2),
      previous_close: round(prevClose, 2),
      change: round(change, 2),
      change_pct: round(changePct, 2),
      currency: "INR",
      market: "stock",
      source: "synthetic_fo",
      day_low: optionalRound(dayLow, 2),
      day_high: optionalRound(dayHigh, 2),
      open: optionalRound(prevClose, 2),
      volume: 25000,
    };
  } else if (d.type === "FUTURE") {
    const daysLeft = d.expiry ? getDaysToExpiry(d.expiry) : 30;
    const price = calculateFuturePrice(spotPrice, daysLeft);
    const prevClose = calculateFuturePrice(spotPrevClose, daysLeft + 1);
    const change = round(price - prevClose, 2);
    const changePct = prevClose > 0 ? round((change / prevClose) * 100, 2) : 0;

    const cleanUnderlying = d.underlying.replace(/^\^/, "");
    const cleanName = `${cleanUnderlying} ${d.month ?? "FUT"} FUTURES`;

    return {
      symbol: originalSymbol,
      yf_symbol: originalSymbol,
      name: cleanName,
      price: round(price, 2),
      previous_close: round(prevClose, 2),
      change: round(change, 2),
      change_pct: round(changePct, 2),
      currency: "INR",
      market: "stock",
      source: "synthetic_fo",
      day_low: optionalRound(price * 0.985, 2),
      day_high: optionalRound(price * 1.015, 2),
      open: optionalRound(prevClose, 2),
      volume: 50000,
    };
  }

  throw new Error(`Unsupported derivative: ${originalSymbol}`);
}

/**
 * US equity quote, priced natively in USD.
 *
 * Deliberately does NOT convert to INR: the app shows US prices in dollars, and
 * the order engine does the single USD -> INR conversion at fill time so the
 * stored FX rate belongs to the trade rather than to a quote refresh.
 */
async function fetchUsStockQuote(symbol: string, unitDivisor = 1): Promise<Quote> {
  const yfSymbol = toUsYahooSymbol(symbol);
  const chartUrl = `${YAHOO_CHART}/${encodeURIComponent(yfSymbol)}?range=2d&interval=1d`;
  const chartRes = await fetch(chartUrl, { headers: { "User-Agent": USER_AGENT } });
  if (!chartRes.ok) throw new Error(`Yahoo chart ${chartRes.status} for ${yfSymbol}`);
  const chart = await chartRes.json();
  const result = chart?.chart?.result?.[0];
  const meta = result?.meta;
  if (!meta) throw new Error(`No chart meta for ${yfSymbol}`);

  const rawPrice = Number(meta.regularMarketPrice ?? 0);
  if (!(rawPrice > 0)) throw new Error(`No price for ${yfSymbol}`);
  const rawPrevClose = Number(meta.chartPreviousClose ?? meta.previousClose ?? rawPrice);
  const price = rawPrice / unitDivisor;
  const previousClose = rawPrevClose / unitDivisor;
  const change = price - previousClose;
  const decimals = unitDivisor > 1 ? 4 : 2;

  const summary = await fetchYahooSummary(yfSymbol);
  const storedSymbol = fromUsYahooSymbol(yfSymbol);
  const rawDayLow = number(summary.dayLow ?? meta.regularMarketDayLow);
  const rawDayHigh = number(summary.dayHigh ?? meta.regularMarketDayHigh);
  const rawOpen = number(summary.open ?? meta.regularMarketOpen);

  return {
    symbol: storedSymbol,
    yf_symbol: yfSymbol,
    name: (summary.name as string | undefined) ?? meta.shortName ?? storedSymbol,
    price: round(price, decimals),
    previous_close: round(previousClose, decimals),
    change: round(change, decimals),
    change_pct: round(rawPrevClose ? ((rawPrice - rawPrevClose) / rawPrevClose) * 100 : 0, 2),
    // Native currency. The app formats us_stock with "$" on the strength of this.
    currency: "USD",
    market: US_MARKET,
    source: "yahoo",
    day_low: rawDayLow > 0 ? round(rawDayLow / unitDivisor, decimals) : undefined,
    day_high: rawDayHigh > 0 ? round(rawDayHigh / unitDivisor, decimals) : undefined,
    open: rawOpen > 0 ? round(rawOpen / unitDivisor, decimals) : undefined,
    volume: optionalInt(summary.volume ?? meta.regularMarketVolume),
    // Indicative only. The binding rate is the one the engine records at fill.
    fx_rate: round(await getUsdInrRate(), 4),
  };
}

async function fetchPakistanStockQuote(symbol: string): Promise<Quote> {
  const yfSymbol = symbol.toUpperCase().endsWith(".KA") ? symbol.toUpperCase() : `${symbol.toUpperCase()}.KA`;
  const chartUrl = `${YAHOO_CHART}/${encodeURIComponent(yfSymbol)}?range=2d&interval=1d`;
  const chartRes = await fetch(chartUrl, { headers: { "User-Agent": USER_AGENT } });
  if (!chartRes.ok) throw new Error(`Yahoo chart ${chartRes.status} for ${yfSymbol}`);
  const chart = await chartRes.json();
  const result = chart?.chart?.result?.[0];
  const meta = result?.meta;
  if (!meta) throw new Error(`No chart meta for ${yfSymbol}`);

  const price = Number(meta.regularMarketPrice ?? 0);
  if (!(price > 0)) throw new Error(`No price for ${yfSymbol}`);
  const previousClose = Number(meta.chartPreviousClose ?? meta.previousClose ?? price);
  const change = price - previousClose;
  const cleanSymbol = symbol.toUpperCase().replace(/\.KA$/i, "");

  return {
    symbol: cleanSymbol,
    yf_symbol: yfSymbol,
    name: (meta.shortName as string | undefined) ?? meta.longName ?? cleanSymbol,
    price: round(price, 2),
    previous_close: round(previousClose, 2),
    change: round(change, 2),
    change_pct: round(previousClose ? (change / previousClose) * 100 : 0, 2),
    currency: "PKR",
    market: "pakistan_stock",
    source: "yahoo",
    day_low: optionalRound(meta.regularMarketDayLow, 2),
    day_high: optionalRound(meta.regularMarketDayHigh, 2),
    open: optionalRound(meta.regularMarketOpen, 2),
    volume: optionalInt(meta.regularMarketVolume),
    fx_rate: 0.342,
  };
}

async function fetchItalyStockQuote(symbol: string): Promise<Quote> {
  const yfSymbol = symbol.toUpperCase().endsWith(".MI") ? symbol.toUpperCase() : `${symbol.toUpperCase()}.MI`;
  const chartUrl = `${YAHOO_CHART}/${encodeURIComponent(yfSymbol)}?range=2d&interval=1d`;
  const chartRes = await fetch(chartUrl, { headers: { "User-Agent": USER_AGENT } });
  if (!chartRes.ok) throw new Error(`Yahoo chart ${chartRes.status} for ${yfSymbol}`);
  const chart = await chartRes.json();
  const result = chart?.chart?.result?.[0];
  const meta = result?.meta;
  if (!meta) throw new Error(`No chart meta for ${yfSymbol}`);

  const price = Number(meta.regularMarketPrice ?? 0);
  if (!(price > 0)) throw new Error(`No price for ${yfSymbol}`);
  const previousClose = Number(meta.chartPreviousClose ?? meta.previousClose ?? price);
  const change = price - previousClose;
  const cleanSymbol = symbol.toUpperCase().replace(/\.MI$/i, "");

  return {
    symbol: cleanSymbol,
    yf_symbol: yfSymbol,
    name: (meta.shortName as string | undefined) ?? meta.longName ?? cleanSymbol,
    price: round(price, 2),
    previous_close: round(previousClose, 2),
    change: round(change, 2),
    change_pct: round(previousClose ? (change / previousClose) * 100 : 0, 2),
    currency: "EUR",
    market: "italy_stock",
    source: "yahoo",
    day_low: optionalRound(meta.regularMarketDayLow, 2),
    day_high: optionalRound(meta.regularMarketDayHigh, 2),
    open: optionalRound(meta.regularMarketOpen, 2),
    volume: optionalInt(meta.regularMarketVolume),
    fx_rate: 106.34,
  };
}

function normalizeSymbol(symbol: string, market: string): string {
  let s = symbol.toUpperCase().trim();
  if (market === US_MARKET) {
    return fromUsYahooSymbol(s);
  }
  if (market === "stock") {
    const colonIndex = s.indexOf(":");
    if (colonIndex !== -1) s = s.substring(colonIndex + 1);
    s = s.replace(/\.(NS|BO)$/i, "");
    s = s.replace(/-(EQ|SM|BE|BZ)$/i, "");
    
    // Do not split by space/hyphen if it's an F&O instrument
    const isFO = s.includes("FUT") || s.includes("CE") || s.includes("PE") || /\d{2}[A-Z]{3}/.test(s);
    if (!s.startsWith("^") && !isFO) {
      s = s.split("-")[0].split(" ")[0];
    }
    if (s === "ZOMATO") s = "ETERNAL";
  } else {
    s = s.replace(/(USDT|INR)$/i, "");
    // Polygon rebranded MATIC -> POL. CoinDCX dropped MATICINR entirely, so a
    // MATIC lookup used to fall through to Binance's stale MATICUSDT and serve a
    // price ~5x the real token (₹36 against POL's ₹7.46). Alias here so all three
    // providers see POL, the same way ZOMATO -> ETERNAL is handled above.
    if (s === "MATIC") s = "POL";
  }
  return s;
}

function toYahooSymbol(symbol: string): string {
  if (symbol === "^NSEI" || symbol === "NIFTY" || symbol === "NIFTY50") return "^NSEI";
  if (symbol === "^NSEBANK" || symbol === "BANKNIFTY") return "^NSEBANK";
  if (symbol === "^BSESN" || symbol === "SENSEX") return "^BSESN";
  if (symbol.endsWith(".NS") || symbol.endsWith(".BO") || symbol.startsWith("^")) return symbol;
  return `${symbol}.NS`;
}

async function fetchYahooStockQuote(symbol: string): Promise<Quote> {
  const yfSymbol = toYahooSymbol(symbol);
  const chartUrl = `${YAHOO_CHART}/${encodeURIComponent(yfSymbol)}?range=2d&interval=1d`;
  const chartRes = await fetch(chartUrl, { headers: { "User-Agent": USER_AGENT } });
  if (!chartRes.ok) throw new Error(`Yahoo chart failed: ${chartRes.status}`);

  const chartJson = await chartRes.json();
  const result = chartJson?.chart?.result?.[0];
  if (!result) throw new Error(`No Yahoo chart result for ${yfSymbol}`);

  const meta = result.meta ?? {};
  const quoteRows = result.indicators?.quote?.[0] ?? {};
  const closes: unknown[] = quoteRows.close ?? [];
  const price = number(meta.regularMarketPrice ?? closes[closes.length - 1]);
  const previousClose = number(meta.chartPreviousClose ?? meta.previousClose ?? closes[closes.length - 2] ?? price);
  if (price <= 0) throw new Error(`Yahoo price unavailable for ${yfSymbol}`);

  const quoteSummary = await fetchYahooSummary(yfSymbol);
  const rawSymbol = yfSymbol.replace(".NS", "").replace(".BO", "");
  const change = price - previousClose;

  return {
    symbol: rawSymbol,
    yf_symbol: yfSymbol,
    name: STOCK_NAMES[rawSymbol] ?? quoteSummary.name ?? rawSymbol,
    price: round(price, 2),
    previous_close: round(previousClose || price, 2),
    change: round(change, 2),
    change_pct: round(previousClose ? (change / previousClose) * 100 : 0, 2),
    currency: "INR",
    market: "stock",
    source: "yahoo",
    display_name: displayName(yfSymbol),
    category: yfSymbol.startsWith("^") ? "index" : "stock",
    day_low: optionalRound(quoteSummary.dayLow ?? meta.regularMarketDayLow, 2),
    day_high: optionalRound(quoteSummary.dayHigh ?? meta.regularMarketDayHigh, 2),
    open: optionalRound(quoteSummary.open ?? meta.regularMarketOpen, 2),
    volume: optionalInt(quoteSummary.volume ?? meta.regularMarketVolume),
  };
}

async function fetchYahooSummary(yfSymbol: string): Promise<Record<string, unknown>> {
  try {
    const res = await fetch(`${YAHOO_QUOTE}?symbols=${encodeURIComponent(yfSymbol)}`, {
      headers: { "User-Agent": USER_AGENT },
    });
    if (!res.ok) return {};
    const json = await res.json();
    const q = json?.quoteResponse?.result?.[0];
    if (!q) return {};
    return {
      name: q.longName ?? q.shortName,
      dayLow: q.regularMarketDayLow,
      dayHigh: q.regularMarketDayHigh,
      open: q.regularMarketOpen,
      volume: q.regularMarketVolume,
    };
  } catch {
    return {};
  }
}

async function fetchCoinDcxQuote(symbol: string): Promise<Quote | null> {
  const res = await fetch(COINDCX_TICKER, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`CoinDCX ticker failed: ${res.status}`);
  const tickers = await res.json();
  if (!Array.isArray(tickers)) return null;

  const ticker = tickers.find((item) => item?.market === `${symbol}INR`);
  if (!ticker) return null;

  const price = number(ticker.last_price);
  if (price <= 0) return null;
  const changePct = number(ticker.change_24_hour);
  const previousClose = changePct ? price / (1 + changePct / 100) : price;

  return {
    symbol,
    yf_symbol: `${symbol}INR`,
    name: cryptoName(symbol),
    price: round(price, 2),
    previous_close: round(previousClose, 2),
    change: round(price - previousClose, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "crypto",
    source: "coindcx",
    display_name: cryptoName(symbol),
    category: "crypto",
    day_low: optionalRound(ticker.low, 2),
    day_high: optionalRound(ticker.high, 2),
    volume: optionalInt(ticker.volume),
  };
}

async function fetchBinanceQuote(symbol: string): Promise<Quote> {
  const binanceSymbol = `${symbol}USDT`;
  const res = await fetch(`${BINANCE_TICKER}?symbol=${encodeURIComponent(binanceSymbol)}`, {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`Binance quote failed: ${res.status}`);

  const data = await res.json();
  const usdToInr = await fetchUsdInrRate();
  const price = number(data.lastPrice) * usdToInr;
  const changePct = number(data.priceChangePercent);
  const previousClose = changePct ? price / (1 + changePct / 100) : price;

  return {
    symbol,
    yf_symbol: binanceSymbol,
    name: cryptoName(symbol),
    price: round(price, 2),
    previous_close: round(previousClose, 2),
    change: round(price - previousClose, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "crypto",
    source: "binance",
    display_name: cryptoName(symbol),
    category: "crypto",
    day_low: optionalRound(number(data.lowPrice) * usdToInr, 2),
    day_high: optionalRound(number(data.highPrice) * usdToInr, 2),
    open: optionalRound(number(data.openPrice) * usdToInr, 2),
    volume: optionalInt(data.volume),
  };
}

async function fetchCoinGeckoQuote(symbol: string): Promise<Quote> {
  const id = CRYPTO_IDS[symbol];
  if (!id) throw new Error(`Unknown CoinGecko symbol: ${symbol}`);

  const url = `${COINGECKO_BASE}/simple/price?ids=${encodeURIComponent(id)}&vs_currencies=inr&include_24hr_change=true`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`CoinGecko quote failed: ${res.status}`);

  const data = (await res.json())?.[id];
  if (!data) throw new Error(`No CoinGecko data for ${id}`);
  const price = number(data.inr);
  const changePct = number(data.inr_24h_change);
  const previousClose = changePct ? price / (1 + changePct / 100) : price;

  return {
    symbol,
    yf_symbol: id,
    name: cryptoName(symbol, id),
    price: round(price, 2),
    previous_close: round(previousClose, 2),
    change: round(price - previousClose, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "crypto",
    source: "coingecko",
    display_name: cryptoName(symbol, id),
    category: "crypto",
  };
}

async function fetchUsdInrRate(): Promise<number> {
  try {
    const chartUrl = `${YAHOO_CHART}/USDINR=X?range=2d&interval=1d`;
    const res = await fetch(chartUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) throw new Error(`Yahoo FX failed: ${res.status}`);
    const result = (await res.json())?.chart?.result?.[0];
    const closes: unknown[] = result?.indicators?.quote?.[0]?.close ?? [];
    const rate = number(result?.meta?.regularMarketPrice ?? closes[closes.length - 1]);
    if (rate > 0) return rate;
  } catch {
    // Fall back to a conservative recent rate if Yahoo FX is temporarily unavailable.
  }
  return 83.5;
}

function displayName(yfSymbol: string): string {
  const names: Record<string, string> = {
    "^NSEI": "NIFTY 50",
    "^NSEBANK": "BANK NIFTY",
    "^BSESN": "SENSEX",
  };
  return names[yfSymbol] ?? yfSymbol.replace(".NS", "").replace(".BO", "");
}

function cryptoName(symbol: string, fallbackId = ""): string {
  const names: Record<string, string> = {
    BTC: "Bitcoin",
    ETH: "Ethereum",
    SOL: "Solana",
    ADA: "Cardano",
    XRP: "XRP",
    DOGE: "Dogecoin",
    BNB: "BNB",
    DOT: "Polkadot",
    AVAX: "Avalanche",
    POL: "Polygon",
    LTC: "Litecoin",
    LINK: "Chainlink",
  };
  return names[symbol] ?? fallbackId.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()) ?? symbol;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function number(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function round(n: number, decimals: number): number {
  const m = 10 ** decimals;
  return Math.round(n * m) / m;
}

function optionalRound(value: unknown, decimals: number): number | undefined {
  const n = number(value);
  return n > 0 ? round(n, decimals) : undefined;
}

function optionalInt(value: unknown): number | undefined {
  const n = number(value);
  return n > 0 ? Math.round(n) : undefined;
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  try {
    return JSON.stringify(err);
  } catch {
    return "Unknown error";
  }
}
