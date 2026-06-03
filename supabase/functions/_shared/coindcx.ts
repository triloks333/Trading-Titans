const COINDCX_BASE = "https://api.coindcx.com";

interface CoinDcxConfig {
  apiKey: string;
  secretKey: string;
}

function getConfig(): CoinDcxConfig {
  return {
    apiKey: Deno.env.get("COINDCX_API_KEY") ?? "",
    secretKey: Deno.env.get("COINDCX_SECRET_KEY") ?? "",
  };
}

let _cachedTickers: any[] = [];
let _lastUpdate = 0;
let _cachedFuturesPrices: any | null = null;
let _futuresPricesUpdate = 0;
let _cachedActiveFutures: Record<string, string[]> = {};
let _activeFuturesUpdate: Record<string, number> = {};

async function fetchAllTickers(): Promise<any[]> {
  const now = Date.now();
  // Cache tickers for 3 seconds to avoid rate limits
  if (_cachedTickers.length > 0 && now - _lastUpdate < 3000) {
    return _cachedTickers;
  }

  const response = await fetch(`${COINDCX_BASE}/exchange/ticker`);
  if (!response.ok) {
    throw new Error(`CoinDCX ticker API failed: ${response.status}`);
  }

  const data = await response.json();
  if (Array.isArray(data)) {
    _cachedTickers = data;
    _lastUpdate = now;
  }
  return _cachedTickers;
}

export interface CoinDcxQuote {
  symbol: string;
  yf_symbol: string;
  name: string;
  price: number;
  previous_close: number;
  change: number;
  change_pct: number;
  currency: string;
  market: string;
  display_name?: string;
  category?: string;
  day_low?: number;
  day_high?: number;
  open?: number;
  volume?: number;
}

export async function fetchQuote(sym: string): Promise<CoinDcxQuote> {
  const cleanSym = sym.toUpperCase().trim();
  if (isFuturesPair(cleanSym)) {
    return await fetchFuturesQuote(cleanSym);
  }

  const coindcxMarket = `${cleanSym}INR`;

  const tickers = await fetchAllTickers();
  const ticker = tickers.find((t: any) => t.market === coindcxMarket);

  if (!ticker) {
    throw new Error(`CoinDCX symbol not found: ${coindcxMarket}`);
  }

  const price = Number(ticker.last_price) || 0;
  const changePct = Number(ticker.change_24_hour) || 0;
  const prev = changePct ? price / (1 + changePct / 100) : price;
  const change = price - prev;

  const displayName = cleanSym === "BTC" ? "Bitcoin" : cleanSym === "ETH" ? "Ethereum" : cleanSym;

  return {
    symbol: cleanSym,
    yf_symbol: coindcxMarket,
    name: displayName,
    price: round(price, 2),
    previous_close: round(prev, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "crypto",
    display_name: displayName,
    category: "crypto",
    day_low: ticker.low ? round(Number(ticker.low), 2) : undefined,
    day_high: ticker.high ? round(Number(ticker.high), 2) : undefined,
    volume: ticker.volume ? Number(ticker.volume) : undefined,
  };
}

export async function fetchFuturesQuote(pair: string): Promise<CoinDcxQuote> {
  const cleanPair = normalizeFuturesPair(pair);
  const prices = await fetchFuturesPrices();
  const ticker = prices[cleanPair];
  if (!ticker) {
    throw new Error(`CoinDCX futures symbol not found: ${cleanPair}`);
  }

  const price = Number(ticker.ls ?? ticker.last_price ?? ticker.price ?? 0);
  const changePct = Number(ticker.pc ?? ticker.change_24_hour ?? 0);
  const prev = changePct ? price / (1 + changePct / 100) : price;
  const change = price - prev;
  const underlying = futuresUnderlying(cleanPair);

  return {
    symbol: cleanPair,
    yf_symbol: cleanPair,
    name: `${underlying} Perpetual Futures`,
    price: round(price, 4),
    previous_close: round(prev, 4),
    change: round(change, 4),
    change_pct: round(changePct, 2),
    currency: "USDT",
    market: "crypto",
    display_name: `${underlying} Futures`,
    category: "crypto_futures",
    day_low: ticker.l ? round(Number(ticker.l), 4) : undefined,
    day_high: ticker.h ? round(Number(ticker.h), 4) : undefined,
    volume: ticker.v ? Number(ticker.v) : undefined,
  };
}

export async function fetchFuturesChain(sym: string): Promise<Record<string, unknown> | null> {
  const underlying = sym.toUpperCase().trim().replace(/INR$|USDT$/, "");
  const pairs = await fetchActiveFutures("USDT");
  const matching = pairs
    .filter((pair) => futuresUnderlying(pair) === underlying || futuresUnderlying(pair).replace(/^1000/, "") === underlying)
    .slice(0, 20);

  if (matching.length === 0) return null;

  const prices = await fetchFuturesPrices();
  const futures = matching.map((pair) => {
    const ticker = prices[pair] ?? {};
    const price = Number(ticker.ls ?? 0);
    const changePct = Number(ticker.pc ?? 0);
    const prev = changePct ? price / (1 + changePct / 100) : price;
    const change = price - prev;
    return {
      symbol: pair,
      provider_symbol: pair,
      underlying,
      instrument_type: "FUTURE",
      contract_type: "PERPETUAL",
      expiry_date: "PERPETUAL",
      settlement: "never",
      name: `${futuresUnderlying(pair)} Perpetual Futures`,
      price: round(price, 4),
      previous_close: round(prev, 4),
      change: round(change, 4),
      change_pct: round(changePct, 2),
      mark_price: ticker.mp != null ? round(Number(ticker.mp), 4) : undefined,
      funding_rate: ticker.fr != null ? Number(ticker.fr) : undefined,
      high: ticker.h != null ? round(Number(ticker.h), 4) : undefined,
      low: ticker.l != null ? round(Number(ticker.l), 4) : undefined,
      volume: ticker.v != null ? Number(ticker.v) : undefined,
      currency: "USDT",
      source: "coindcx",
    };
  });

  const first = futures[0];
  return {
    underlying,
    spot_price: first?.price ?? 0,
    change: first?.change ?? 0,
    change_pct: first?.change_pct ?? 0,
    expiries: ["PERPETUAL"],
    futures,
    derivative_type: "futures",
    source: "coindcx",
  };
}

async function fetchFuturesPrices(): Promise<Record<string, any>> {
  const now = Date.now();
  if (_cachedFuturesPrices && now - _futuresPricesUpdate < 3000) {
    return _cachedFuturesPrices;
  }
  const response = await fetch("https://public.coindcx.com/market_data/v3/current_prices/futures/rt");
  if (!response.ok) {
    throw new Error(`CoinDCX futures prices failed: ${response.status}`);
  }
  const data = await response.json();
  _cachedFuturesPrices = data?.prices ?? {};
  _futuresPricesUpdate = now;
  return _cachedFuturesPrices;
}

async function fetchActiveFutures(marginCurrency: "USDT" | "INR"): Promise<string[]> {
  const now = Date.now();
  const cached = _cachedActiveFutures[marginCurrency];
  if (cached && now - (_activeFuturesUpdate[marginCurrency] ?? 0) < 60 * 60 * 1000) {
    return cached;
  }
  const url = `${COINDCX_BASE}/exchange/v1/derivatives/futures/data/active_instruments?margin_currency_short_name[]=${marginCurrency}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`CoinDCX active futures failed: ${response.status}`);
  }
  const data = await response.json();
  _cachedActiveFutures[marginCurrency] = Array.isArray(data) ? data.map((x) => String(x).toUpperCase()) : [];
  _activeFuturesUpdate[marginCurrency] = now;
  return _cachedActiveFutures[marginCurrency];
}

function isFuturesPair(sym: string): boolean {
  return /^B-[A-Z0-9]+_[A-Z]+$/.test(sym) || sym.endsWith("-FUTURES");
}

function normalizeFuturesPair(sym: string): string {
  return sym.replace(/-FUTURES$/, "").toUpperCase();
}

function futuresUnderlying(pair: string): string {
  const match = normalizeFuturesPair(pair).match(/^B-([A-Z0-9]+)_/);
  return match?.[1] ?? pair;
}

function round(n: number, decimals: number): number {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}
