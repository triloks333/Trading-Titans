const YAHOO_BASE = "https://query1.finance.yahoo.com/v8/finance/chart";
const YAHOO_QUOTE = "https://query1.finance.yahoo.com/v7/finance/quote";
const YAHOO_SEARCH = "https://query1.finance.yahoo.com/v1/finance/search";
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

async function fetchJson(url: string): Promise<any> {
  const response = await fetch(url, { headers: { "User-Agent": UA } });
  if (!response.ok) {
    throw new Error(`Yahoo request failed: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

const CURATED_NAMES: Record<string, string> = {
  "RELIANCE": "Reliance Industries",
  "TCS": "Tata Consultancy Services",
  "HDFCBANK": "HDFC Bank",
  "INFY": "Infosys",
  "ICICIBANK": "ICICI Bank",
  "HINDUNILVR": "Hindustan Unilever",
  "ITC": "ITC Limited",
  "SBIN": "State Bank of India",
  "BHARTIARTL": "Bharti Airtel",
  "KOTAKBANK": "Kotak Mahindra Bank",
  "LT": "Larsen & Toubro",
  "AXISBANK": "Axis Bank",
  "ASIANPAINT": "Asian Paints",
  "MARUTI": "Maruti Suzuki",
  "BAJFINANCE": "Bajaj Finance",
  "WIPRO": "Wipro",
  "HCLTECH": "HCL Technologies",
  "ULTRACEMCO": "UltraTech Cement",
  "TITAN": "Titan Company",
  "SUNPHARMA": "Sun Pharmaceutical",
  "NESTLEIND": "Nestle India",
  "TATAMOTORS": "Tata Motors",
  "TMCV": "Tata Motors - Commercial",
  "TMPV": "Tata Motors - Passenger",
  "ADANIENT": "Adani Enterprises",
  "ADANIPORTS": "Adani Ports",
  "POWERGRID": "Power Grid Corporation",
  "NTPC": "NTPC",
  "ONGC": "Oil & Natural Gas Corp",
  "COALINDIA": "Coal India",
  "JSWSTEEL": "JSW Steel",
  "TATASTEEL": "Tata Steel",
  "M&M": "Mahindra & Mahindra",
  "BAJAJFINSV": "Bajaj Finserv",
  "INDUSINDBK": "IndusInd Bank",
  "TECHM": "Tech Mahindra",
  "DRREDDY": "Dr. Reddy's Labs",
  "CIPLA": "Cipla",
  "GRASIM": "Grasim Industries",
  "BRITANNIA": "Britannia Industries",
  "HEROMOTOCO": "Hero MotoCorp",
  "EICHERMOT": "Eicher Motors",
  "BAJAJ-AUTO": "Bajaj Auto",
  "DIVISLAB": "Divi's Laboratories",
  "HDFCLIFE": "HDFC Life Insurance",
  "SBILIFE": "SBI Life Insurance",
  "TATACONSUM": "Tata Consumer Products",
  "PIDILITIND": "Pidilite Industries",
  "DMART": "Avenue Supermarts",
  "ZOMATO": "Zomato",
  "PAYTM": "One97 Communications (Paytm)",
  "IRCTC": "IRCTC",
};

export function toYfSymbol(sym: string, market = "stock"): string {
  let s = sym.toUpperCase().trim();
  
  if (market === "crypto" || ["BTC", "ETH", "SOL", "USDT", "DOGE", "XRP", "ADA", "BNB"].includes(s)) {
    if (s.endsWith("-INR") || s.endsWith("-USD")) return s;
    return `${s}-INR`;
  }
  
  // Strip exchange prefix (e.g. NSE:FEDERALBNK-EQ -> FEDERALBNK-EQ)
  const colonIndex = s.indexOf(':');
  if (colonIndex !== -1) {
    s = s.substring(colonIndex + 1);
  }
  
  // Strip Fyers/broker specific suffixes (e.g. -EQ, -BE, -SM, -BZ) without destroying hyphenated tickers like BAJAJ-AUTO, NAM-INDIA
  if (!s.startsWith("^")) {
    s = s.replace(/-(EQ|BE|SM|BZ)$/i, "").split(' ')[0];
  }

  if (s === "NIFTY" || s === "NIFTY50" || s === "NIFTY 50" || s === "^NSEI" || s === "NSEI") return "^NSEI";
  if (s === "BANKNIFTY" || s === "BANK NIFTY" || s === "NIFTY BANK" || s === "^NSEBANK" || s === "NSEBANK") return "^NSEBANK";
  if (s === "SENSEX" || s === "^BSESN" || s === "BSESN") return "^BSESN";
  if (s === "FINNIFTY" || s === "NIFTY FIN SERVICE" || s === "^CNXFIN") return "^CNXFIN";
  if (s === "NIFTY IT" || s === "NIFTYIT" || s === "^CNXIT") return "^CNXIT";

  if (s.endsWith(".NS") || s.endsWith(".BO")) return s;
  if (s.startsWith("^")) return s;
  return `${s}.NS`;
}

export function displayName(sym: string): string {
  const map: Record<string, string> = {
    "^NSEI": "NIFTY 50",
    "^BSESN": "SENSEX",
    "^NSEBANK": "BANK NIFTY",
  };
  return map[sym] ?? sym;
}

export interface YfQuote {
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
  avg_trade_price?: number;
  last_traded_quantity?: number;
  last_traded_time?: string;
  lower_circuit?: number;
  upper_circuit?: number;
  open_interest?: number;
}

export async function fetchQuote(symbol: string): Promise<YfQuote> {
  const yfSym = toYfSymbol(symbol);
  const quoteUrl = `${YAHOO_QUOTE}?symbols=${encodeURIComponent(yfSym)}`;
  const chartUrl = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?interval=1d&range=2d`;

  let meta: any = {};
  let price = 0;
  let prevClose = 0;
  let currency = "INR";
  let name: string | null = null;
  let qResult: any = null;

  try {
    const json = await fetchJson(quoteUrl);
    qResult = json?.quoteResponse?.result?.[0];
    if (qResult) {
      price = Number(qResult.regularMarketPrice ?? qResult.ask ?? qResult.bid ?? 0);
      prevClose = Number(qResult.regularMarketPreviousClose ?? qResult.regularMarketPreviousClose ?? qResult.previousClose ?? 0);
      currency = qResult.currency ?? "INR";
      name = qResult.longName ?? qResult.shortName ?? null;
    }
  } catch {
    // Ignore direct quote failures and fall back to chart data.
  }

  if (!price || !prevClose) {
    try {
      const json = await fetchJson(chartUrl);
      const result = json?.chart?.result?.[0];
      if (!result) throw new Error(`No YF result for ${yfSym}`);
      meta = result.meta ?? {};
      const closes = result.indicators?.quote?.[0]?.close ?? [];
      price = Number(meta.regularMarketPrice ?? closes[closes.length - 1] ?? 0);
      prevClose = Number(meta.chartPreviousClose ?? meta.previousClose ?? closes[closes.length - 2] ?? price ?? 0);
      currency = meta.currency ?? currency;
      if (!name) {
        name = CURATED_NAMES[yfSym.replace('.NS', '').replace('.BO', '')] ?? null;
      }
    } catch (err) {
      throw new Error(`Yahoo quote failed for ${yfSym}: ${err.message}`);
    }
  }

  if (!price) {
    throw new Error(`Yahoo quote price unavailable for ${yfSym}`);
  }

  const rawSym = yfSym.replace(".NS", "").replace(".BO", "");
  const finalName = name ?? CURATED_NAMES[rawSym] ?? rawSym;
  const change = price - prevClose;
  const changePct = prevClose ? (change / prevClose) * 100 : 0;

  const dayLow = qResult?.regularMarketDayLow ?? meta.regularMarketDayLow;
  const dayHigh = qResult?.regularMarketDayHigh ?? meta.regularMarketDayHigh;
  const open = qResult?.regularMarketOpen ?? meta.regularMarketOpen;
  const volume = qResult?.regularMarketVolume ?? meta.regularMarketVolume;

  return {
    symbol: rawSym,
    yf_symbol: yfSym,
    name: finalName,
    price: round(price, 2),
    previous_close: round(prevClose, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    currency: currency === "INR" || yfSym.startsWith("^") ? "INR" : "USD",
    market: "stock",
    display_name: displayName(yfSym),
    category: yfSym.startsWith("^") ? "index" : "stock",
    day_low: dayLow != null ? round(Number(dayLow), 2) : undefined,
    day_high: dayHigh != null ? round(Number(dayHigh), 2) : undefined,
    open: open != null ? round(Number(open), 2) : undefined,
    volume: volume != null ? Number(volume) : undefined,
  };
}

export interface CandleData {
  t: number;
  o: number;
  h: number;
  l: number;
  c: number;
}

interface HistoryResult {
  symbol: string;
  points: { t: number; v: number }[];
  candles: CandleData[];
}

export async function fetchHistory(
  symbol: string,
  range: string,
  interval?: string,
  opts?: {
    /**
     * Pre-resolved Yahoo symbol. Supply this for a US listing: `toYfSymbol`
     * appends ".NS" to anything unsuffixed, so AAPL became AAPL.NS, which does
     * not exist and made every US chart fail with a 500.
     */
    yfSymbol?: string;
    /**
     * Honour `range` AND `interval` exactly as given.
     *
     * Off by default because the shipped mobile client sends `range=1mo` with a
     * real `interval` and depends on the interval winning — the map below then
     * picks the range. Turning that into a silent behaviour change for an app
     * already on the Play Store is not worth the tidiness, so callers that want
     * both respected ask for it.
     */
    strict?: boolean;
  }
): Promise<HistoryResult> {
  const yfSym = opts?.yfSymbol ?? toYfSymbol(symbol);

  const periodMap: Record<string, string> = {
    "1d": "1d", "5d": "5d", "1mo": "1mo", "3mo": "3mo",
    "6mo": "6mo", "1y": "1y", "5y": "5y",
  };
  const defaultInterval: Record<string, string> = {
    "1d": "5m", "5d": "30m", "1mo": "1d", "3mo": "1d",
    "6mo": "1d", "1y": "1d", "5y": "1wk",
  };
  const intervalMap: Record<string, { range: string; interval: string }> = {
    "1m":  { range: "1d", interval: "1m" },
    "5m":  { range: "5d", interval: "5m" },
    "15m": { range: "1mo", interval: "15m" },
    "30m": { range: "1mo", interval: "30m" },
    "1h":  { range: "3mo", interval: "1h" },
    "1d":  { range: "1y", interval: "1d" },
    "1w":  { range: "5y", interval: "1wk" },
  };

  let period: string;
  let yfInterval: string;

  if (opts?.strict && interval) {
    // Both as asked. Without this branch `range` is silently discarded whenever
    // an interval is present, so range=3mo&interval=1d quietly returned a full
    // year — which made a "3M" and a "1Y" button produce identical charts.
    period = periodMap[range] ?? range;
    yfInterval = interval;
  } else if (interval && intervalMap[interval]) {
    period = intervalMap[interval].range;
    yfInterval = intervalMap[interval].interval;
  } else {
    period = periodMap[range] ?? "1mo";
    yfInterval = defaultInterval[range] ?? "1d";
  }

  // Yahoo expects "1wk" for weekly bars, rejecting "1w" with 400
  if (yfInterval === "1w") yfInterval = "1wk";

  function extractValidCandles(r: any): CandleData[] {
    if (!r) return [];
    const timestamps: number[] = r.timestamp ?? [];
    const quote = r.indicators?.quote?.[0] ?? {};
    const opens: (number | null)[] = quote.open ?? [];
    const highs: (number | null)[] = quote.high ?? [];
    const lows: (number | null)[] = quote.low ?? [];
    const closes: (number | null)[] = quote.close ?? [];

    const valid: CandleData[] = [];
    for (let i = 0; i < timestamps.length; i++) {
      const o = opens[i];
      const h = highs[i];
      const l = lows[i];
      const c = closes[i];
      if (
        o != null &&
        h != null &&
        l != null &&
        c != null &&
        Number.isFinite(o) &&
        Number.isFinite(h) &&
        Number.isFinite(l) &&
        Number.isFinite(c)
      ) {
        valid.push({
          t: timestamps[i] * 1000,
          o: round(o, 2),
          h: round(h, 2),
          l: round(l, 2),
          c: round(c, 2),
        });
      }
    }
    return valid;
  }

  async function queryYahooCandles(p: string, intv: string): Promise<CandleData[]> {
    try {
      const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?range=${p}&interval=${intv}`;
      const res = await fetch(url, { headers: { "User-Agent": UA } });
      if (!res.ok) return [];
      const json = await res.json();
      return extractValidCandles(json?.chart?.result?.[0]);
    } catch {
      return [];
    }
  }

  let candles = await queryYahooCandles(period, yfInterval);
  let isFallback = false;

  // If no valid candles returned (market closed, weekend, holiday, pre-market, or Yahoo limit),
  // dynamically fall back to a wider range so charts never fail with "no price history".
  if (candles.length === 0) {
    let fallbackRange = "5d";
    if (yfInterval === "1m") {
      fallbackRange = "5d";
    } else if (["5m", "15m", "30m"].includes(yfInterval)) {
      fallbackRange = "1mo";
    } else if (yfInterval === "1h") {
      fallbackRange = "3mo";
    } else {
      fallbackRange = "1y";
    }

    if (fallbackRange !== period) {
      const fbCandles = await queryYahooCandles(fallbackRange, yfInterval);
      if (fbCandles.length > 0) {
        candles = fbCandles;
        isFallback = true;
      }
    }
  }

  // If still empty and strict mode was used, try safe daily fallback
  if (candles.length === 0 && opts?.strict) {
    const fbDaily = await queryYahooCandles("1mo", "1d");
    if (fbDaily.length > 0) {
      candles = fbDaily;
      isFallback = true;
    }
  }

  // When a 1-day range was requested but we had to fetch 5d because markets are closed,
  // slice to the most recent trading session to preserve the 1-day intraday view.
  if (isFallback && (range === "1d" || period === "1d") && candles.length > 0) {
    let lastGapIdx = 0;
    for (let i = 1; i < candles.length; i++) {
      // Gap > 4 hours indicates an overnight / weekend gap between trading sessions
      if (candles[i].t - candles[i - 1].t > 14400 * 1000) {
        lastGapIdx = i;
      }
    }
    candles = candles.slice(lastGapIdx);
  }

  const points = candles.map((c) => ({ t: c.t, v: c.c }));
  return { symbol: symbol.toUpperCase(), points, candles };
}

export async function searchStocks(query: string): Promise<{ symbol: string; name: string; market: string }[]> {
  const url = `${YAHOO_SEARCH}?q=${encodeURIComponent(query)}&count=25`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) return [];

  const json = await res.json();
  const quotes: any[] = json.quotes ?? [];

  return quotes
    .filter((q: any) => {
      const sym = q.symbol ?? "";
      if (sym.includes(".BO") && q.exchange !== "NSI") return false;
      if (sym.startsWith("0P")) return false;
      if (q.quoteType === "MUTUALFUND" || q.quoteType === "ETF") return false;
      return true;
    })
    .slice(0, 25)
    .map((q: any) => {
      const sym = (q.symbol ?? "").toUpperCase().replace(".NS", "").replace(".BO", "");
      return {
        symbol: sym,
        name: q.longName ?? q.shortName ?? q.symbol ?? "",
        market: "stock",
      };
    });
}

/**
 * Search US-listed equities.
 *
 * Mirror image of searchStocks: that one keeps Indian listings, this one keeps
 * US ones. Yahoo marks US listings with an empty/undefined `exchDisp` suffix, so
 * the reliable filter is "no dot suffix in the symbol" — AAPL is US, AAPL.NS and
 * SAP.DE are not.
 */
export async function searchUsStocks(
  query: string,
): Promise<{ symbol: string; name: string; market: string }[]> {
  const url = `${YAHOO_SEARCH}?q=${encodeURIComponent(query)}&count=25`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) return [];

  const json = await res.json();
  const quotes: any[] = json.quotes ?? [];
  const US_EXCHANGES = new Set(["NMS", "NYQ", "NGM", "NCM", "ASE", "PCX", "BATS"]);

  return quotes
    .filter((q: any) => {
      const sym: string = q.symbol ?? "";
      if (!sym) return false;
      // A dot suffix means a non-US listing (.NS, .BO, .DE, .L). Class shares
      // like BRK-B use a dash on the search endpoint, so they survive this.
      if (/\.[A-Z]{1,3}$/i.test(sym)) return false;
      if (sym.startsWith("0P") || sym.startsWith("^")) return false;
      if (q.quoteType !== "EQUITY") return false;
      if (q.exchange && !US_EXCHANGES.has(q.exchange)) return false;
      return true;
    })
    .slice(0, 25)
    .map((q: any) => ({
      symbol: (q.symbol ?? "").toUpperCase(),
      name: q.longName ?? q.shortName ?? q.symbol ?? "",
      market: "us_stock",
    }));
}

export async function searchPakistanStocks(
  query: string,
): Promise<{ symbol: string; name: string; market: string }[]> {
  const url = `${YAHOO_SEARCH}?q=${encodeURIComponent(query)}&count=25`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) return [];

  const json = await res.json();
  const quotes: any[] = json.quotes ?? [];

  return quotes
    .filter((q: any) => {
      const sym: string = (q.symbol ?? "").toUpperCase();
      return sym.endsWith(".KA") || q.exchange === "KAR";
    })
    .slice(0, 25)
    .map((q: any) => ({
      symbol: (q.symbol ?? "").toUpperCase(),
      name: q.longName ?? q.shortName ?? q.symbol ?? "",
      market: "pakistan_stock",
    }));
}

export async function searchItalyStocks(
  query: string,
): Promise<{ symbol: string; name: string; market: string }[]> {
  const url = `${YAHOO_SEARCH}?q=${encodeURIComponent(query)}&count=25`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) return [];

  const json = await res.json();
  const quotes: any[] = json.quotes ?? [];

  return quotes
    .filter((q: any) => {
      const sym: string = (q.symbol ?? "").toUpperCase();
      return sym.endsWith(".MI") || q.exchange === "MIL";
    })
    .slice(0, 25)
    .map((q: any) => ({
      symbol: (q.symbol ?? "").toUpperCase(),
      name: q.longName ?? q.shortName ?? q.symbol ?? "",
      market: "italy_stock",
    }));
}


export async function whatIfYahoo(
  symbol: string,
  market: string,
  amount: number,
  yearsAgo: number
): Promise<Record<string, unknown>> {
  const yfSym = toYfSymbol(symbol, market);
  
  // Calculate precise calendar-based period1 and period2
  const end = new Date();
  const start = new Date();
  start.setFullYear(start.getFullYear() - yearsAgo);
  
  const period1 = Math.floor(start.getTime() / 1000);
  const period2 = Math.floor(end.getTime() / 1000);

  const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?period1=${period1}&period2=${period2}&interval=1d`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`YF whatif failed: ${res.status}`);

  const json = await res.json();
  const result = json?.chart?.result?.[0];
  if (!result) throw new Error("No whatif data");

  const timestamps: number[] = result.timestamp ?? [];
  const closes: (number | null)[] = result.indicators?.quote?.[0]?.close ?? [];
  
  // Filter out any null close prices and find first and last valid entries
  let firstIdx = -1;
  let lastIdx = -1;
  for (let i = 0; i < closes.length; i++) {
    if (closes[i] != null) {
      if (firstIdx === -1) firstIdx = i;
      lastIdx = i;
    }
  }
  
  if (firstIdx === -1 || lastIdx === -1 || firstIdx === lastIdx) {
    throw new Error("Insufficient history");
  }

  const oldPrice = closes[firstIdx]!;
  const newPrice = closes[lastIdx]!;
  const units = amount / oldPrice;
  const currentValue = units * newPrice;
  const pnl = currentValue - amount;
  const pnlPct = amount ? (pnl / amount) * 100 : 0;
  
  // Expose the exact purchase date from the Yahoo dataset
  const purchaseTimestamp = timestamps[firstIdx] * 1000;
  const purchaseDate = new Date(purchaseTimestamp).toISOString();

  return {
    symbol: symbol.toUpperCase(),
    yf_symbol: yfSym,
    amount_invested: amount,
    purchase_date: purchaseDate,
    purchase_price: round(oldPrice, 2),
    current_price: round(newPrice, 2),
    units: round(units, 4),
    current_value: round(currentValue, 2),
    pnl: round(pnl, 2),
    pnl_pct: round(pnlPct, 2),
  };
}

function round(n: number, decimals: number): number {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}
