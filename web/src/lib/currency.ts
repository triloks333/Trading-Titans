/*
 * Which currency an instrument's own prices are quoted in.
 *
 * Its own module, with no imports, for two reasons. It is domain knowledge rather
 * than presentation — the portfolio model needs it to avoid subtracting dollars
 * from rupees, long before anything is formatted. And keeping it free of `clsx`
 * and `tailwind-merge` (which lib/format.ts pulls in for `cn`) is what lets the
 * position model run under plain `node` in positions.check.ts.
 */

export type Currency = 'INR' | 'USD'

export const CURRENCY_SYMBOL: Record<Currency, string> = { INR: '₹', USD: '$' }

/**
 * The currency a market's prices are stored in.
 *
 * This is not cosmetic. `quotes_cache.price` for a `us_stock` row is dollars —
 * AAPL sits at 319.70, which is $319.70 and would be a nonsense rupee price —
 * whereas crypto is converted to rupees upstream by market-quote before it is
 * cached, and Indian equity is natively rupees. Treating every market as rupees,
 * which the first version of the web app did, understates a US price by roughly
 * the exchange rate and corrupts any P&L computed from it.
 */
export function currencyFor(market: string | null | undefined): Currency {
  return market === 'us_stock' ? 'USD' : 'INR'
}

/** Locale whose grouping suits the currency: lakh/crore for rupees, thousands for dollars. */
export function localeFor(currency: Currency): string {
  return currency === 'USD' ? 'en-US' : 'en-IN'
}
