import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import { CURRENCY_SYMBOL as SYMBOLS, currencyFor as currencyOf, type Currency as Ccy } from './currency'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/*
 * Money formatting mirrors app/lib/core/money.dart: the wallet is held in rupees
 * and displayed in the Indian numbering system (lakh/crore grouping), which
 * `en-IN` gives for free — 2000000 renders as 20,00,000 and not 2,000,000.
 */
const inr0 = new Intl.NumberFormat('en-IN', {
  maximumFractionDigits: 0,
})
const inr2 = new Intl.NumberFormat('en-IN', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

// Currency identity lives in ./currency, which stays import-free so the position
// model can use it without dragging clsx in. Re-exported here so call sites have
// one place to import money helpers from.
export { CURRENCY_SYMBOL, currencyFor, localeFor, type Currency } from './currency'

// Dollars group in thousands, rupees in lakh and crore. Using en-IN for both
// would render $1,00,000 for a hundred thousand dollars.
const usd0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 })
const usd2 = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

/** A wallet, portfolio or P&L figure in rupees. */
export function money(value: number | null | undefined, decimals: 0 | 2 = 0) {
  const n = value ?? 0
  return `₹${(decimals === 2 ? inr2 : inr0).format(n)}`
}

/** Same, with an explicit sign — for anything that can be a credit or a debit. */
export function signedMoney(value: number | null | undefined, decimals: 0 | 2 = 2) {
  const n = value ?? 0
  const sign = n < 0 ? '-' : '+'
  return `${sign}${money(Math.abs(n), decimals)}`
}

/**
 * A figure in an explicit currency. Sign, if shown, goes BEFORE the symbol, so a
 * loss reads "-₹3,654" and never "₹-3,654".
 */
export function inCurrency(
  value: number | null | undefined,
  currency: Ccy,
  decimals: 0 | 2 = 2,
  signed = false,
) {
  const n = value ?? 0
  const fmt =
    currency === 'USD' ? (decimals === 2 ? usd2 : usd0) : decimals === 2 ? inr2 : inr0
  const body = `${SYMBOLS[currency]}${fmt.format(Math.abs(n))}`
  if (signed) return `${n < 0 ? '-' : '+'}${body}`
  return n < 0 ? `-${body}` : body
}

/**
 * A price or value belonging to one instrument, formatted in that instrument's
 * own currency. Use this for anything read off a quote or a position; use
 * {@link money} only for the wallet and for portfolio-wide rupee totals.
 */
export function instrumentMoney(
  value: number | null | undefined,
  market: string | null | undefined,
  decimals: 0 | 2 = 2,
) {
  return inCurrency(value, currencyOf(market), decimals)
}

/** Signed variant of {@link instrumentMoney}, for per-position P&L. */
export function signedInstrumentMoney(
  value: number | null | undefined,
  market: string | null | undefined,
  decimals: 0 | 2 = 2,
) {
  return inCurrency(value, currencyOf(market), decimals, true)
}

export function percent(value: number | null | undefined, decimals = 2) {
  const n = value ?? 0
  return `${n >= 0 ? '+' : ''}${n.toFixed(decimals)}%`
}

/**
 * Compact rupee figure for tight spaces: 2000000 -> "₹20L", 15000000 -> "₹1.5Cr".
 * Indian units, because "₹2M" means nothing to the audience.
 */
export function compactMoney(value: number | null | undefined) {
  const n = Math.abs(value ?? 0)
  const sign = (value ?? 0) < 0 ? '-' : ''
  if (n >= 1_00_00_000) return `${sign}₹${(n / 1_00_00_000).toFixed(n % 1_00_00_000 === 0 ? 0 : 1)}Cr`
  if (n >= 1_00_000) return `${sign}₹${(n / 1_00_000).toFixed(n % 1_00_000 === 0 ? 0 : 1)}L`
  if (n >= 1_000) return `${sign}₹${(n / 1_000).toFixed(n % 1_000 === 0 ? 0 : 1)}K`
  return `${sign}₹${inr0.format(n)}`
}

export function shortDate(iso: string | null | undefined) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: '2-digit',
  })
}

export function timeAgo(iso: string | null | undefined) {
  if (!iso) return '—'
  const secs = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (secs < 60) return 'just now'
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`
  if (secs < 604800) return `${Math.floor(secs / 86400)}d ago`
  return shortDate(iso)
}
