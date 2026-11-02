/*
 * Domain shapes for the tables the web app reads. Hand-written rather than
 * generated so only the columns actually used are declared — the live schema has
 * 60+ tables, most of which (instruments at 201k rows, nse_fo_bhavcopy at 730k,
 * and the unrelated kv_* set belonging to another product) the web app never
 * touches.
 */

export interface Profile {
  id: string
  email: string
  name: string
  phone?: string | null
  wallet_balance: number
  total_realized_pnl: number
  subscription_active: boolean
  plan: string | null
  is_admin: boolean | null
  referral_code: string | null
  referred_by: string | null
  challenge_baseline_capital: number
  converted_at: string | null
  total_xp: number | null
  /**
   * Residency, from onboarding. `india` | `outside_india` | null, where null
   * predates the question. This — not `display_currency` — decides which currency
   * a purchase is billed in; see `billingCurrencyFor` in ./payments.
   */
  location: string | null
  /** Cosmetic preference for how figures are rendered. Never a billing input. */
  display_currency: string | null
  created_at: string
}

export interface Holding {
  id: string
  user_id: string
  symbol: string
  quantity: number
  avg_price: number
  market: string | null
  created_at: string
}

export interface Order {
  id: string
  user_id: string
  symbol: string
  name: string | null
  side: 'buy' | 'sell' | string
  quantity: number
  price: number | null
  /** The requested limit. Null for a market order — `price` becomes the fill. */
  limit_price: number | null
  total: number | null
  status: string
  market: string | null
  order_type: string | null
  instrument_type: string | null
  strike_price: number | null
  option_type: string | null
  expiry_date: string | null
  /** Written GROSS by the engine: charges are separate columns, never netted in. */
  realized_pnl: number | null
  brokerage: number | null
  stamp_duty: number | null
  tax_charges: number | null
  total_charges: number | null
  /** Price in the instrument's own currency; set for us_stock only. */
  native_price: number | null
  native_currency: string | null
  fx_rate: number | null
  created_at: string
  executed_at: string | null
}

export interface WalletTransaction {
  id: number
  user_id: string
  amount: number
  balance_before: number
  balance_after: number
  kind: string | null
  description: string | null
  created_at: string
}

export interface Quote {
  symbol: string
  name?: string | null
  price: number
  previous_close?: number | null
  change?: number | null
  change_pct?: number | null
  currency?: string | null
  market?: string | null
  day_low?: number | null
  day_high?: number | null
  open?: number | null
  /*
   * No `volume` here on purpose: `quotes_cache` has no such column, so declaring
   * one made the type promise data the table cannot supply. The market-quote
   * endpoint does return volume, but that is a different shape from a cached row.
   */
  source?: string | null
  updated_at?: string | null
}

export interface Challenge {
  key: string
  title: string
  description: string
  category: string | null
  reward_amount: number
  xp: number | null
  is_active: boolean | null
  sort_order: number | null
}

export interface Candle {
  t: number
  o: number
  h: number
  l: number
  c: number
}

export interface HistoryResponse {
  symbol: string
  points: { t: number; v: number }[]
  candles: Candle[]
}

/*
 * The old `Position extends Holding` shape lived here and carried a single `ltp`,
 * `invested` and `pnl`. It has been replaced by lib/positions.ts, which keeps a
 * position's own currency separate from the rupee figures used for portfolio
 * totals — the flat shape could not express a US position without mixing the two,
 * and had no room for shorts, lots or day P&L.
 */
