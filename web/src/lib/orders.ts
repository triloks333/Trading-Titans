import { supabase, functionsBase } from './supabase'

/*
 * Order placement.
 *
 * Everything here is a thin call to the `place-order` edge function, and that is
 * the whole design. The browser does NOT compute what a trade costs, whether the
 * wallet can afford it, what lot size applies, or what the fill price should be.
 * All of that lives server-side, in `place-order` (validation, rate limiting,
 * price warming) and `execute-pending-orders` (charges, margin, fills, wallet).
 *
 * The alternative — reimplementing the money logic in TypeScript for the web —
 * would give this product a third copy of it, after Dart and Deno. The two that
 * already exist have drifted from each other more than once, most recently on
 * whether intraday charge rates apply. A third would drift too, and the failure
 * mode is a user's balance disagreeing with itself depending on which client they
 * used. The charge helper in lib/charges.ts is a *preview* only, and is checked
 * against real engine output precisely so that stays true.
 *
 * `place-order` authenticates from the JWT and ignores any user id in the body,
 * so a web client cannot place an order for anybody else.
 */

export type OrderSide = 'buy' | 'sell'
export type OrderInstrument = 'EQUITY' | 'FUTURE' | 'OPTION'

export interface PlaceOrderRequest {
  symbol: string
  market: string
  side: OrderSide
  instrumentType: OrderInstrument
  /** Units, not lots. For F&O this must already be quantity x lot size. */
  quantity: number
  /** True for a market order; false requires `price`. */
  isMarket: boolean
  /** The limit price. Ignored when `isMarket`. */
  price?: number
  /** Closing an existing position: stops the engine opening a reverse one. */
  isExitOrder?: boolean
  optionType?: 'CE' | 'PE' | null
  strikePrice?: number | null
  expiryDate?: string | null
}

export interface PlaceOrderResult {
  ok: boolean
  /** Server-supplied message, safe to show the user verbatim. */
  message: string
  orderId?: string
  status?: string
}

/**
 * Places an order and returns what the server said.
 *
 * Deliberately never throws for a rejected order: "insufficient funds" and
 * "market closed" are ordinary outcomes a user needs to read, not exceptions. Only
 * a missing session is treated as programmer error.
 */
export async function placeOrder(req: PlaceOrderRequest): Promise<PlaceOrderResult> {
  const { data: sessionData } = await supabase.auth.getSession()
  const token = sessionData.session?.access_token
  if (!token) return { ok: false, message: 'You are signed out. Please sign in again.' }

  try {
    const res = await fetch(`${functionsBase}/place-order`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // The USER's token, not the anon key: the function derives the account
        // from it, so this is what makes the order belong to whoever is signed in.
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        symbol: req.symbol,
        market: req.market,
        side: req.side,
        instrumentType: req.instrumentType,
        quantity: req.quantity,
        isMarket: req.isMarket,
        // Only send a price for a limit order. Sending one for a market order
        // would be stored as a trigger threshold it should not have.
        ...(req.isMarket ? {} : { price: req.price }),
        ...(req.isExitOrder ? { isExitOrder: true } : {}),
        ...(req.optionType ? { optionType: req.optionType } : {}),
        ...(req.strikePrice != null ? { strikePrice: req.strikePrice } : {}),
        ...(req.expiryDate ? { expiryDate: req.expiryDate } : {}),
      }),
    })

    const body = (await res.json().catch(() => ({}))) as {
      error?: string
      message?: string
      order?: { id?: string; status?: string }
      id?: string
      status?: string
    }

    if (!res.ok) {
      return {
        ok: false,
        message:
          body.error ??
          (res.status === 429
            ? 'Too many orders in a short time. Please wait a moment.'
            : `Order rejected (${res.status}).`),
      }
    }

    const status = body.order?.status ?? body.status
    return {
      ok: true,
      orderId: body.order?.id ?? body.id,
      status,
      message:
        status === 'executed'
          ? 'Order executed.'
          : 'Order placed. It will fill when the market reaches your price.',
    }
  } catch {
    return { ok: false, message: 'Could not reach the server. Check your connection.' }
  }
}

/**
 * Calls a server-side order endpoint with the signed-in user's token.
 *
 * Cancel and modify used to be direct table updates. They could not stay that
 * way: the RLS policy that allowed them (`USING (auth_uid() = user_id)`, with no
 * WITH CHECK and no column restriction) made "edit my own order" and "rewrite my
 * own realized_pnl" the same privilege. Both now go through functions that
 * validate ownership and state, and the direct grant has been withdrawn.
 *
 * Like placeOrder, a rejected request is an ordinary result rather than a throw:
 * "already filled" is something the user needs to read.
 */
async function callOrderFunction(
  name: 'cancel-order' | 'modify-order',
  payload: Record<string, unknown>,
  fallback: string,
): Promise<PlaceOrderResult> {
  const { data: sessionData } = await supabase.auth.getSession()
  const token = sessionData.session?.access_token
  if (!token) return { ok: false, message: 'You are signed out. Please sign in again.' }

  try {
    const res = await fetch(`${functionsBase}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(payload),
    })
    const body = (await res.json().catch(() => ({}))) as { error?: string; message?: string }
    if (!res.ok) {
      return {
        ok: false,
        message:
          body.error ??
          (res.status === 429
            ? 'Too many changes in a short time. Please wait a moment.'
            : `Request rejected (${res.status}).`),
      }
    }
    return { ok: true, message: body.message ?? fallback }
  } catch {
    return { ok: false, message: 'Could not reach the server. Check your connection.' }
  }
}

/** Cancels a pending order. */
export async function cancelOrder(orderId: string): Promise<PlaceOrderResult> {
  const r = await callOrderFunction('cancel-order', { orderId }, 'Order cancelled.')
  return r.ok ? { ...r, orderId } : r
}

/**
 * Changes the limit price and/or quantity of a pending order.
 *
 * The server keeps `price` and `limit_price` in step and recomputes `total`. This
 * used to be done here, and `total` was left stale on a quantity-only change.
 */
export async function modifyOrder(
  orderId: string,
  changes: { quantity?: number; limitPrice?: number },
): Promise<PlaceOrderResult> {
  const payload: Record<string, unknown> = { orderId }
  if (changes.quantity != null && changes.quantity > 0) payload.quantity = changes.quantity
  if (changes.limitPrice != null && changes.limitPrice > 0) payload.price = changes.limitPrice
  if (Object.keys(payload).length === 1) {
    return { ok: false, message: 'Nothing to change.' }
  }

  const r = await callOrderFunction('modify-order', payload, 'Order updated.')
  return r.ok ? { ...r, orderId } : r
}
