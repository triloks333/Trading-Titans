import { fetchQuote as yfQuote } from "./yahoo.ts";

const BINANCE_BASE = "https://api.binance.com/api/v3";

const SYMBOL_MAP: Record<string, string> = {
  "BTC": "BTCUSDT",
  "ETH": "ETHUSDT",
  "SOL": "SOLUSDT",
  "ADA": "ADAUSDT",
  "XRP": "XRPUSDT",
  "DOGE": "DOGEUSDT",
  "BNB": "BNBUSDT",
  "MATIC": "MATICUSDT",
  "DOT": "DOTUSDT",
  "AVAX": "AVAXUSDT",
  "SHIB": "SHIBUSDT",
  "LINK": "LINKUSDT",
  "LTC": "LTCUSDT",
};

let _cachedRate = 83.5;
let _lastRateUpdate = 0;

async function getUsdInrRate(): Promise<number> {
  const now = Date.now();
  // Cache the rate for 30 minutes
  if (now - _lastRateUpdate < 1800000) {
    return _cachedRate;
  }
  try {
    const usdInr = await yfQuote("USDINR=X");
    if (usdInr && usdInr.price > 0) {
      _cachedRate = usdInr.price;
      _lastRateUpdate = now;
    }
  } catch (_) {
    // Return cached rate on failure
  }
  return _cachedRate;
}

export interface BinanceQuote {
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

export async function fetchQuote(sym: string): Promise<BinanceQuote> {
  const cleanSym = sym.toUpperCase().trim();
  const binanceSym = SYMBOL_MAP[cleanSym] ?? `${cleanSym}USDT`;

  const response = await fetch(`${BINANCE_BASE}/ticker/24hr?symbol=${binanceSym}`);
  if (!response.ok) {
    throw new Error(`Binance quote failed: ${response.status} for ${binanceSym}`);
  }

  const data = await response.json();
  const usdPrice = Number(data.lastPrice) || 0;
  const usdChangePct = Number(data.priceChangePercent) || 0;

  // Convert to INR
  const rate = await getUsdInrRate();
  const priceInr = usdPrice * rate;
  
  // Previous close in INR
  const prevInr = usdChangePct ? priceInr / (1 + usdChangePct / 100) : priceInr;
  const changeInr = priceInr - prevInr;

  const displayName = cleanSym === "BTC" ? "Bitcoin" : cleanSym === "ETH" ? "Ethereum" : cleanSym;

  return {
    symbol: cleanSym,
    yf_symbol: binanceSym,
    name: displayName,
    price: round(priceInr, 2),
    previous_close: round(prevInr, 2),
    change: round(changeInr, 2),
    change_pct: round(usdChangePct, 2), // Keep percentage change relative
    currency: "INR",
    market: "crypto",
    display_name: displayName,
    category: "crypto",
    day_low: data.lowPrice ? round(Number(data.lowPrice) * rate, 2) : undefined,
    day_high: data.highPrice ? round(Number(data.highPrice) * rate, 2) : undefined,
    open: data.openPrice ? round(Number(data.openPrice) * rate, 2) : undefined,
    volume: data.volume ? Number(data.volume) : undefined,
  };
}

function round(n: number, decimals: number): number {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}
