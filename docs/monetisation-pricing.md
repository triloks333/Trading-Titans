# Pricing & revenue plan

Commercial plan only — SKUs, price points, what each tier includes, and what you
actually keep after tax and fees. No engineering here; that's in
`monetisation-plan.md`.

All figures in ₹. Fee and tax rates verified against current sources (§6).
Revenue tables computed, not estimated — see the assumptions in §4.

---

## 1. The catalogue

Two axes. **Top-ups sell cash. Subscriptions sell capability.** Keeping them
separate stops the funnel collapsing into one confusing ladder, and it means a
top-up buyer still has a reason to subscribe.

### Tier 1 — Top-ups (one-time, keep forever)

| SKU | Virtual cash | Price | ₹ per lakh |
|---|---|---|---|
| `topup_boost` | ₹1,00,000 | **₹199** | ₹199 |
| `topup_plus` | ₹5,00,000 | **₹599** | ₹120 |
| `topup_max` | ₹10,00,000 | **₹999** | ₹100 |

Same prices as the packs already in the code (`titan_1l` / `titan_5l` /
`titan_pro`), so nothing is wasted. The declining ₹-per-lakh is deliberate: it
makes trading up feel like a discount rather than an upsell.

No feature access attached. No expiry, no renewal.

### Tier 2 — Subscriptions (recurring, two levels)

| SKU | Monthly | Annual | Effective /mo on annual | Annual saving |
|---|---|---|---|---|
| `pro_monthly` / `pro_annual` | **₹149** | **₹1,199** | ₹99.92 | 33% (₹589) |
| `titan_monthly` / `titan_annual` | **₹799** | **₹5,999** | ₹499.92 | 37% (₹3,589) |

**Pro ₹149** is priced deliberately *below* the cheapest top-up. A recurring ₹199
is a harder ask than a one-time ₹199, so putting Pro under the impulse price makes
it the obvious-value option. Annual lands under ₹100/mo, which is the number that
closes.

**Titan ₹799** is a different customer, not a bigger version of the same one. Pro
is for someone learning; Titan is for someone treating this as practice for a real
options desk. The 37% annual discount is heavier than Pro's on purpose — churn risk
rises with ticket size, so locking Titan users into a year is worth more than the
margin given up.

Naming uses the brand for the top tier: **Free → Pro → Titan → Enterprise**. The
`titan_*` prefix is free to reuse because the old cash packs are being renamed
`topup_*`.

### Tier 3 — Enterprise (contact us only)

Per-seat, annual, invoiced directly. No self-serve checkout, no price on the page.

| Band | Seats | Price/seat/yr | Example |
|---|---|---|---|
| Campus | 50–249 | ₹499 | 100 seats = ₹49,900 |
| Institution | 250–999 | ₹399 | 400 seats = ₹1,59,600 |
| Scale | 1,000+ | ₹299 | 2,000 seats = ₹5,98,000 |

- **Minimum contract ₹25,000/yr** — keeps out deals that cost more to service than
  they earn.
- Optional one-time **onboarding & branding ₹10,000**: branded reports, custom
  starting capital, cohort setup.
- Targets: colleges and B-schools, trading coaching institutes, prop-desk training,
  corporate L&D, finance-club competitions.

---

## 2. What each tier includes

The two-tier split only works if features actually move up. Below, Pro keeps
everything that upgrades a *learner*, and Titan takes everything that costs us real
money or real compute — which is also what a serious trader will pay for.

**Free**
Android + web app · Indian equity, market & limit orders · crypto · portfolio,
orders, wallet ledger · challenges and XP · leaderboard top 10 + your own rank ·
3 trade autopsies · 3 price alerts · 1 watchlist (10 symbols) · 1-month charts ·
7 days P&L history · 1 what-if/day · community support

**Top-up buyer**
Free, plus the virtual cash purchased — permanently. No feature change.

**Pro — ₹149/mo or ₹1,199/yr**
Free, plus:
- **Index F&O trading** — NIFTY and BANKNIFTY futures and options
- **US stocks**
- **Unlimited trade autopsies with advice**
- **Full leaderboard** — all 100, historical placings, percentile, podium archive
- **Unlimited price alerts and watchlists**
- **All chart timeframes** up to 5 years
- **Full P&L history and analytics** + CSV export
- **Unlimited what-if simulations**
- ₹50,000/month cash stipend · exclusive challenges · priority support

**Titan — ₹799/mo or ₹5,999/yr**
Pro, plus:
- **Real-time tick data** — Pro runs on the standard refresh, Titan gets live ticks
- **Full stock F&O** — every underlying, not just index
- **Options Greeks and a real IV surface** — delta, gamma, theta, vega, per-strike
  implied vol instead of a flat assumption
- **Multi-leg strategy builder** — spreads, straddles, condors, with payoff diagrams
- **Backtesting** against historical NSE F&O data
- **Advanced risk analytics** — Sharpe, max drawdown, VaR, exposure heatmap
- **AI trade coach** — pattern analysis across your whole history, not per trade
- **Up to 5 parallel portfolios** — test strategies side by side
- **₹5,00,000/month cash stipend**
- **Read-only data API** · dedicated support · feature-request priority

**Enterprise**
Titan for every seat, plus instructor/admin view over the cohort, private
leaderboards, custom starting capital, branded reports, bulk onboarding, full data
export API, dedicated support with SLA.

### Two placement calls worth defending

**Web app stays free.** It's the only rail where you keep ~83% instead of ~72%
(§3). Gating it means a free user can never reach a web checkout, pushing every
sale into Play and costing 11 points of margin on all of it.

**Leaderboard is only partly gated.** Free keeps the top 10 and own rank. A
leaderboard no free user can see stops being a retention loop and stops being
social proof. The full 100 + history + percentile still sells something real.

### The thing that makes ₹799 defensible or not

At ₹799/mo you are priced against **Sensibull (~₹800/mo)** — a real options
analytics product. So Titan has to genuinely ship Greeks, a real IV surface, the
strategy builder and backtesting. Four of those are things this codebase does not
have yet, and one of them (**option premiums currently use a flat 25% IV across all
clients**) is a known open bug.

Put plainly: **Titan cannot launch at ₹799 on today's feature set.** Pro can launch
almost immediately. Sequence accordingly — Pro first, Titan when the options stack
is real. Shipping Titan early at ₹799 with a flat-IV pricing model invites refunds
from exactly the customers you most want.

---

## 3. What you actually keep

Three rates decide everything:

- **GST 18%** on digital services in India, and B2C prices must display inclusive
  of it. ₹149 is not ₹149 of revenue — it's ₹126.27 plus ₹22.73 you owe.
- **Razorpay 2%** + 18% GST on that fee. Once GST-registered the fee's GST is input
  credit, so the real cost is 2%; before registration, 2.36%.
- **Google Play 15%** on the first $1M/yr for India.

### Take rate by rail

| Rail | You keep |
|---|---|
| Web / Razorpay, **before** GST registration | **97.6%** |
| Web / Razorpay, after GST registration | **82.7%** |
| Google Play Billing, India | **~72%** |
| Play + India alternative billing (15% − 4% + own gateway 2%) | **~71.7%** |

Two conclusions fall straight out:

**India's alternative-billing route is pointless.** Knocking 4% off the Play fee
then paying your own gateway 2% lands within a rounding error of just using Play
Billing, for a great deal more work. Skip it.

**Web is worth 11 points over Play** — and it matters most on the expensive SKU. On
a ₹5,999 Titan annual that's **₹643 per subscriber per year**.

### Net per SKU

| SKU | Price | Web, pre-GST-reg | Web, post-GST-reg | Play Billing |
|---|---|---|---|---|
| Boost | ₹199 | ₹194.30 | ₹164.66 | ₹143.35 |
| Plus | ₹599 | ₹584.86 | ₹495.65 | ₹431.48 |
| Max | ₹999 | ₹975.42 | ₹826.63 | ₹719.62 |
| Pro monthly | ₹149 | ₹145.48 | ₹123.29 | ₹107.33 |
| Pro annual | ₹1,199 | ₹1,170.70 | ₹992.12 | ₹863.69 |
| **Titan monthly** | ₹799 | ₹780.14 | ₹661.14 | ₹575.55 |
| **Titan annual** | ₹5,999 | ₹5,857.42 | ₹4,963.92 | ₹4,321.31 |

### The ₹20 lakh GST cliff — plan for this

GST registration is mandatory for services above **₹20 lakh** aggregate annual
turnover (₹10 lakh in special-category states). The day you cross it you lose
15.25% of every rupee.

So the revenue curve goes *backwards* across the threshold:

| Gross turnover | Net kept |
|---|---|
| ₹19,90,000 | ₹19,42,964 |
| ₹20,10,000 | ₹16,63,275 |

**You need ₹23.5 lakh of gross to beat ₹19.9 lakh of gross.** Two options, both
needing a decision well before you get near: raise prices ~18% to coincide with
registration (₹149 → ₹179, ₹799 → ₹949), or absorb the dip. Deciding late means
eating it.

The Titan tier **brings this forward significantly** — see §4.

On Play, Google is merchant of record for GST in India, so ~72% applies whether or
not you're registered: no cliff, but no cheap early phase either. **Confirm the
exact Play/GST mechanics with a CA before modelling on it.**

---

## 4. Revenue scenarios

Assumptions, stated so you can argue with them:

- **2% of registered users subscribe** (base). Consumer freemium runs 1–3%. Bear
  1%, bull 4%.
- **80% take Pro, 20% take Titan.** Typical for a ~5× price gap; the premium tier
  usually lands at 10–25% of the paid base.
- **70/30 monthly/annual** split within each tier.
- **10% monthly churn** → ~10-month average life on monthly plans.
- **4% of registered users buy one top-up per year**, average ticket ₹459 (mix:
  50% Boost, 35% Plus, 15% Max).

### Base case, gross annual revenue

| Registered users | Subscribers | Sub revenue | Top-up revenue | **Gross/yr** | Gross/mo |
|---|---|---|---|---|---|
| 176 *(today)* | ~4 | ₹9,173 | ₹3,213 | **₹12,386** | ₹1,032 |
| 1,000 | 20 | ₹52,014 | ₹18,360 | **₹70,374** | ₹5,864 |
| 5,000 | 100 | ₹2,60,070 | ₹91,800 | **₹3,51,870** | ₹29,322 |
| 10,000 | 200 | ₹5,20,140 | ₹1,83,600 | **₹7,03,740** | ₹58,645 |
| 50,000 | 1,000 | ₹26,00,700 | ₹9,18,000 | **₹35,18,700** | ₹2,93,225 |
| 100,000 | 2,000 | ₹52,01,400 | ₹18,36,000 | **₹70,37,400** | ₹5,86,450 |

The number to carry around: **₹70.37 gross per registered user per year.**

### What the Titan tier is actually worth

| | Single tier (₹149 only) | Two tiers (₹149 + ₹799) |
|---|---|---|
| ARPU / registered user / yr | ₹46.41 | **₹70.37** |
| Gross at 10,000 users | ₹4,64,140 | **₹7,03,740** |

**Adding Titan lifts revenue 51.6% at the same conversion rate.** And the split
inside that is the real story: **Titan is 20% of subscribers but 56.9% of
subscription revenue.** One Titan annual subscriber is worth five Pro annuals.

That has a direct consequence for where effort goes — moving a Pro user to Titan is
worth ~5× more than converting a new free user to Pro.

### Net, after the right rail

| Registered users | Gross/yr | Net (web) | Notes |
|---|---|---|---|
| 1,000 | ₹70,374 | ₹68,713 | pre-GST |
| 5,000 | ₹3,51,870 | ₹3,43,566 | pre-GST |
| 10,000 | ₹7,03,740 | ₹6,87,132 | pre-GST |
| 50,000 | ₹35,18,700 | ₹29,11,575 | **GST applies** |
| 100,000 | ₹70,37,400 | ₹58,23,150 | GST applies |

**The GST cliff now arrives at ~28,400 registered users**, down from ~43,100 on the
single-tier model. Higher ARPU is good, but it means registration and the price
adjustment that should accompany it land a lot sooner than the user-count target
suggests.

### Sensitivity

Conversion rate, at 10,000 users:

| Subscriber conversion | Gross/yr |
|---|---|
| 1% (bear) | ₹4,43,670 |
| 2% (base) | ₹7,03,740 |
| 4% (bull) | ₹12,23,880 |

Tier mix, at 10,000 users and 2% conversion:

| Titan share of subscribers | Gross/yr |
|---|---|
| 10% | ₹5,83,940 |
| 20% (base) | ₹7,03,740 |
| 30% | ₹8,23,540 |

Ten points of tier mix is worth ₹1.2 lakh/yr at 10,000 users — comparable to a
whole point of overall conversion. **Tier mix is now as important a lever as
conversion**, and it's the cheaper one to move because those users are already
paying.

### Honest read

At today's 176 users this is roughly **₹1,030/month**. Monetisation is not a
revenue event at this scale — it's plumbing built now so it's ready when the user
base justifies it. Distribution matters far more than pricing.

Milestones worth naming: **~2,400 users covers infrastructure** (§5), **~28,400
brings GST**, and **50,000 makes this a real business**.

---

## 5. Cost side and break-even

Fill in your actual figures; the structure is the point.

| Line | Est. /mo | Scales with users? |
|---|---|---|
| Supabase Pro | ~₹2,100 ($25) | Yes — DB, egress, function calls |
| Vercel | ₹0–1,700 | Mildly |
| Market data (Upstox / Fyers) | **?** | Depends on contract |
| Domain + email | ~₹200 | No |
| FCM push | ₹0 | No |
| Play developer account | $25 one-time | No |
| **Estimated current burn** | **₹5,000–15,000** | |

Blended net revenue per subscriber per year, at the 80/20 tier and 70/30 billing
mix (pre-GST, web): **₹2,539**.

| Monthly burn | Subscribers needed | ≈ registered users at 2% |
|---|---|---|
| ₹5,000 | 24 | 1,200 |
| ₹10,000 | 47 | 2,400 |
| ₹15,000 | 71 | 3,550 |

**Break-even lands around 1,200–3,600 registered users** — roughly half what the
single-tier model needed. Titan does that, not Pro.

One caveat on the cost line: Titan promises **real-time tick data**, and that is
the one benefit here with a genuine variable cost attached. Before committing to
₹799, price what live tick data actually costs per user under your Upstox/Fyers
contract. If it's material, Titan's margin is not the ₹780 in the table.

### Enterprise changes the shape completely

| Deal | Annual value | Equivalent in B2C |
|---|---|---|
| 100-seat campus @ ₹499 | ₹49,900 | 109 top-ups / 9 Titan annuals |
| 400-seat institution @ ₹399 | ₹1,59,600 | 348 top-ups / 27 Titan annuals |
| 2,000-seat @ ₹299 | ₹5,98,000 | 1,303 top-ups / 100 Titan annuals |

One 400-seat institution ≈ the entire subscription revenue from 3,000 registered
consumer users. No Play fee, no app-store review, no per-user support, invoiced
directly, paid annually up front instead of dribbling in with 10% monthly churn.

If the goal is revenue rather than user count, enterprise is the priority and B2C
is the funnel that makes enterprise credible.

---

## 6. Competitive price context

| Service | Price/mo |
|---|---|
| Spotify India | ₹119 |
| YouTube Premium India | ₹149 |
| Netflix mobile India | ₹149 |
| **Trading Titans Pro** | **₹149** |
| Neostox paper trading | ~₹500 |
| Sensibull (options analytics) | ~₹800 |
| **Trading Titans Titan** | **₹799** |
| TradingView Essential India | ~₹1,200 |

Pro at ₹149 sits in the casual-app band, which is the right band — most competing
simulators (StockGro, Dhan) are free, so the paid pitch has to be cheap enough not
to think about.

Titan at ₹799 sits in the **tools** band, against Sensibull. That's a coherent
position but an exacting one: at that price users compare feature lists directly,
which is why §2 insists Titan ships real Greeks and backtesting first.

### On the 5.4× gap between tiers

Standard SaaS ladders step 2–3×. ₹149 → ₹799 is a big leap, and it works only
because the two tiers target genuinely different people rather than different
appetites. Watch for one signal after launch: if Titan conversion sits below ~10%
of subscribers while Pro users hit their limits often, the gap is too wide and a
middle tier is being asked for. **₹399/mo** — stock F&O and Greeks, without
real-time data, backtesting or the API — is the natural insert, and at 10,000 users
a 15% middle-tier share is worth roughly ₹40,000/yr over the two-tier base. Don't
build it pre-emptively.

### Sources

Rates verified from: [Razorpay pricing — 2% + 18% GST on domestic
payments](https://razorpay.com/blog/razorpay-payment-gateway-pricing-explained),
[Google Play service fee — 15% or less for 99% of
developers](https://support.google.com/googleplay/android-developer/answer/11131145?hl=en-IN),
[India alternative billing — service fee reduced by
4%](https://support.google.com/googleplay/android-developer/answer/13306652?hl=en),
[GST 18% on SaaS and digital services in
India](https://www.india-briefing.com/news/gst-compliance-for-saas-and-cloud-computing-in-india-explained-39021.html/),
[GST registration threshold ₹20 lakh for
services](https://cleartax.in/s/gst-registration-limits-increased).
Content was rephrased for compliance with licensing restrictions.

Note: Google's June 2026 Billing Choice programme (10% fee, external payment links)
launched for the **EEA, UK and US**, expanding to Australia, Japan and South Korea.
**India is not included**, so the 15% India rate applies here. Re-check before
committing to Play Billing.

---

## 7. Decisions needed to finalise the numbers

**D1 — Cash stipends per tier.** Proposed ₹50,000/mo on Pro and ₹5,00,000/mo on
Titan, **non-cumulative** so unused stipend lapses. Non-cumulative is the important
word: it drives monthly re-engagement without inflating balances or creating a
"cancel and keep the cash" exit. Confirm both amounts.

**D2 — Is purchased cash protected from resets?** If seasons or challenges ever
reset wallets, wiping paid-for cash is a refund conversation and a chargeback risk.
Recommend purchased cash is floored and never reset. Decide before the first sale.

**D3 — Titan annual at ₹5,999 (37% off) or ₹6,499 (32% off)?** ₹5,999 gives the
cleaner ₹500/mo effective and pulls harder to annual prepay; ₹6,499 keeps the
discount consistent with Pro's 33%. Worth ₹500/subscriber/yr.

**D4 — Free trial?** 7 days lifts conversion materially and is the norm. Strongly
recommended on **Titan specifically** — ₹799 is a real decision and a trial does
the selling that a feature list can't.

**D5 — Pre-empt the GST cliff or absorb it?** (§3.) Now arriving at ~28,400 users,
sooner than the single-tier model. Easier to launch at the higher price than raise
it later.

**D6 — Refund policy.** Instantly-delivered virtual goods are normally
non-refundable, but Play's rules override yours on Play purchases.

**D7 — Are there ads? DECIDED: no.** No ads anywhere, for free or paid users, ever.
The "ad-free" line has been removed from Pro's benefits — it was promising to
remove something that does not exist, which users notice. Consequence to hold on
to: with no ad revenue, free users cost money and earn nothing, so every rupee has
to come from top-ups, subscriptions or enterprise. That makes conversion the only
lever, and it is an argument for keeping the free tier generous enough to grow the
funnel rather than squeezing it.

**D8 — Web-first or Play-first? DECIDED: web-first, with an in-app handoff.**
Web is one integration and 11 points better margin — worth ₹643/yr on every Titan
annual.

An earlier draft of this section claimed "the app can't legally point them to web."
**That was wrong for India and is corrected here**, because it would have pushed the
whole funnel into Play Billing for no reason:

- The CCI fined Google ₹936.44 crore over Play Store billing conditions. On appeal
  NCLAT upheld the core finding — penalty cut to ~₹217 crore — and reaffirmed that
  mandating Google Play Billing and blocking cheaper alternatives was an abuse of
  dominance. The behavioural remedies require Google to permit third-party billing
  and to stop enforcing **anti-steering** against developers.
- Netflix's own support pages describe exactly this pattern on Android: begin
  sign-up in the app, finish it in a browser.

So an in-app handoff to a web checkout is **contested territory with a binding
Indian remedy behind it**, not a clear violation. Two caveats worth holding:
the NCLAT orders bind Google's conduct rather than rewriting its published global
policy, so a reviewer can still flag the app and you would be arguing the Indian
remedy; and Netflix's leverage in such a dispute is not ours.

Cheap hedge, adopted: frame the in-app entry point as **"Manage subscription on the
web"** rather than a price-led pitch. Identical conversion path and margin, but it
reads as account management rather than steering, which sits inside even a
conservative reading of the policy.

Play Billing stays a later option if revenue ever justifies the second integration.

**D9 — Launch sequence for the two tiers.** Pro can ship on close to today's
feature set. Titan needs real-time data, Greeks, a real IV surface, the strategy
builder and backtesting first. Recommend **Pro at launch, Titan as a second
release** — with Titan announced as "coming" so Pro buyers see the ladder.

**D10 — Founding-member grandfathering.** The 176 existing users signed up to a
product advertised as free. Recommend permanent free **Pro** (not Titan) — costs ₹0
in real revenue, makes a decent announcement, keeps the paid cohort measurable, and
leaves Titan as something they can still be upsold.
