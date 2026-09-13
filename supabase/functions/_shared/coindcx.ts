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

// ─── History ────────────────────────────────────────────────────────────────
//
// WHY CRYPTO HISTORY MOVED HERE FROM COINGECKO
// `coingecko.ts`'s fetchHistory takes an `interval` argument and never reads it.
// It maps the range to a day count, calls /ohlc, then downsamples to a fixed 120
// candles — so a "1m" chart drew 30-minute bars and a "5m" chart drew 4-hourly
// ones. That is what users reported as the timeframes not working, and it was not
// fixable at the call site because CoinGecko's public endpoint chooses granularity
// from the day count and ignores anything we ask for.
//
// CoinDCX serves real OHLC at a named interval, and it is already the venue
// `fetchQuote` above reads the live price from (`<SYM>INR` on /exchange/ticker).
// So this also closes a seam: until now the body of a crypto chart was CoinGecko
// and its right-hand edge was CoinDCX, two venues about 12% apart on Indian
// crypto. Verified at the time of writing — I-BTC_INR closed at ₹7,895,150 while
// quotes_cache held ₹7,895,446, 0.004% apart.

/** The only intervals the public candles endpoint accepts. Verified: anything
 *  else returns `422 interval must be one of [1m, 15m, 1h, 1d]`. */
const NATIVE_CANDLE_INTERVALS = ["1m", "15m", "1h", "1d"] as const;

const INTERVAL_SECONDS: Record<string, number> = {
  "1m": 60,
  "5m": 300,
  "10m": 600,
  "15m": 900,
  "30m": 1800,
  "1h": 3600,
  "1d": 86400,
  "1w": 604800,
};

/**
 * The native interval to fetch in order to build [want], and how many of them go
 * into one output bar.
 *
 * Picks the coarsest native interval that divides [want] exactly, so a 30-minute
 * bar is built from two 15-minute bars rather than thirty 1-minute ones — fewer
 * bars fetched for the same result, and it keeps more history inside the request
 * limit.
 */
function sourceFor(want: string): { native: string; factor: number } {
  const target = INTERVAL_SECONDS[want] ?? INTERVAL_SECONDS["1d"];
  let best = { native: "1m", factor: target / 60 };
  for (const native of NATIVE_CANDLE_INTERVALS) {
    const secs = INTERVAL_SECONDS[native];
    if (secs <= target && target % secs === 0) best = { native, factor: target / secs };
  }
  return best;
}

/** Rolls finer bars into coarser ones: first open, last close, extremes of all. */
function rollUp(bars: CandleData[], factor: number, toSeconds: number): CandleData[] {
  if (factor <= 1) return bars;
  const out: CandleData[] = [];
  const bucketMs = toSeconds * 1000;
  for (const b of bars) {
    const start = Math.floor(b.t / bucketMs) * bucketMs;
    const last = out[out.length - 1];
    if (last && last.t === start) {
      if (b.h > last.h) last.h = b.h;
      if (b.l < last.l) last.l = b.l;
      last.c = b.c;
    } else {
      out.push({ t: start, o: b.o, h: b.h, l: b.l, c: b.c });
    }
  }
  return out;
}

/** Hard ceiling the endpoint honours. 1000 verified; larger is not served. */
const MAX_LIMIT = 1000;

/** Span of each `range` the chart sends, in seconds. */
const RANGE_SECONDS: Record<string, number> = {
  "1d": 86400,
  "5d": 5 * 86400,
  "10d": 10 * 86400,
  "1mo": 30 * 86400,
  "3mo": 90 * 86400,
  "6mo": 180 * 86400,
  "1y": 365 * 86400,
  "5y": 5 * 365 * 86400,
};

export async function fetchHistory(
  sym: string,
  range: string,
  interval?: string,
): Promise<{ symbol: string; points: { t: number; v: number }[]; candles: CandleData[] }> {
  const clean = sym.toUpperCase().trim();
  const want = interval && INTERVAL_SECONDS[interval] ? interval : "1d";
  const { native, factor } = sourceFor(want);

  // Honour `range` as well as `interval`, capped at ~400 output bars.
  //
  // Not just cosmetic. Clients already in the field ask crypto for `1d` bars at
  // both `3mo` and `1y`; ignoring range would answer both with the same 400 daily
  // bars, so two buttons would draw the same chart — which is the very complaint
  // this change set out to fix. Crypto trades 24/7, so a span holds far more bars
  // than the same span on an exchange with a session.
  const spanSeconds = RANGE_SECONDS[range] ?? RANGE_SECONDS["1y"];
  const barsWanted = Math.max(2, Math.ceil(spanSeconds / INTERVAL_SECONDS[want]));
  const limit = Math.min(MAX_LIMIT, Math.min(400, barsWanted) * factor);

  // The INR market, not the USDT perpetual. `B-BTC_USDT` prices in dollars and sits
  // ~12% away from the rupee price we quote, which is exactly the mismatch the old
  // TradingView chart had between its candles and our header.
  const pair = `I-${clean}_INR`;
  const url =
    `https://public.coindcx.com/market_data/candles` +
    `?pair=${encodeURIComponent(pair)}&interval=${native}&limit=${limit}`;

  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`CoinDCX candles failed: ${res.status}`);

  const raw = await res.json();
  if (!Array.isArray(raw)) {
    // A 422 body arrives as an object, so an unexpected shape is a real failure
    // rather than an empty market. Throwing lets market-history fall back.
    throw new Error(`CoinDCX candles unexpected: ${JSON.stringify(raw).slice(0, 120)}`);
  }

  // Newest-first from the API; the chart wants oldest-first.
  const bars: CandleData[] = raw
    .map((c: Record<string, number>) => ({
      t: Number(c.time),
      o: Number(c.open),
      h: Number(c.high),
      l: Number(c.low),
      c: Number(c.close),
    }))
    .filter((c: CandleData) =>
      Number.isFinite(c.t) && [c.o, c.h, c.l, c.c].every((n) => Number.isFinite(n) && n > 0)
    )
    .sort((a: CandleData, b: CandleData) => a.t - b.t);

  const candles = rollUp(bars, factor, INTERVAL_SECONDS[want]);
  return {
    symbol: clean,
    points: candles.map((c) => ({ t: c.t, v: c.c })),
    candles,
  };
}

export interface CandleData {
  t: number;
  o: number;
  h: number;
  l: number;
  c: number;
}
