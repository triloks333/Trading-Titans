import { useQuery } from '@tanstack/react-query'
import { supabase, functionsBase } from './supabase'
import { inCurrency } from './format'

/*
 * Checkout, from the browser's side.
 *
 * The split of responsibility here is the whole security model, so it is worth
 * stating plainly:
 *
 *   - the browser sends a SKU, never an amount. Price comes from
 *     `plan_catalogue` server-side, so editing a number in devtools buys nothing.
 *   - the browser never grants anything. Razorpay's success callback is a UI
 *     event, not proof of payment — it can be forged by anyone who can open a
 *     console. Cash and tiers are granted only by the `razorpay-webhook` edge
 *     function, after verifying an HMAC signature from Razorpay.
 *
 * That second point is why `startCheckout` finishes by *polling* for the grant
 * rather than applying it. The webhook usually lands within a second or two of
 * the payment, but it is a separate network path and can be slower, so the UI
 * waits for the database to confirm instead of taking the client's word for it.
 */

export type PlanKind = 'one_time' | 'subscription'
export type PlanTier = 'topup' | 'pro' | 'titan'
export type BillingInterval = 'monthly' | 'annual'

export interface Plan {
  sku: string
  tier: PlanTier
  kind: PlanKind
  title: string
  /** Rupee price in paise. */
  price_paise: number
  /**
   * Dollar price in cents. Null for a SKU with no dollar price yet, which the
   * server refuses to sell in USD rather than guessing one.
   */
  price_usd_cents: number | null
  billing_interval: BillingInterval | null
  cash_grant: number
  monthly_stipend: number
  is_active: boolean
  sort_order: number
}

export type BillingCurrency = 'INR' | 'USD'

/**
 * Which currency an account is charged in.
 *
 * Residency, NOT `display_currency`. Eight live accounts sit in India with a
 * dollar display; that setting governs how figures are drawn and nothing else, so
 * letting it pick a billing currency would charge a rupee customer in dollars
 * because they preferred the look of them. A null location predates the question
 * and means India.
 *
 * Must stay identical to the rule in `create-payment-order`, which resolves this
 * server-side and is authoritative. This copy exists so the price on the card is
 * the price on the invoice; if the two ever diverge, the user is quoted one number
 * and charged another.
 */
export function billingCurrencyFor(
  location: string | null | undefined,
): BillingCurrency {
  return location === 'outside_india' ? 'USD' : 'INR'
}

/** The minor-unit price in [currency], or null when this plan has none. */
export function planMinor(plan: Plan, currency: BillingCurrency): number | null {
  return currency === 'USD' ? plan.price_usd_cents : plan.price_paise
}

/**
 * The exact amount that will be charged, formatted.
 *
 * The two prices are independent price points, each fixed to match its own
 * Razorpay plan, so neither is ever converted into the other — a plan's amount is
 * immutable, and a converted figure would show one price and charge another.
 * Cents appear only when there are any: rupee prices are whole, most dollar ones
 * are not.
 */
export function planPrice(plan: Plan, currency: BillingCurrency): string {
  const minor = planMinor(plan, currency)
  // No price in this currency: show the rupee one rather than "$0", which would
  // advertise something the server will not sell.
  if (minor === null) return planPrice(plan, 'INR')
  const major = minor / 100
  return inCurrency(major, currency, Number.isInteger(major) ? 0 : 2)
}

/**
 * The catalogue. Readable by anyone — `plan_catalogue` has a `SELECT true`
 * policy — and deliberately the only place prices are written down. Hardcoding
 * them in the page would give this product a third copy of the price list after
 * Dart and SQL, and the copies drift.
 */
export async function fetchPlans(): Promise<Plan[]> {
  const { data, error } = await supabase
    .from('plan_catalogue')
    .select('*')
    .eq('is_active', true)
    .order('sort_order')
  if (error) throw new Error(error.message)
  return (data ?? []) as Plan[]
}

/**
 * The monetisation kill switch, read from `app_flags`.
 *
 * Every paid surface checks this, so the whole thing can be switched off from the
 * dashboard without a release — which is what makes it safe to ship the checkout
 * before the Terms rewrite and re-consent are done. Defaults to OFF: a failed
 * read must hide the paywall, never reveal it.
 */
export function useMonetisationEnabled() {
  return useQuery({
    queryKey: ['flag', 'monetization_enabled'],
    staleTime: 60_000,
    queryFn: async (): Promise<boolean> => {
      const { data, error } = await supabase
        .from('app_flags')
        .select('enabled')
        .eq('key', 'monetization_enabled')
        .maybeSingle()
      if (error) return false
      return data?.enabled === true
    },
  })
}

// ── Razorpay Checkout ────────────────────────────────────────────────────────

interface RazorpayInstance {
  open: () => void
  on: (event: string, handler: (payload: unknown) => void) => void
}

interface RazorpayOptions {
  key: string
  name: string
  description?: string
  order_id?: string
  subscription_id?: string
  amount?: number
  currency?: string
  prefill?: { email?: string; name?: string }
  theme?: { color?: string }
  handler?: (response: Record<string, string>) => void
  modal?: { ondismiss?: () => void }
}

declare global {
  interface Window {
    Razorpay?: new (options: RazorpayOptions) => RazorpayInstance
  }
}

const CHECKOUT_SRC = 'https://checkout.razorpay.com/v1/checkout.js'

/**
 * Loads Razorpay's script once, on demand.
 *
 * Not in index.html: a third-party script on every page load costs every user
 * who never opens the pricing page, and this one is only needed at the moment
 * someone decides to buy.
 */
function loadCheckout(): Promise<void> {
  if (window.Razorpay) return Promise.resolve()

  const existing = document.querySelector<HTMLScriptElement>(
    `script[src="${CHECKOUT_SRC}"]`,
  )
  if (existing) {
    // A second click while the first load is still in flight must wait for that
    // load, not start another one.
    return new Promise((resolve, reject) => {
      existing.addEventListener('load', () => resolve())
      existing.addEventListener('error', () =>
        reject(new Error('Could not load the payment window.')),
      )
    })
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = CHECKOUT_SRC
    script.async = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Could not load the payment window.'))
    document.head.appendChild(script)
  })
}

interface CheckoutSession {
  kind: PlanKind
  keyId: string
  orderId?: string
  subscriptionId?: string
  title: string
  currency?: BillingCurrency
  /**
   * Minor units of `currency` — paise for INR, cents for USD. The name is
   * inherited from the rupee-only version and kept so the two deploys did not have
   * to be simultaneous.
   */
  amountPaise: number
}

/** Asks the server to open a checkout for this SKU. The server sets the price. */
async function createSession(sku: string): Promise<CheckoutSession> {
  const { data: sessionData } = await supabase.auth.getSession()
  const token = sessionData.session?.access_token
  if (!token) throw new Error('You are signed out. Please sign in again.')

  const res = await fetch(`${functionsBase}/create-payment-order`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // The user's own token: the function derives the account from it, so a
      // purchase cannot be started on somebody else's behalf.
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ sku }),
  })

  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    // These messages are written server-side for a user to read: "you already
    // have an active subscription", "that plan is not available".
    throw new Error(body?.error ?? 'Could not start the payment.')
  }
  return body as CheckoutSession
}

/**
 * Waits for the webhook to actually apply the purchase.
 *
 * Returns false on timeout, which is not the same as failure — the money may
 * well have been taken and the grant may land a moment later. The caller says
 * so rather than claiming the purchase failed, because telling a user who has
 * just paid that nothing happened is the worse error.
 */
async function waitForGrant(
  session: CheckoutSession,
  timeoutMs = 25_000,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (session.kind === 'one_time' && session.orderId) {
      const { data } = await supabase
        .from('payment_orders')
        .select('credited_at')
        .eq('provider_order_id', session.orderId)
        .maybeSingle()
      if (data?.credited_at) return true
    } else if (session.subscriptionId) {
      const { data } = await supabase
        .from('subscriptions')
        .select('status')
        .eq('provider_subscription_id', session.subscriptionId)
        .maybeSingle()
      if (data?.status === 'active') return true
    }
    await new Promise((r) => setTimeout(r, 1500))
  }
  return false
}

export type CheckoutOutcome =
  /** Paid and the grant is visible in the database. */
  | { status: 'granted' }
  /** Paid, but the grant had not landed before we stopped waiting. */
  | { status: 'confirming' }
  /** The user closed the payment window without paying. */
  | { status: 'dismissed' }

/**
 * Runs a full checkout: create the order server-side, open Razorpay, then wait
 * for the webhook to confirm.
 *
 * Throws only for things that stopped the attempt from starting — signed out,
 * plan unavailable, script blocked. A user who simply changes their mind is a
 * `dismissed` outcome, not an exception.
 */
export async function startCheckout(
  sku: string,
  who: { email?: string | null; name?: string | null } = {},
): Promise<CheckoutOutcome> {
  const session = await createSession(sku)
  await loadCheckout()
  const Razorpay = window.Razorpay
  if (!Razorpay) throw new Error('Could not load the payment window.')

  return new Promise<CheckoutOutcome>((resolve, reject) => {
    // Guards the case where Razorpay fires both `handler` and `ondismiss`, which
    // would otherwise settle this promise twice and, worse, start two polls.
    let settled = false
    const settle = (fn: () => void) => {
      if (settled) return
      settled = true
      fn()
    }

    const rzp = new Razorpay({
      key: session.keyId,
      name: 'Trading Titans',
      description: session.title,
      ...(session.kind === 'subscription'
        ? { subscription_id: session.subscriptionId }
        : {
            order_id: session.orderId,
            amount: session.amountPaise,
            // Must match the order Razorpay already holds, which the server set
            // from the account's residency. Hardcoding 'INR' here made every
            // dollar-billed checkout fail validation.
            currency: session.currency ?? 'INR',
          }),
      prefill: { email: who.email ?? undefined, name: who.name ?? undefined },
      theme: { color: '#B8860B' },
      handler: () => {
        // Note what is NOT here: no grant, no wallet write, no "success" claim
        // based on this callback. All it does is start watching the database.
        settle(() => {
          void waitForGrant(session).then((granted) =>
            resolve({ status: granted ? 'granted' : 'confirming' }),
          )
        })
      },
      modal: {
        ondismiss: () => settle(() => resolve({ status: 'dismissed' })),
      },
    })

    rzp.on('payment.failed', (payload: unknown) => {
      const description =
        (payload as { error?: { description?: string } })?.error?.description ??
        'The payment did not go through. You have not been charged.'
      settle(() => reject(new Error(description)))
    })

    rzp.open()
  })
}
