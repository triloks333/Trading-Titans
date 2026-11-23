/**
 * Shared utility for pricing and parsing F&O (Futures & Options) contracts.
 * Provides Black-Scholes pricing, Days-to-Expiry calculation, and contract symbol parsing.
 */
import { exchangeFor, monthlyExpiry } from "./expiry_calendar.ts";

export interface ParsedDerivative {
  isDerivative: boolean;
  type: "OPTION" | "FUTURE";
  symbol: string;
  underlying: string;
  expiry?: string;
  strike?: number;
  optionType?: "CE" | "PE";
  month?: string;
}

/// Monthly expiry for a "<YY><MON>" contract. Delegates to the shared expiry
/// calendar (last Tuesday on NSE, last Thursday on BSE, moved back over
/// holidays); this used to hard-code "last Thursday", wrong since Sep 2025.
function expiryFromMonthYear(year2: string, month3: string, underlying = ""): string {
  const months: Record<string, number> = {
    JAN: 1, FEB: 2, MAR: 3, APR: 4, MAY: 5, JUN: 6,
    JUL: 7, AUG: 8, SEP: 9, OCT: 10, NOV: 11, DEC: 12,
  };
  const m = months[month3.toUpperCase()] ?? 1;
  const y = 2000 + parseInt(year2, 10);
  return monthlyExpiry(y, m, exchangeFor(underlying));
}

/**
 * Parses derivative symbol formats:
 * Options: ^NSEI-2026-10-06-21850-PE, RELIANCE-2026-10-06-2500-CE, RELIANCE26DEC640CE
 * Futures: RELIANCE26DECFUT, RELIANCE OCT FUT, NIFTY OCT FUT, RELIANCE-FUT, NIFTYFUT
 */
export function parseDerivativeSymbol(rawSymbol: string): ParsedDerivative | null {
  if (!rawSymbol) return null;
  const s = rawSymbol.trim();

  // 1. Option format: <underlying>-<YYYY-MM-DD>-<strike>-<CE|PE>
  const optMatch = s.match(/^(.+)-(\d{4}-\d{2}-\d{2})-(\d+(?:\.\d+)?)-(CE|PE)$/i);
  if (optMatch) {
    const underlying = optMatch[1].toUpperCase();
    const expiry = optMatch[2];
    const strike = parseFloat(optMatch[3]);
    const optionType = optMatch[4].toUpperCase() as "CE" | "PE";
    return {
      isDerivative: true,
      type: "OPTION",
      symbol: s,
      underlying,
      expiry,
      strike,
      optionType,
    };
  }

  // 2. Compact NSE Future format: <underlying><YY><MON>FUT (e.g. RELIANCE26DECFUT, NIFTY26OCTFUT)
  const compactFutMatch = s.match(/^(?:NSE:|BSE:)?(\^?[A-Za-z&-]+)(\d{2})([A-Za-z]{3})FUT$/i);
  if (compactFutMatch) {
    const underlying = compactFutMatch[1].toUpperCase();
    const yr = compactFutMatch[2];
    const mon = compactFutMatch[3].toUpperCase();
    const expiry = expiryFromMonthYear(yr, mon, underlying);
    return {
      isDerivative: true,
      type: "FUTURE",
      symbol: s,
      underlying,
      month: mon,
      expiry,
    };
  }

  // 3. Compact NSE Option format: <underlying><YY><MON><strike><CE|PE> (e.g. RELIANCE26DEC640CE)
  const compactOptMatch = s.match(/^(?:NSE:|BSE:)?(\^?[A-Za-z&-]+)(\d{2})([A-Za-z]{3})(\d+(?:\.\d+)?)(CE|PE)$/i);
  if (compactOptMatch) {
    const underlying = compactOptMatch[1].toUpperCase();
    const yr = compactOptMatch[2];
    const mon = compactOptMatch[3].toUpperCase();
    const strike = parseFloat(compactOptMatch[4]);
    const optionType = compactOptMatch[5].toUpperCase() as "CE" | "PE";
    const expiry = expiryFromMonthYear(yr, mon, underlying);
    return {
      isDerivative: true,
      type: "OPTION",
      symbol: s,
      underlying,
      month: mon,
      expiry,
      strike,
      optionType,
    };
  }

  // 4. Space-separated Future with optional day, month, and optional 2-digit/4-digit year:
  // e.g. "RELIANCE 29 Dec 26 FUT", "RELIANCE 26 DEC FUT", "RELIANCE DEC 26 FUT", "RELIANCE DEC FUT", "NIFTY OCT FUT"
  const spaceFutMatch = s.match(
    /^(?:NSE:|BSE:)?(\^?[A-Za-z&-]+)\s+(?:(\d{1,2})\s+)?([A-Za-z]{3})(?:\s+(\d{2,4}))?\s+FUT$/i
  );
  if (spaceFutMatch) {
    const underlying = spaceFutMatch[1].toUpperCase();
    const dayOrYr = spaceFutMatch[2];
    const mon = spaceFutMatch[3].toUpperCase();
    const yrGroup = spaceFutMatch[4];

    let year = new Date().getFullYear();
    if (yrGroup) {
      const parsedYr = parseInt(yrGroup, 10);
      year = parsedYr < 100 ? 2000 + parsedYr : parsedYr;
    } else if (dayOrYr && parseInt(dayOrYr, 10) >= 24 && parseInt(dayOrYr, 10) <= 35) {
      year = 2000 + parseInt(dayOrYr, 10);
    }
    const expiry = expiryFromMonthYear(String(year % 100).padStart(2, "0"), mon, underlying);
    return {
      isDerivative: true,
      type: "FUTURE",
      symbol: s,
      underlying,
      month: mon,
      expiry,
    };
  }

  // 5. Simple futures format: <underlying>-FUT or <underlying> FUT or <underlying>FUT (e.g. RELIANCE-FUT, NIFTY-FUT)
  const simpleFutMatch = s.match(/^(?:NSE:|BSE:)?(\^?[A-Za-z&-]+)(?:-|\s+)?FUT$/i);
  if (simpleFutMatch && !s.includes("FUTURE")) {
    return {
      isDerivative: true,
      type: "FUTURE",
      symbol: s,
      underlying: simpleFutMatch[1].toUpperCase(),
    };
  }

  return null;
}

/**
 * Standard Normal Cumulative Distribution Function (Abramowitz & Stegun approximation)
 */
export function normalCDF(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804 * Math.exp(-x * x / 2);
  const p = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x >= 0 ? 1 - p : p;
}

/**
 * Black-Scholes formula for European options pricing.
 * @param spot Underlying asset price
 * @param strike Strike price
 * @param T Time to expiry in years
 * @param type 'CE' (Call) or 'PE' (Put)
 * @param r Annual risk-free interest rate (default 6.5%)
 * @param sigma Annualized implied volatility (default 25%)
 */
export function blackScholes(
  spot: number,
  strike: number,
  T: number,
  type: "CE" | "PE",
  r = 0.065,
  sigma = 0.25
): number {
  if (spot <= 0 || strike <= 0) return 0.05;
  const time = Math.max(0.0001, T);
  const d1 = (Math.log(spot / strike) + (r + 0.5 * sigma * sigma) * time) / (sigma * Math.sqrt(time));
  const d2 = d1 - sigma * Math.sqrt(time);

  let price = 0.0;
  if (type === "CE") {
    price = spot * normalCDF(d1) - strike * Math.exp(-r * time) * normalCDF(d2);
  } else {
    price = strike * Math.exp(-r * time) * normalCDF(-d2) - spot * normalCDF(-d1);
  }

  const intrinsic = type === "CE" ? Math.max(0, spot - strike) : Math.max(0, strike - spot);
  return Math.max(0.05, Math.max(intrinsic, Math.round(price * 100) / 100));
}

/**
 * Calculates days to expiry from an ISO date string (YYYY-MM-DD), expiring at 15:30 IST.
 */
export function getDaysToExpiry(expiryDateStr: string, fromDate = new Date()): number {
  const expiryTime = Date.parse(`${expiryDateStr}T15:30:00+05:30`);
  if (!Number.isFinite(expiryTime)) return 0.01;
  const diffMs = expiryTime - fromDate.getTime();
  const days = diffMs / (24 * 60 * 60 * 1000);
  return Math.max(0.0001, days);
}

/**
 * Calculates futures price based on spot price, days to expiry, and cost of carry.
 */
export function calculateFuturePrice(spot: number, daysLeft: number, r = 0.055): number {
  const price = spot * (1 + r * (Math.max(0, daysLeft) / 365.0));
  return Math.round(price * 100) / 100;
}
