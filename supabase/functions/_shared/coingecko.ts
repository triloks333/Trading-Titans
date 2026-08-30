const CG_BASE = "https://api.coingecko.com/api/v3";

const SYMBOL_OVERRIDES: Record<string, string> = {
  btc: "bitcoin",
  eth: "ethereum",
  sol: "solana",
  ada: "cardano",
  xrp: "ripple",
  doge: "dogecoin",
  bnb: "binancecoin",
  pol: "polygon-ecosystem-token", // was matic/matic-network before the Polygon rebrand
  dot: "polkadot",
  ltc: "litecoin",
  avax: "avalanche-2",
  shib: "shiba-inu",
  link: "chainlink",
  uni: "uniswap",
  atom: "cosmos",
  trx: "tron",
  vet: "vechain",
  fil: "filecoin",
  algo: "algorand",
  near: "near-protocol",
  apt: "aptos",
  sand: "the-sandbox",
  mana: "decentraland",
  axs: "axie-infinity",
};

let _cgList: { id: string; symbol: string; name: string }[] = [];
let _cgListTime = 0;

async function getCgList(): Promise<{ id: string; symbol: string; name: string }[]> {
  const now = Date.now();
  if (_cgList.length > 0 && now - _cgListTime < 3600000) return _cgList;
  try {
    const res = await fetch(`${CG_BASE}/coins/list`, { headers: { Accept: "application/json" } });
    if (res.ok) {
      _cgList = await res.json();
      _cgListTime = now;
    }
  } catch {
    // use existing list
  }
  return _cgList;
}

export function resolveCgId(sym: string): string | null {
  const s = sym.toLowerCase().trim();
  if (SYMBOL_OVERRIDES[s]) return SYMBOL_OVERRIDES[s];
  const list = _cgList;
  for (const c of list) {
    if (c.symbol.toLowerCase() === s) return c.id;
  }
  return null;
}

export interface CgQuote {
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

export async function fetchQuote(sym: string): Promise<CgQuote> {
  const cgId = resolveCgId(sym);
  if (!cgId) throw new Error(`Unknown crypto: ${sym}`);

  const url = `${CG_BASE}/simple/price?ids=${encodeURIComponent(cgId)}&vs_currencies=inr&include_24hr_change=true`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });

  if (res.status === 429) throw new Error("CG rate-limited");
  if (!res.ok) throw new Error(`CG quote failed: ${res.status}`);

  const json = await res.json();
  const data = json[cgId];
  if (!data) throw new Error(`No CG data for ${cgId}`);

  const price = Number(data.inr) || 0;
  const changePct = Number(data.inr_24h_change) || 0;
  const prev = changePct ? price / (1 + changePct / 100) : price;
  const name = cgId.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

  return {
    symbol: sym.toUpperCase(),
    yf_symbol: cgId,
    name,
    price: round(price, 2),
    previous_close: round(prev, 2),
    change: round(price - prev, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "crypto",
  };
}

export async function fetchHistory(
  sym: string,
  range: string,
  interval?: string
): Promise<{ symbol: string; points: { t: number; v: number }[]; candles: CandleData[] }> {
  const cgId = resolveCgId(sym);
  if (!cgId) throw new Error(`Unknown crypto: ${sym}`);

  // CoinGecko's public /ohlc accepts only a fixed set of day counts. `5y` mapped
  // to 1825, which is not one of them, so every 5-year crypto chart failed
  // outright. 365 is the longest the free tier serves, so that is the honest cap.
  const daysMap: Record<string, number> = {
    "1d": 1, "5d": 7, "1mo": 30, "3mo": 90, "6mo": 180, "1y": 365, "5y": 365,
  };
  const days = daysMap[range] ?? 30;

  const url = `${CG_BASE}/coins/${encodeURIComponent(cgId)}/ohlc?vs_currency=inr&days=${days}`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (res.status === 429) throw new Error("CG history rate-limited");
  if (!res.ok) throw new Error(`CG history failed: ${res.status}`);

  const json = await res.json();
  const ohlc: [number, number, number, number, number][] = json ?? [];

  /*
   * Downsample by AGGREGATING, not by sampling.
   *
   * This used to keep every `step`-th candle and discard the rest, which quietly
   * corrupted the chart: the true high and low of a period lived in the candles
   * that were thrown away, so wicks were shortened or lost and the visible range
   * was narrower than the market's. Merging a group into one candle — first open,
   * highest high, lowest low, last close — is what a longer timeframe actually
   * means and preserves the extremes.
   */
  const target = 120;
  const step = Math.max(1, Math.ceil(ohlc.length / target));
  const candles: CandleData[] = [];
  const points: { t: number; v: number }[] = [];

  for (let i = 0; i < ohlc.length; i += step) {
    const group = ohlc.slice(i, i + step);
    if (group.length === 0) continue;
    const ts = group[0][0];
    const open = group[0][1];
    let high = group[0][2];
    let low = group[0][3];
    for (const [, , h, l] of group) {
      if (h > high) high = h;
      if (l < low) low = l;
    }
    const close = group[group.length - 1][4];
    candles.push({
      t: ts,
      o: round(open, 2),
      h: round(high, 2),
      l: round(low, 2),
      c: round(close, 2),
    });
    points.push({ t: ts, v: round(close, 2) });
  }
  return { symbol: sym.toUpperCase(), points, candles };
}

export interface CandleData {
  t: number;
  o: number;
  h: number;
  l: number;
  c: number;
}

export async function searchCrypto(
  query: string
): Promise<{ symbol: string; name: string; market: string; id: string }[]> {
  const q = query.toLowerCase();
  const list = await getCgList();
  const results: { symbol: string; name: string; market: string; id: string }[] = [];

  for (const c of list) {
    if (
      c.symbol.toLowerCase() === q ||
      c.name.toLowerCase().includes(q) ||
      c.id.toLowerCase().includes(q)
    ) {
      results.push({ symbol: c.symbol.toUpperCase(), name: c.name, market: "crypto", id: c.id });
      if (results.length >= 25) break;
    }
  }
  return results;
}

export async function whatIfCrypto(
  sym: string,
  amount: number,
  yearsAgo: number
): Promise<Record<string, unknown>> {
  const cgId = resolveCgId(sym);
  if (!cgId) throw new Error(`Unknown crypto: ${sym}`);

  const days = Math.ceil(yearsAgo * 365);
  const url = `${CG_BASE}/coins/${encodeURIComponent(cgId)}/market_chart?vs_currency=inr&days=${days}`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`CG whatif failed: ${res.status}`);

  const json = await res.json();
  const prices: [number, number][] = json.prices ?? [];
  if (prices.length < 2) throw new Error("Insufficient CG history");

  const oldPrice = prices[0][1];
  const newPrice = prices[prices.length - 1][1];
  const units = amount / oldPrice;
  const currentValue = units * newPrice;
  const pnl = currentValue - amount;
  const pnlPct = amount ? (pnl / amount) * 100 : 0;
  const targetDate = new Date(Date.now() - yearsAgo * 365 * 86400000);

  return {
    symbol: sym.toUpperCase(),
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

// Eagerly populate CG list on import for faster subsequent lookups
getCgList();
