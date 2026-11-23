/**
 * Indian F&O expiry calendar: the FALLBACK rule for when the exchange contract
 * list (the `instruments` table, synced daily from the Fyers NSE/BSE masters)
 * has nothing for a symbol. The contract list is the source of truth; this
 * module only has to be right when that is missing.
 *
 * Rules in force since 1 Sep 2025 (SEBI expiry-day harmonisation):
 *   - NSE: every monthly contract (index and stock, options and futures)
 *     expires on the LAST TUESDAY of the month.
 *   - NSE: NIFTY is the only index with weekly options, every Tuesday.
 *     BANKNIFTY / FINNIFTY / MIDCPNIFTY weeklies were withdrawn in Nov 2024.
 *   - BSE: monthly contracts expire on the LAST THURSDAY; SENSEX has weekly
 *     options every Thursday.
 *   - If the expiry day is a trading holiday it moves to the PREVIOUS trading
 *     day (e.g. 24 Nov 2026 Guru Nanak Jayanti -> Mon 23 Nov 2026).
 *
 * The old code hard-coded "last Thursday" (and Wed/Tue/Mon weeklies per index),
 * which has been wrong for NSE since Sep 2025.
 *
 * Mirror of app/lib/core/expiry_calendar.dart; keep the two in step.
 */
import { INDIAN_HOLIDAYS_2026 } from "./market_hours.ts";

export type Exchange = "NSE" | "BSE";

const TUESDAY = 2;
const THURSDAY = 4;

/// Exchange holidays that fall on the same date every year. Covers the years
/// whose full list is not in INDIAN_HOLIDAYS_2026 yet (e.g. 26 Jan 2027).
const FIXED_HOLIDAYS_MMDD = new Set(["01-26", "05-01", "08-15", "10-02", "12-25"]);

/// Default holiday set: the published 2026 list. Callers that can read
/// `market_holidays` should pass that set instead.
export const DEFAULT_HOLIDAYS: ReadonlySet<string> = INDIAN_HOLIDAYS_2026;

function iso(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/// True when [isoDate] (YYYY-MM-DD) is a weekday and not an exchange holiday.
export function isTradingDay(isoDate: string, holidays: ReadonlySet<string> = DEFAULT_HOLIDAYS): boolean {
  const [y, m, d] = isoDate.split("-").map(Number);
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  if (dow === 0 || dow === 6) return false;
  if (holidays.has(isoDate)) return false;
  return !FIXED_HOLIDAYS_MMDD.has(isoDate.slice(5));
}

/// [isoDate] itself if it is a trading day, else the closest earlier one.
export function rollBackToTradingDay(isoDate: string, holidays: ReadonlySet<string> = DEFAULT_HOLIDAYS): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  for (let i = 0; i < 10; i++) {
    const s = iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
    if (isTradingDay(s, holidays)) return s;
    t.setUTCDate(t.getUTCDate() - 1);
  }
  return isoDate;
}

/// Exchange an underlying's derivatives trade on.
export function exchangeFor(underlying: string): Exchange {
  const u = underlying.toUpperCase().replace(/^(NSE:|BSE:)/, "");
  return u === "SENSEX" || u === "BANKEX" || u === "SENSEX50" || u === "^BSESN" ? "BSE" : "NSE";
}

/// Only NIFTY (NSE, Tuesday) and SENSEX (BSE, Thursday) list weekly options.
export function hasWeeklyOptions(underlying: string): boolean {
  const u = underlying.toUpperCase().replace(/^(NSE:|BSE:)/, "");
  return u === "NIFTY" || u === "NIFTY50" || u === "^NSEI" || u === "SENSEX" || u === "^BSESN";
}

/// Monthly expiry (ISO date) for [month] (1-12) of [year].
export function monthlyExpiry(
  year: number,
  month: number,
  exchange: Exchange = "NSE",
  holidays: ReadonlySet<string> = DEFAULT_HOLIDAYS,
): string {
  const target = exchange === "BSE" ? THURSDAY : TUESDAY;
  const last = new Date(Date.UTC(year, month, 0)); // last day of month
  const diff = (last.getUTCDay() - target + 7) % 7;
  return rollBackToTradingDay(iso(year, month, last.getUTCDate() - diff), holidays);
}

/// Today's date in IST and whether today's 15:30 IST close has passed.
function istToday(now: Date): { today: string; afterClose: boolean } {
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
  const today = iso(ist.getUTCFullYear(), ist.getUTCMonth() + 1, ist.getUTCDate());
  const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  return { today, afterClose: minutes >= 15 * 60 + 30 };
}

function isLive(expiry: string, now: Date): boolean {
  const { today, afterClose } = istToday(now);
  return expiry > today || (expiry === today && !afterClose);
}

/// Next [count] monthly expiries that have not expired yet.
export function upcomingMonthlyExpiries(
  underlying: string,
  count = 3,
  now: Date = new Date(),
  holidays: ReadonlySet<string> = DEFAULT_HOLIDAYS,
): string[] {
  const exchange = exchangeFor(underlying);
  const { today } = istToday(now);
  let [y, m] = today.split("-").map(Number);
  const out: string[] = [];
  for (let i = 0; out.length < count && i < 24; i++) {
    const e = monthlyExpiry(y, m, exchange, holidays);
    if (isLive(e, now)) out.push(e);
    m++;
    if (m > 12) { m = 1; y++; }
  }
  return out;
}

/// Next [count] option expiries: weekly for NIFTY/SENSEX, monthly otherwise.
export function upcomingOptionExpiries(
  underlying: string,
  count = 4,
  now: Date = new Date(),
  holidays: ReadonlySet<string> = DEFAULT_HOLIDAYS,
): string[] {
  if (!hasWeeklyOptions(underlying)) return upcomingMonthlyExpiries(underlying, Math.min(count, 3), now, holidays);
  const target = exchangeFor(underlying) === "BSE" ? THURSDAY : TUESDAY;
  const { today } = istToday(now);
  const [y, m, d] = today.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  const out: string[] = [];
  for (let i = 0; out.length < count && i < 120; i++) {
    if (t.getUTCDay() === target) {
      const e = rollBackToTradingDay(iso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()), holidays);
      if (isLive(e, now) && !out.includes(e)) out.push(e);
    }
    t.setUTCDate(t.getUTCDate() + 1);
  }
  return out;
}
