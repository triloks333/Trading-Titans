/*
 * F&O price estimation. A direct port of app/lib/core/option_pricing.dart, which
 * is itself the same model as `bs()` / `futurePrice()` in
 * supabase/functions/execute-pending-orders.
 *
 * Why estimate at all: there is no live options feed in this product. Both the
 * chain and the fill engine price a contract by putting the live SPOT through
 * Black-Scholes, which is deliberate — it means the premium a user is shown is
 * the premium the engine will charge, so an order cannot fill at a number that
 * was never on screen. The constants below must therefore stay identical to the
 * Dart and Deno copies; if the web used a different volatility, a web user's
 * position would be marked at a different price from the same position viewed on
 * the phone.
 *
 * ponytail: a flat 25% implied volatility for every underlying, matching the
 * other two copies. The ceiling is accuracy — real index IV is nearer 12% and
 * single-stock IV runs 25-45%, so the level can sit well away from the exchange's
 * own (DIXON 15000 CE: ~₹419 modelled against ₹273 real). The upgrade path is an
 * IV per underlying/expiry solved from the daily NSE bhavcopy close and shared by
 * all three copies. Do not fix it here alone: display and fill must move together
 * or a limit order starts filling at a price the user never saw.
 */

const RISK_FREE_RATE = 0.065
const IMPLIED_VOL = 0.25

/** Abramowitz-Stegun approximation of the standard normal CDF. */
function normalCdf(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x))
  const d = 0.3989422804 * Math.exp((-x * x) / 2)
  const p =
    d *
    t *
    (0.31938153 +
      t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
  return x >= 0 ? 1 - p : p
}

function blackScholes(
  optionType: string,
  spot: number,
  strike: number,
  tYears: number,
): number {
  if (spot <= 0 || strike <= 0) return 0.05
  const intrinsic = optionType === 'CE' ? Math.max(0, spot - strike) : Math.max(0, strike - spot)
  if (tYears <= 0) {
    // At or past expiry the premium is pure intrinsic value.
    return Math.max(0.05, Math.round(intrinsic * 100) / 100)
  }
  const sqrtT = Math.sqrt(tYears)
  const d1 =
    (Math.log(spot / strike) + (RISK_FREE_RATE + 0.5 * IMPLIED_VOL * IMPLIED_VOL) * tYears) /
    (IMPLIED_VOL * sqrtT)
  const d2 = d1 - IMPLIED_VOL * sqrtT
  const discount = strike * Math.exp(-RISK_FREE_RATE * tYears)
  const price =
    optionType === 'CE'
      ? spot * normalCdf(d1) - discount * normalCdf(d2)
      : discount * normalCdf(-d2) - spot * normalCdf(-d1)
  // Floored at 5 paise and intrinsic value, rounded to paise.
  return Math.max(0.05, Math.max(intrinsic, Math.round(price * 100) / 100))
}

export function optionPremium({
  optionType,
  spot,
  strike,
  daysToExpiry,
}: {
  optionType: string
  spot: number
  strike: number
  daysToExpiry: number
}): number {
  return blackScholes(optionType, spot, strike, Math.max(0.0001, daysToExpiry) / 365)
}

/** Futures price = spot plus cost of carry to expiry. */
export function futurePrice({
  spot,
  daysToExpiry,
}: {
  spot: number
  daysToExpiry: number
}): number {
  if (spot <= 0 || daysToExpiry <= 0) return spot
  return spot * (1 + RISK_FREE_RATE * (daysToExpiry / 365))
}

/** Calendar days from now until [expiry]; negative once past. */
export function daysToExpiry(expiry: string | null | undefined): number {
  if (!expiry) return 0
  const isoStr = expiry.includes('T') ? expiry : `${expiry}T15:30:00+05:30`
  const ms = new Date(isoStr).getTime() - Date.now()
  return Number.isNaN(ms) ? 0 : ms / 86_400_000
}
