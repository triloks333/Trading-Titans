// US equity market helpers shared by the quote, search and order functions.
//
// Two jobs: decide whether the US regular session is open right now, and supply
// a USD -> INR rate. Both are needed by the order engine, which keeps every
// wallet number in INR while the app displays US prices in USD.

const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart";
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

/** Market value stored on orders.market / holdings.market for US equities. */
export const US_MARKET = "us_stock";

/**
 * Nth given weekday of a month, as a UTC timestamp at `utcHour`.
 * Used to locate the US DST switchover instants.
 */
function nthWeekdayUtc(
  year: number,
  month: number, // 0-based
  weekday: number, // 0 = Sunday
  n: number,
  utcHour: number,
): number {
  const first = Date.UTC(year, month, 1, utcHour, 0, 0, 0);
  const firstWeekday = new Date(first).getUTCDay();
  const offset = (weekday - firstWeekday + 7) % 7;
  return Date.UTC(year, month, 1 + offset + (n - 1) * 7, utcHour, 0, 0, 0);
}

/**
 * True when US Eastern is observing daylight saving time (EDT, UTC-4).
 *
 * Rule since 2007: DST runs from 02:00 local on the second Sunday of March
 * (07:00 UTC, still EST) to 02:00 local on the first Sunday of November
 * (06:00 UTC, still EDT).
 */
export function isUsDst(at: Date = new Date()): boolean {
  const year = at.getUTCFullYear();
  const start = nthWeekdayUtc(year, 2, 0, 2, 7); // March, 2nd Sunday, 07:00 UTC
  const end = nthWeekdayUtc(year, 10, 0, 1, 6); // November, 1st Sunday, 06:00 UTC
  const t = at.getTime();
  return t >= start && t < end;
}

/** Minutes to subtract from UTC to get US Eastern wall-clock time. */
export function usEasternOffsetMinutes(at: Date = new Date()): number {
  return isUsDst(at) ? 240 : 300; // EDT = UTC-4, EST = UTC-5
}

/** US Eastern wall-clock time, expressed as a Date whose UTC fields are ET. */
export function usEasternNow(at: Date = new Date()): Date {
  return new Date(at.getTime() - usEasternOffsetMinutes(at) * 60 * 1000);
}

/**
 * True during the US regular session: Mon-Fri, 09:30-16:00 US Eastern.
 *
 * ponytail: weekends only, no US holiday calendar. On Thanksgiving or July 4th
 * this reports open and a pending order would fill against the last price Yahoo
 * served. The existing Indian check has the same gap. Upgrade path: a
 * `market_holidays` table keyed on (market, date), checked here and in
 * isStockOpen.
 */
export function isUsMarketOpen(at: Date = new Date()): boolean {
  const et = usEasternNow(at);
  const day = et.getUTCDay();
  if (day === 0 || day === 6) return false;
  const minutes = et.getUTCHours() * 60 + et.getUTCMinutes();
  return minutes >= 9 * 60 + 30 && minutes < 16 * 60;
}

/** Human-readable session label, for the market-status endpoint. */
export function usSessionLabel(at: Date = new Date()): string {
  if (isUsMarketOpen(at)) return "Market Open";
  const et = usEasternNow(at);
  const day = et.getUTCDay();
  if (day === 0 || day === 6) return "Weekend Closed";
  return isUsDst(at) ? "Opens at 7:00 PM IST" : "Opens at 8:00 PM IST";
}

// ── USD -> INR ──────────────────────────────────────────────────────────────
// Cached in module scope: an isolate serves many requests, and the rate only
// needs to be fresh to the minute for a paper-trading fill.
let _cachedRate = 0;
let _cachedAt = 0;
const RATE_TTL_MS = 10 * 60 * 1000;

/**
 * USD -> INR rate. Falls back to the last known value, then to a constant, so a
 * Yahoo outage can never price an order at zero.
 *
 * The caller must persist the returned rate on the order row: without it a past
 * trade's INR cost cannot be reconciled against its USD price later.
 */
export async function getUsdInrRate(): Promise<number> {
  const now = Date.now();
  if (_cachedRate > 0 && now - _cachedAt < RATE_TTL_MS) return _cachedRate;
  try {
    const res = await fetch(`${YAHOO_CHART}/USDINR=X?range=2d&interval=1d`, {
      headers: { "User-Agent": UA },
    });
    if (res.ok) {
      const body = await res.json();
      const price = body?.chart?.result?.[0]?.meta?.regularMarketPrice;
      if (typeof price === "number" && price > 0) {
        _cachedRate = price;
        _cachedAt = now;
        return price;
      }
    }
  } catch (_) {
    // fall through to the cached or default value
  }
  if (_cachedRate > 0) return _cachedRate;
  // ponytail: last-resort constant so an FX outage degrades instead of failing.
  // Stored on the order as usual, so such fills stay identifiable.
  return 88.0;
}

let _cachedPkrRate = 0;
let _cachedPkrAt = 0;
export async function getPkrInrRate(): Promise<number> {
  const now = Date.now();
  if (_cachedPkrRate > 0 && now - _cachedPkrAt < RATE_TTL_MS) return _cachedPkrRate;
  try {
    const res = await fetch(`${YAHOO_CHART}/PKRINR=X?range=2d&interval=1d`, {
      headers: { "User-Agent": UA },
    });
    if (res.ok) {
      const body = await res.json();
      const price = body?.chart?.result?.[0]?.meta?.regularMarketPrice;
      if (typeof price === "number" && price > 0) {
        _cachedPkrRate = price;
        _cachedPkrAt = now;
        return price;
      }
    }
  } catch (_) {
    // fall through
  }
  if (_cachedPkrRate > 0) return _cachedPkrRate;
  return 0.34;
}

let _cachedEurRate = 0;
let _cachedEurAt = 0;
export async function getEurInrRate(): Promise<number> {
  const now = Date.now();
  if (_cachedEurRate > 0 && now - _cachedEurAt < RATE_TTL_MS) return _cachedEurRate;
  try {
    const res = await fetch(`${YAHOO_CHART}/EURINR=X?range=2d&interval=1d`, {
      headers: { "User-Agent": UA },
    });
    if (res.ok) {
      const body = await res.json();
      const price = body?.chart?.result?.[0]?.meta?.regularMarketPrice;
      if (typeof price === "number" && price > 0) {
        _cachedEurRate = price;
        _cachedEurAt = now;
        return price;
      }
    }
  } catch (_) {
    // fall through
  }
  if (_cachedEurRate > 0) return _cachedEurRate;
  return 106.0;
}


/**
 * Yahoo symbol for a US equity. US tickers are used as-is; only the exchange
 * prefix and any Indian suffix that slipped through are stripped.
 *
 * Note the contrast with the Indian path, which appends ".NS" — doing that to
 * AAPL yields AAPL.NS, which does not exist.
 */
export function toUsYahooSymbol(symbol: string): string {
  let s = (symbol || "").toUpperCase().trim();
  const colon = s.indexOf(":");
  if (colon !== -1) s = s.slice(colon + 1);
  s = s.replace(/\.(NS|BO)$/i, "");
  // Class shares use a dot on Yahoo (BRK.B), but our stored form uses a dash.
  s = s.replace(/-([A-Z])$/i, ".$1");
  return s;
}

/** Storage form of a US symbol: the inverse of the class-share rewrite above. */
export function fromUsYahooSymbol(symbol: string): string {
  return (symbol || "").toUpperCase().trim().replace(/\.([A-Z])$/i, "-$1");
}
