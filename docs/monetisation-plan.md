# Monetisation plan — top-ups, subscriptions, enterprise

Status: **proposal, nothing built.** Written after auditing what already exists in
the database and both clients, so the sequencing below reflects the real starting
point rather than a greenfield one.

---

## 0. Read this first: three blockers

These are not risks to manage later. Each one makes it unsafe or non-compliant to
switch monetisation on, and each is cheap to fix now and expensive to fix after
money has changed hands.

### 0.1 Two RPCs are currently free-money endpoints

`credit_demo_cash(p_amount numeric)` and `activate_subscription(p_plan_id text)`
are both `SECURITY DEFINER`, both `EXECUTE`-granted to `authenticated`, and
**neither takes a payment reference or verifies anything**. Any signed-in user can
open a console and call:

```js
await supabase.rpc('credit_demo_cash', { p_amount: 1000000 })      // +₹10,00,000
await supabase.rpc('activate_subscription', { p_plan_id: 'titan_pro' }) // +₹10,00,000 and Pro
```

The only guards are "not a guest" and a ₹10,00,000 per-call cap on the top-up —
and the cap is per call, not cumulative, so it is not a limit on anything.

Today this costs nothing real, because the product is free and the cash is
simulated. The moment a price tag appears next to those numbers, this is the
product being given away. **Nothing else in this plan can ship until both RPCs
require a server-verified payment.** See Phase 1.

### 0.2 The Terms say the product is free, and 176 users accepted that

The Terms and Privacy text (`app/lib/core/legal.dart`, mirrored at
`web/src/lib/legal.ts`) currently state, in the document users tick a box to
accept:

> **Free:** there is nothing to buy, so there is nothing to refund.

Revision `August 17, 2026` is recorded against every acceptance in
`profiles.terms_version`. Introducing paid plans requires new Terms with payment,
refund, cancellation and auto-renewal clauses, a version bump, and **re-consent**
— the existing acceptances do not cover a paid product. The `accept_terms` RPC
already handles a version change correctly (a newer version updates the
timestamp), so the machinery is there; the text and the release are not.

The website's `TermsPage.tsx` and `PrivacyPage.tsx` still carry the *old* paid-era
Razorpay text. Those are a starting point for the new text, not something to
simply un-hide — they describe packs and prices that will not match this funnel.

### 0.3 Google Play billing policy decides the architecture, not us

Play policy requires Google Play Billing for in-app purchases of digital content,
and virtual currency is explicitly named. Practical consequences:

- Selling top-ups **inside the Android app** via Razorpay is a policy violation
  that risks removal, not a fee optimisation.
- Linking from inside the app to a web checkout is also restricted. India has had
  an alternative-billing allowance, but it is conditional and still carries a
  service fee — this needs a written decision, not an assumption.
- The **web app has no such constraint.** Razorpay on `trading-titans-web.vercel.app`
  is clean.

This is a commercial decision with a technical consequence, and it has to be made
before Phase 2 is designed. Options in §6.

---

## 1. What already exists

Worth knowing, because a surprising amount of the plumbing is in place.

| Piece | State |
|---|---|
| `app_flags.monetization_enabled` | **false.** Kill switch for top-up card, Subscribe screen, plan badges. Already respected by `app_flags_service.dart`. |
| `profiles.plan` | `text`, default `'free_starter'`. All 176 users on it. |
| `profiles.subscription_active` | `boolean`, **default `true`**. Everyone is "active" today. |
| `activate_subscription(text)` | Exists. Credits cash, sets plan. No payment check. |
| `credit_demo_cash(numeric)` | Exists. Credits cash. No payment check. |
| `wallet_transactions` | 395 rows. Full ledger with `balance_before`/`after` and a `kind`. Reusable for purchase credits. |
| `referral_commissions` | Empty, but already shaped for paid packages: `package_name`, `package_price`, `commission_amount`, `status`. |
| Plan catalogue | Hard-coded in `supabase_service.dart` as `titan_1l` ₹199/₹1L, `titan_5l` ₹599/₹5L, `titan_pro` ₹999/₹10L — all flagged `is_mock: true`. |
| Payments table | **Does not exist.** No order, receipt, webhook or idempotency record anywhere. |
| Payment gateway | **None wired.** The whole flow is mocked. |
| `website/src/components/TopupPage.tsx` | Deliberately disabled with a note explaining why. |

So: the *shape* of one-time cash packs already exists and maps onto funnel tier 1.
Recurring subscriptions, entitlements, and every part of taking actual money do
not exist at all.

---

## 2. The funnel

### Tier 1 — Top-ups (one-time, keep forever)

Buy simulated cash once; it stays on the account. No renewal, no expiry.

This already exists as `titan_1l` / `titan_5l` / `titan_pro`. Suggested tidy-up:
rename to what they are, since "Pro Launch" reads like a subscription tier and will
be confused with tier 2.

| Pack | Cash | Indicative price |
|---|---|---|
| Boost | ₹1,00,000 | ₹199 |
| Plus | ₹5,00,000 | ₹599 |
| Max | ₹10,00,000 | ₹999 |

Deliberately **not** bundled with feature access. Keeping "cash" and "features"
as separate axes is what stops the funnel collapsing into one confusing ladder,
and it means a top-up buyer has a reason to also subscribe.

One design question to settle: is bought cash **protected from a balance reset?**
If challenges or seasons ever reset wallets, resetting paid-for cash is a refund
conversation. Recommend a separate `purchased_cash_floor` on the profile that a
reset cannot go below.

### Tier 2 — Subscription (monthly / annual)

Recurring. Unlocks features, does **not** grant cash (or grants a small monthly
stipend — decide, see §7).

Indicative: **₹199/month, ₹1,499/year** (annual ≈ 37% off, which is the discount
that historically converts best on annual). Name: keep `titan_pro` as the id if
you want continuity with existing data, but the id currently means a cash pack —
cleaner to introduce `pro_monthly` / `pro_annual` and leave the old ids to tier 1.

### Tier 3 — Enterprise (contact us only)

No self-serve checkout. A form that creates a lead. Target: colleges, coaching
institutes, prop-desk training, corporate L&D.

Offer: seat pools, an instructor/admin view over a cohort, custom starting
capital, private leaderboards, branded reports, bulk onboarding. **None of this
exists** — enterprise is a sales motion first and a build second, so Phase 5 is
deliberately just the lead capture. Do not build cohort tooling before a signed
pilot.

`support_tickets` (4 rows) already exists and can carry enterprise leads without a
new table.

---

## 3. Feature matrix

You asked for the web app, autopsies and leaderboards to become paid. Below is
that, with two places where I think it costs more than it earns — flagged, not
silently overridden.

| Feature | Free | Top-up buyer | Subscriber | Enterprise |
|---|---|---|---|---|
| Android app, Indian equity, market + limit orders | ✅ | ✅ | ✅ | ✅ |
| Crypto | ✅ | ✅ | ✅ | ✅ |
| Portfolio, orders, wallet ledger | ✅ | ✅ | ✅ | ✅ |
| Buy simulated cash | ✅ | ✅ | ✅ | n/a |
| **Web app** | ⚠️ see §3.1 | ⚠️ | ✅ | ✅ |
| **Trade Autopsy** | last 3 trades | last 3 | ✅ unlimited + advice | ✅ |
| **Leaderboard** | ⚠️ see §3.2 | ⚠️ | ✅ full + history | ✅ private boards |
| F&O (futures and options) | view only | view only | ✅ trade | ✅ |
| US stocks | ❌ | ❌ | ✅ | ✅ |
| Price alerts | 3 | 3 | unlimited | unlimited |
| Watchlists | 1, 10 symbols | 1 | unlimited | unlimited |
| Advanced charts (5Y, all timeframes) | 1M only | 1M | ✅ all | ✅ |
| Option chain with real OI | ❌ | ❌ | ✅ | ✅ |
| What-if simulator | 1/day | 1/day | unlimited | ✅ |
| P&L history and analytics | 7 days | 7 days | full | full + export |
| Challenges and XP | ✅ | ✅ | ✅ + exclusive | ✅ |
| Ad-free | — | — | ✅ | ✅ |
| Data export (CSV) | ❌ | ❌ | ✅ | ✅ + API |
| Cohort/instructor view | ❌ | ❌ | ❌ | ✅ |
| Support | community | community | priority | dedicated + SLA |

### 3.1 Gating the whole web app — my recommendation: don't

Making the web app subscriber-only is the single highest-leverage paywall you
have, and also the one most likely to backfire, for a specific reason: **the web
app is where you can sell without Google's cut** (§0.3). If a free user cannot
open the web app, they can never reach a Razorpay checkout, and every purchase is
pushed back into Play Billing.

Recommended instead: web app is **free to browse and trade**, and the subscriber
features inside it are gated the same as on mobile. You keep the paywall pressure
and keep the cheap payment rail. A "web access" paywall also asks the user to pay
for a *platform* rather than a *capability*, which is a harder sell than "unlock
F&O".

If you still want web behind the wall, the least-bad version is a **7-day free
web trial** on signup, which preserves the checkout path.

### 3.2 Gating the leaderboard — my recommendation: partial only

The leaderboard is a retention and virality loop. A free user who cannot see where
they rank loses the main reason to come back tomorrow, and a leaderboard nobody
free can see stops being social proof.

Recommended split: **free users see the top 10 and their own rank.** Subscribers
get the full 100, historical placings, percentile, and the weekly podium archive.
That keeps the hook and still sells something real.

### 3.3 What is genuinely worth gating

Ranked by "subscriber would pay for this" against "free user does not lose the
core loop":

1. **F&O trading** — the highest-intent feature, real depth, natural upsell from
   equity. Also the most expensive for us to run (bhavcopy, lot sizes, expiry).
2. **US stocks** — already behind a flag, so gating is nearly free to implement.
3. **Unlimited autopsies with advice** — the advice text is the product.
4. **Option chain with real OI** — real NSE data, real cost.
5. **Full analytics and export** — the "I'm serious about this" feature.

Cap-based limits (alerts, watchlists, what-if) are better than hard locks: a limit
teaches the value, a lock hides it.

---

## 4. Data model to add

```
payment_orders        -- one row per checkout attempt
  id, user_id, provider ('razorpay'|'play'|'manual'),
  provider_order_id, kind ('topup'|'subscription'),
  sku, amount_paise, currency, status
  ('created'|'paid'|'failed'|'refunded'), created_at, paid_at

payment_events         -- raw verified webhook payloads, append-only
  id, order_id, provider, provider_event_id UNIQUE, type, payload jsonb, received_at

subscriptions
  id, user_id, sku, provider, provider_subscription_id,
  status ('trialing'|'active'|'past_due'|'cancelled'|'expired'),
  current_period_start, current_period_end,
  cancel_at_period_end bool, created_at, updated_at

entitlements           -- the ONE thing the app reads
  user_id, feature text, value jsonb, source, expires_at
  primary key (user_id, feature)

plan_catalogue         -- prices and limits as DATA, not hard-coded in Dart
  sku, tier, title, price_paise, interval, cash_grant, features jsonb, is_active
```

Two decisions worth stating plainly:

**`entitlements` is the read path, and nothing else is.** Clients must never
compute access from `plan` strings or price tables. One table, one question —
"does this user have this feature" — means a plan rename, a promo, a grandfather,
a manual grant and an enterprise seat all flow through the same check. The current
`profiles.plan` text column is exactly the thing that becomes a mess of string
comparisons scattered across three clients.

**`payment_events.provider_event_id` is UNIQUE, and that is the idempotency key.**
Gateways retry webhooks. Without this, one payment credits cash more than once.

`profiles.plan` and `subscription_active` stay for now as a denormalised cache, so
existing code keeps working, but they become *derived* — written by the
entitlement logic, never by a client.

---

## 5. Migration of the 176 existing users

`subscription_active` defaults to **`true`** and every current user has it. So the
naive switch-on has two failure modes, and both are bad:

- Gate on `subscription_active` → all 176 users are silently upgraded to paid for
  free, and you can never tell them apart from real subscribers.
- Flip the default to `false` and gate → 176 existing users lose features they
  have been using, with no warning, on an app update.

Recommended: **grandfather explicitly.** Before switching anything on, write a
migration that gives every existing account a permanent `founding_member`
entitlement covering the subscriber feature set. Reasons: it is honest (they used
the product when it was advertised as free), it is a genuine goodwill story worth
announcing, and it makes the paid cohort measurable from day one because it is a
separate `source` in `entitlements`.

Owner accounts (`.kiro/steering/owner-accounts.md`) get the same permanent
entitlement, and stay exempt from every cap and audit.

---

## 6. The Play Billing decision

Needs answering before Phase 2 is designed. Three options:

**A. Play Billing in-app, Razorpay on web.** Fully compliant. Costs Google's fee
(15% up to $1M/yr) on mobile. Two payment integrations, two webhook paths, and
prices that differ by platform unless you absorb the fee. Most work, least risk.

**B. Web-only checkout, app is read-only about payment.** One integration
(Razorpay), no Google fee. The app must not link to or mention the web checkout,
which materially hurts conversion — most users are on mobile. Compliant only if
the app is genuinely silent about purchasing.

**C. Play Billing only, no web checkout.** Simplest single integration, but pays
Google's fee on everything including web users, and wastes the web app's
advantage.

**Recommendation: start with B, add A later.** Ship web checkout first because it
is one integration and zero policy risk, prove people will actually pay, then take
on Play Billing once there is revenue to justify the work. This also means Phase 2
does not block on Play review.

---

## 7. Open questions for you

1. **Does a subscription grant cash?** Clean separation says no. A small monthly
   stipend (say ₹50,000) makes the subscription feel tangible every month. Pick
   one — the ambiguity is what makes pricing pages confusing.
2. **Is purchased cash protected from resets?** (§2, tier 1.)
3. **Web app: gate, don't gate, or trial?** (§3.1.)
4. **Leaderboard: full gate or top-10-plus-own-rank?** (§3.2.)
5. **Prices**: are ₹199/₹1,499 right for the audience? Indian retail simulator
   users are price-sensitive; ₹199/mo is roughly a streaming subscription.
6. **Refund policy.** Needed for the Terms rewrite regardless. Simulated goods
   delivered instantly are normally non-refundable, but Play has its own rules.
7. **Free trial on subscription?** 7 days is standard and lifts conversion, but
   needs `trialing` status handled everywhere.
8. **Do ads exist?** The matrix lists "ad-free" as a subscriber benefit, but there
   are no ads in the product today. Drop the row or plan the ads.

---

## 8. Phased build order

Each phase is independently shippable and leaves the product in a working state.
Monetisation stays **off** until Phase 4.

### Phase 1 — Close the free-money hole (server only, no release)
Blocking prerequisite. Nothing user-visible.

1. `revoke execute on credit_demo_cash, activate_subscription from authenticated`.
2. Reintroduce both behind a new signature that requires a verified
   `payment_orders.id` and asserts `status='paid'`, callable only by the service
   role from an edge function.
3. Add an owner/admin-only `admin_credit_cash` for the self-credit the owner rule
   allows, gated on `is_admin()`.
4. Verify no client calls the old signatures. The app's Subscribe screen does —
   it is already hidden by the kill switch, so it can fail closed.

**Done when** a normal authenticated user cannot move their own balance.

### Phase 2 — Payments spine (server + web)
1. Migrations for the five tables in §4.
2. Seed `plan_catalogue` with the tier 1 packs and tier 2 SKUs.
3. `create-payment-order` edge function: creates a Razorpay order, records
   `payment_orders`.
4. `razorpay-webhook` edge function: **signature verification**, idempotent on
   `provider_event_id`, marks paid, grants cash or entitlement, writes
   `wallet_transactions`.
5. `entitlements` write logic + a `has_entitlement(feature)` SQL helper.
6. Web checkout UI, live behind the kill switch.

**Done when** a real ₹1 test payment credits exactly once, and a replayed webhook
credits zero more times.

### Phase 3 — Entitlement enforcement (both clients)
1. Web: an `useEntitlement()` hook and gates on the §3 features.
2. App: extend `app_flags_service` into an entitlement service, gate the same
   features. Needs a release.
3. Every gate has an upgrade path that *explains what is behind it* — a lock with
   no explanation is a dead end.
4. Server-side enforcement too, on anything with a cost: F&O order placement must
   check entitlement in `place-order`, not just hide a button. **A client-side-only
   gate is decoration.**

### Phase 4 — Legal, grandfathering, switch-on
1. New Terms and Privacy with payment, refund, renewal and cancellation clauses.
2. Bump `TERMS_VERSION` in both `legal.dart` and `legal.ts`; re-consent prompt for
   existing users on next launch.
3. Grandfather migration (§5).
4. Flip `monetization_enabled` to true.
5. Store listing and screenshots updated to reflect in-app purchases.

### Phase 5 — Enterprise lead capture
1. `/enterprise` page on web: what it includes, a form, no price.
2. Lead lands in `support_tickets` with a distinguishing `kind`.
3. Nothing else until a pilot is signed.

### Phase 6 — Later
Play Billing (option A), referral commissions on paid packages (`referral_commissions`
is already shaped for it), annual-plan dunning, cohort tooling.

---

## 9. What I'd do first

If you want one thing done today: **Phase 1**. It is server-only, needs no release,
breaks nothing user-visible, and it is the difference between a paywall and a
suggestion. Everything else can be designed while it is in place.
