const YAHOO_BASE = "https://query1.finance.yahoo.com/v8/finance/chart";
const YAHOO_QUOTE = "https://query1.finance.yahoo.com/v7/finance/quote";
const YAHOO_SEARCH = "https://query1.finance.yahoo.com/v1/finance/search";
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

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

export function toYfSymbol(sym: string): string {
  const s = sym.toUpperCase().trim();
  if (s.endsWith(".NS") || s.endsWith(".BO") || ["^NSEI", "^BSESN", "^NSEBANK"].includes(s)) return s;
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
}

export async function fetchQuote(symbol: string): Promise<YfQuote> {
  const yfSym = toYfSymbol(symbol);
  const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?interval=1d&range=2d`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`YF chart failed: ${res.status} for ${yfSym}`);

  const json = await res.json();
  const result = json?.chart?.result?.[0];
  if (!result) throw new Error(`No YF result for ${yfSym}`);

  const meta = result.meta ?? {};
  const timestamps = result.timestamp ?? [];
  const closes = result.indicators?.quote?.[0]?.close ?? [];

  let price = meta.regularMarketPrice ?? closes[closes.length - 1];
  let prevClose = meta.chartPreviousClose ?? meta.previousClose ?? price;

  if (price == null && closes.length > 0) {
    price = closes[closes.length - 1];
  }
  if (prevClose == null && closes.length > 1) {
    prevClose = closes[closes.length - 2];
  }

  price = Number(price) || 0;
  prevClose = Number(prevClose) || price;
  const change = price - prevClose;
  const changePct = prevClose ? (change / prevClose) * 100 : 0;
  const currency = meta.currency ?? "INR";
  const rawSym = yfSym.replace(".NS", "").replace(".BO", "");

  // Get display name from curated list or quote summary
  let name = CURATED_NAMES[rawSym] ?? rawSym;
  if (name === rawSym) {
    try {
      const qUrl = `${YAHOO_QUOTE}?symbols=${encodeURIComponent(yfSym)}`;
      const qRes = await fetch(qUrl, { headers: { "User-Agent": UA } });
      if (qRes.ok) {
        const qJson = await qRes.json();
        const qResult = qJson?.quoteResponse?.result?.[0];
        if (qResult) {
          name = qResult.longName ?? qResult.shortName ?? rawSym;
        }
      }
    } catch {
      // fallback to curated name or raw symbol
    }
  }

  return {
    symbol: rawSym,
    yf_symbol: yfSym,
    name,
    price: round(price, 2),
    previous_close: round(prevClose, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    currency: currency === "INR" || yfSym.startsWith("^") ? "INR" : "USD",
    market: "stock",
    display_name: displayName(yfSym),
    category: yfSym.startsWith("^") ? "index" : "stock",
  };
}

export async function fetchHistory(
  symbol: string,
  range: string
): Promise<{ symbol: string; points: { t: number; v: number }[] }> {
  const yfSym = toYfSymbol(symbol);

  const periodMap: Record<string, string> = {
    "1d": "1d", "5d": "5d", "1mo": "1mo", "3mo": "3mo",
    "6mo": "6mo", "1y": "1y", "5y": "5y",
  };
  const intervalMap: Record<string, string> = {
    "1d": "5m", "5d": "30m", "1mo": "1d", "3mo": "1d",
    "6mo": "1d", "1y": "1d", "5y": "1wk",
  };

  const period = periodMap[range] ?? "1mo";
  const interval = intervalMap[range] ?? "1d";

  const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?range=${period}&interval=${interval}`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`YF history failed: ${res.status}`);

  const json = await res.json();
  const result = json?.chart?.result?.[0];
  if (!result) return { symbol: symbol.toUpperCase(), points: [] };

  const timestamps: number[] = result.timestamp ?? [];
  const closes: number[] = result.indicators?.quote?.[0]?.close ?? [];

  const points = [];
  for (let i = 0; i < timestamps.length && i < closes.length; i++) {
    if (closes[i] != null) {
      points.push({ t: timestamps[i] * 1000, v: round(closes[i], 2) });
    }
  }
  return { symbol: symbol.toUpperCase(), points };
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
    .map((q: any) => ({
      symbol: q.symbol ?? "",
      name: q.longName ?? q.shortName ?? q.symbol ?? "",
      market: "stock",
    }));
}

export async function whatIfStock(
  symbol: string,
  amount: number,
  yearsAgo: number
): Promise<Record<string, unknown>> {
  const yfSym = toYfSymbol(symbol);
  const period = yearsAgo > 1 ? "5y" : "1y";
  const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?range=${period}&interval=1d`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`YF whatif failed: ${res.status}`);

  const json = await res.json();
  const result = json?.chart?.result?.[0];
  if (!result) throw new Error("No whatif data");

  const closes: number[] = result.indicators?.quote?.[0]?.close ?? [];
  if (closes.length < 2) throw new Error("Insufficient history");

  const oldPrice = closes[0];
  const newPrice = closes[closes.length - 1];
  const units = amount / oldPrice;
  const currentValue = units * newPrice;
  const pnl = currentValue - amount;
  const pnlPct = amount ? (pnl / amount) * 100 : 0;
  const targetDate = new Date(Date.now() - yearsAgo * 365 * 86400000);

  return {
    symbol: symbol.toUpperCase(),
    amount_invested: amount,
    purchase_date: targetDate.toISOString(),
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
