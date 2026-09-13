import { useState } from 'react'
import { NavLink } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  BadgeCheck,
  CircleAlert,
  Gift,
  Loader2,
  Lock,
  Sparkles,
  Wallet,
} from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useMyTier } from '@/lib/tier'
import { supabase } from '@/lib/supabase'
import { LegalSheet } from '@/components/LegalSheet'
import { PRIVACY, TERMS, TERMS_VERSION, type LegalDoc } from '@/lib/legal'
import {
  billingCurrencyFor,
  fetchPlans,
  planMinor,
  planPrice,
  startCheckout,
  useMonetisationEnabled,
  type BillingCurrency,
  type BillingInterval,
  type Plan,
} from '@/lib/payments'
import { compactMoney, inCurrency, money, cn } from '@/lib/format'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  Skeleton,
  TierBadge,
} from '@/components/ui'

/**
 * Plans and top-ups.
 *
 * Prices, cash grants and stipends all come from `plan_catalogue` — nothing on
 * this page is written down in TypeScript. That is not tidiness: the price list
 * previously existed in Dart, in TS and in SQL, and the three drifted. The
 * database is now the only copy, and this page renders whatever it says.
 *
 * Every figure shown is GST-inclusive. That is a product decision (the user pays
 * the number on the card, with no surprise at the end) and it is recorded here
 * because a reader who assumes ex-GST will get the arithmetic wrong.
 *
 * Prices render in the account's BILLING currency, which comes from residency and
 * not from the display preference — see `billingCurrencyFor`. Nothing on this page
 * converts between the two: the rupee and dollar prices are separate price points
 * fixed to separate Razorpay plans.
 */
export function Plans() {
  const { session, profile, isGuest } = useAuth()
  const billing = billingCurrencyFor(profile?.location)
  const queryClient = useQueryClient()
  const monetisation = useMonetisationEnabled()
  const myTier = useMyTier(session?.user?.id)

  // Honours the ?sku= the Android app appends when it hands a purchase over.
  // The app sells monthly only, and links here for annual, so a link naming an
  // annual SKU has to open on the annual tab — otherwise the user taps "compare
  // yearly pricing" and lands on the monthly prices they just left.
  const [interval, setInterval] = useState<BillingInterval>(() =>
    new URLSearchParams(window.location.search).get('sku')?.endsWith('_annual')
      ? 'annual'
      : 'monthly',
  )
  const [busySku, setBusySku] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [reading, setReading] = useState<LegalDoc | null>(null)

  const plans = useQuery({ queryKey: ['plan-catalogue'], queryFn: fetchPlans })

  // Defence in depth. The nav entry is hidden when monetisation is off, but a
  // bookmark or a stale link must not reach a paywall either.
  if (monetisation.isSuccess && !monetisation.data) {
    return (
      <Card>
        <EmptyState
          icon={<Gift className="h-5 w-5" />}
          title="Everything is free"
          message="Trading Titans is completely free right now — there is nothing to buy. Finish challenges to earn extra demo cash instead."
          action={
            <NavLink to="/wallet">
              <Button variant="outline">Go to wallet</Button>
            </NavLink>
          }
        />
      </Card>
    )
  }

  async function buy(plan: Plan) {
    setError(null)
    setNotice(null)

    // A guest account cannot be recovered after sign-out, so anything bought on
    // one would vanish with it. Stop before the money, not after.
    if (isGuest) {
      setError(
        'Please make your account permanent first — a guest account cannot be recovered, and a purchase on it would be lost.',
      )
      return
    }

    setBusySku(plan.sku)
    try {
      // Consent to the payment terms, recorded at the moment of purchase.
      //
      // This is the point that matters: nobody should be charged under terms
      // they were not shown. Doing it here rather than as a blanket re-prompt is
      // deliberate — what changed in this revision are the payment, renewal and
      // refund clauses, and those only bind someone who actually pays. Users who
      // never buy anything do not need to re-accept a refund policy.
      //
      // Called directly rather than through `acceptTerms()` from the auth
      // context: that helper deliberately swallows failures so a bad network
      // cannot lock someone out of signing in. That is the right call there and
      // the wrong one here — if the consent did not record, we must not take the
      // money.
      const { error: consentError } = await supabase.rpc('accept_terms', {
        p_version: TERMS_VERSION,
      })
      if (consentError) {
        throw new Error(
          'We could not record your agreement to the terms, so we have not '
            + 'charged you. Please try again in a moment.',
        )
      }

      const outcome = await startCheckout(plan.sku, {
        email: profile?.email,
        name: profile?.name,
      })

      if (outcome.status === 'granted') {
        setNotice(
          plan.kind === 'subscription'
            ? `You are on ${plan.title}. Enjoy it.`
            : `${money(plan.cash_grant)} added to your wallet.`,
        )
        // The wallet, the tier badge and the plan state all changed server-side.
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: ['user-tiers'] }),
          queryClient.invalidateQueries({ queryKey: ['leaderboard'] }),
        ])
      } else if (outcome.status === 'confirming') {
        // Deliberately not phrased as a failure: the payment very likely went
        // through and the webhook is just behind. Telling someone who has paid
        // that it did not work is the worse mistake.
        setNotice(
          'Payment received. We are still confirming it with the bank — this page will catch up within a minute or two.',
        )
      }
      // 'dismissed' says nothing: the user changed their mind and knows it.
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusySku(null)
    }
  }

  const all = plans.data ?? []
  const subscriptions = all.filter(
    (p) => p.kind === 'subscription' && p.billing_interval === interval,
  )
  const topups = all.filter((p) => p.kind === 'one_time')

  // Annual vs monthly, computed rather than asserted, so a price change in the
  // database cannot leave a stale "save 33%" on the page. Computed in the billing
  // currency because the answer differs: ₹1,199 against ₹149×12 saves 33%, while
  // $13 against $2×12 saves 46%.
  const savings = annualSaving(all, billing)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-xl font-extrabold text-ink">Plans &amp; top-ups</h1>
          <p className="mt-1 text-sm text-ink-4">
            {billing === 'USD'
              ? 'Prices in US dollars, taxes included. No adverts, on any plan, ever.'
              : 'Every price includes GST. No adverts, on any plan, ever.'}
          </p>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <span className="text-ink-4">Your plan</span>
          {myTier === 'free' ? (
            <Badge tone="neutral">FREE</Badge>
          ) : (
            <TierBadge tier={myTier} />
          )}
        </div>
      </div>

      {error && (
        <Card className="flex items-start gap-3 border-bear/40 bg-bear-light/40 px-5 py-4">
          <CircleAlert className="mt-0.5 h-4 w-4 shrink-0 text-bear" />
          <div className="min-w-0 text-sm text-ink">
            <p>{error}</p>
            {isGuest && (
              <NavLink to="/upgrade">
                <Button size="sm" variant="dark" className="mt-2.5">
                  <Lock className="h-3 w-3" />
                  Make my account permanent
                </Button>
              </NavLink>
            )}
          </div>
        </Card>
      )}

      {notice && (
        <Card className="flex items-start gap-3 border-bull/40 bg-bull-light/40 px-5 py-4">
          <BadgeCheck className="mt-0.5 h-4 w-4 shrink-0 text-bull" />
          <p className="text-sm text-ink">{notice}</p>
        </Card>
      )}

      {/* ── Subscriptions ──────────────────────────────────────────────────── */}
      <Card>
        <CardHeader
          title="Subscriptions"
          subtitle="Renews automatically. Cancel any time from your Razorpay receipt or by contacting support."
          action={
            <div className="flex rounded-md border border-birch bg-cream p-0.5">
              {(['monthly', 'annual'] as BillingInterval[]).map((i) => (
                <button
                  key={i}
                  onClick={() => setInterval(i)}
                  className={cn(
                    'rounded px-3 py-1.5 text-xs font-semibold capitalize transition-colors',
                    interval === i
                      ? 'bg-pure-white text-ink shadow-sm'
                      : 'text-ink-4 hover:text-ink',
                  )}
                >
                  {i}
                  {i === 'annual' && savings !== null && (
                    <span className="ml-1 text-bull">−{savings}%</span>
                  )}
                </button>
              ))}
            </div>
          }
        />

        {plans.isLoading ? (
          <div className="grid gap-4 p-5 sm:grid-cols-2">
            <Skeleton className="h-56 w-full" />
            <Skeleton className="h-56 w-full" />
          </div>
        ) : (
          <div className="grid gap-4 p-5 sm:grid-cols-2">
            {subscriptions.map((p) => (
              <PlanCard
                key={p.sku}
                plan={p}
                currency={billing}
                current={myTier === p.tier}
                busy={busySku === p.sku}
                disabled={busySku !== null}
                onBuy={() => void buy(p)}
              />
            ))}
          </div>
        )}
      </Card>

      {/* ── One-time top-ups ───────────────────────────────────────────────── */}
      <Card>
        <CardHeader
          title="One-time top-ups"
          subtitle="A single purchase of demo cash. Not a subscription, and it never expires."
        />
        {plans.isLoading ? (
          <div className="grid gap-4 p-5 sm:grid-cols-3">
            <Skeleton className="h-32 w-full" />
            <Skeleton className="h-32 w-full" />
            <Skeleton className="h-32 w-full" />
          </div>
        ) : (
          <div className="grid gap-4 p-5 sm:grid-cols-3">
            {topups.map((p) => (
              <div
                key={p.sku}
                className="flex flex-col rounded-lg border border-birch bg-cream/40 p-4"
              >
                <div className="flex items-center gap-2">
                  <Wallet className="h-4 w-4 text-brand" />
                  <p className="text-sm font-bold text-ink">{p.title}</p>
                </div>
                <p className="tnum mt-3 text-2xl font-extrabold text-ink">
                  {compactMoney(p.cash_grant)}
                </p>
                <p className="text-[11px] text-ink-4">demo cash, credited once</p>
                <div className="mt-auto pt-4">
                  <Button
                    className="w-full"
                    variant="outline"
                    disabled={busySku !== null}
                    onClick={() => void buy(p)}
                  >
                    {busySku === p.sku ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <>Buy for {planPrice(p, billing)}</>
                    )}
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <div className="space-y-2 text-[11px] leading-relaxed text-ink-4">
        <p>
          Demo cash has no monetary value, cannot be withdrawn and cannot be
          exchanged for anything outside Trading Titans. Purchases buy access to
          features and simulated balances only. Payments are processed by
          Razorpay; we never see your card details.
        </p>
        <p>
          Subscriptions renew automatically until cancelled. By continuing to a
          payment you agree to our{' '}
          <button
            onClick={() => setReading(TERMS)}
            className="font-semibold text-brand-deep underline hover:text-brand"
          >
            Terms &amp; Conditions
          </button>
          , including the cancellation and refund policy, and our{' '}
          <button
            onClick={() => setReading(PRIVACY)}
            className="font-semibold text-brand-deep underline hover:text-brand"
          >
            Privacy Policy
          </button>
          .
        </p>
      </div>

      <LegalSheet doc={reading} onClose={() => setReading(null)} />
    </div>
  )
}

/** The percentage an annual plan saves against paying monthly, or null if unclear. */
function annualSaving(plans: Plan[], currency: BillingCurrency): number | null {
  const monthly = plans.find((p) => p.billing_interval === 'monthly')
  const annual = plans.find(
    (p) => p.billing_interval === 'annual' && p.tier === monthly?.tier,
  )
  if (!monthly || !annual) return null
  const monthlyMinor = planMinor(monthly, currency)
  const annualMinor = planMinor(annual, currency)
  // A missing price in this currency makes the comparison meaningless, and a
  // wrong discount badge is worse than none.
  if (monthlyMinor === null || annualMinor === null) return null
  const yearAtMonthly = monthlyMinor * 12
  if (yearAtMonthly <= 0) return null
  const saved = Math.round((1 - annualMinor / yearAtMonthly) * 100)
  return saved > 0 ? saved : null
}

function PlanCard({
  plan,
  currency,
  current,
  busy,
  disabled,
  onBuy,
}: {
  plan: Plan
  currency: BillingCurrency
  current: boolean
  busy: boolean
  disabled: boolean
  onBuy: () => void
}) {
  const isTitan = plan.tier === 'titan'
  const annualMinor =
    plan.billing_interval === 'annual' ? planMinor(plan, currency) : null
  const perMonth = annualMinor === null ? null : annualMinor / 1200

  return (
    <div
      className={cn(
        'flex flex-col rounded-xl border p-5',
        isTitan ? 'border-violet/40 bg-violet-light/25' : 'border-birch bg-cream/40',
      )}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          {isTitan && <Sparkles className="h-4 w-4 text-violet" />}
          <p className="text-sm font-extrabold text-ink">{plan.title}</p>
        </div>
        {current && <Badge tone="bull">CURRENT</Badge>}
      </div>

      <p className="tnum mt-4 text-3xl font-extrabold text-ink">
        {planPrice(plan, currency)}
      </p>
      <p className="text-[11px] text-ink-4">
        per {plan.billing_interval === 'annual' ? 'year' : 'month'},{' '}
        {currency === 'USD' ? 'taxes' : 'GST'} included
        {perMonth !== null && ` · works out to ${inCurrency(perMonth, currency)}/mo`}
      </p>

      <ul className="mt-4 space-y-2 text-[13px] text-ink-3">
        <li className="flex items-start gap-2">
          <BadgeCheck
            className={cn('mt-0.5 h-3.5 w-3.5 shrink-0', isTitan ? 'text-violet' : 'text-brand')}
          />
          <span>
            <strong className="font-semibold text-ink">
              {compactMoney(plan.monthly_stipend)}
            </strong>{' '}
            demo cash every month
          </span>
        </li>
        <li className="flex items-start gap-2">
          <BadgeCheck
            className={cn('mt-0.5 h-3.5 w-3.5 shrink-0', isTitan ? 'text-violet' : 'text-brand')}
          />
          <span>Futures &amp; options trading</span>
        </li>
        <li className="flex items-start gap-2">
          <BadgeCheck
            className={cn('mt-0.5 h-3.5 w-3.5 shrink-0', isTitan ? 'text-violet' : 'text-brand')}
          />
          <span>
            A <strong className="font-semibold text-ink">{plan.tier.toUpperCase()}</strong>{' '}
            badge on your profile and the leaderboard
          </span>
        </li>
        <li className="flex items-start gap-2">
          <BadgeCheck
            className={cn('mt-0.5 h-3.5 w-3.5 shrink-0', isTitan ? 'text-violet' : 'text-brand')}
          />
          <span>No adverts — same as the free plan</span>
        </li>
      </ul>

      <div className="mt-auto pt-5">
        <Button
          className="w-full"
          variant={isTitan ? 'dark' : 'primary'}
          disabled={disabled || current}
          onClick={onBuy}
        >
          {busy ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : current ? (
            'Your current plan'
          ) : (
            `Get ${plan.title}`
          )}
        </Button>
      </div>
    </div>
  )
}
