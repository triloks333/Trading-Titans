# Technical Debt

A single, living list of known technical debt in Trading Titans. Keep entries
short and actionable. Link to the relevant `.kiro/specs/*` when a fix is scoped.

> Status legend: 🔴 high · 🟡 medium · 🟢 low / nice-to-have

---

## Architecture & code structure

- 🔴 **`lib/services/supabase_service.dart` is ~3,000+ lines.** It mixes trading,
  wallet, alerts, leaderboard, rewards, and admin calls. Split by domain
  (e.g. `orders_service`, `wallet_service`, `market_service`, `social_service`).
- 🔴 **Duplicated F&O order math.** The futures/short-option margin logic is
  duplicated between the `place_fo_order` client path and
  `executePendingOrders`. Both repeat `... * lotSize * AppConstants.fnoMarginPct`.
  Extract one shared helper so the margin rule lives in a single place.
- 🟡 **Equity buy/sell branches are near-identical.** The long/short open/add/
  reduce branches repeat large blocks. Parameterize into one path.
- 🟡 **Equity orders mutate the wallet from the client**, while F&O goes through
  the atomic `place_fo_order` RPC. Migrate equity to the same server-side RPC
  pattern for consistency and safety.

## Constants & configuration

- 🟢 **`AppConstants` (`lib/core/app_constants.dart`) is the home for magic
  numbers.** Newly centralized: F&O margin %, equity margin %, guest email
  domain, quote cache TTLs, polling intervals.
- 🟡 **Remaining inline `0.15` margin literals** in `supabase_service.dart` (the
  duplicated F&O math, ~8 identical lines) still need to be swapped to
  `AppConstants.fnoMarginPct` — best done together with the dedup above so the
  value is referenced from one place.
- 🟡 **Charge/fee rates** come from `charge_configurations`; ensure the local
  fallback values are also sourced from a single constant.

## Reusable components (good progress)

Shared widgets already extracted and reused app-wide:
`EmptyState`, `ErrorState`, `AppNetworkImage`, `TrendArrow`, `InfoTooltip` +
glossary, `skeleton` (Shimmer/SkeletonCard/ListSkeleton/Dashboard/Portfolio),
`TitanShowcase`, `swipe_button`, `crown_logo`.

- 🟢 Next candidates to extract: the repeated "stat row" (label + value +
  optional color) used in profile/portfolio, and the repeated symbol/instrument
  list-row card used across trade/watchlist/search.

## Folder structure

- 🟡 **`lib/screens/main/` holds ~24 screens flat.** Group into feature folders
  (e.g. `trade/`, `portfolio/`, `wallet/`, `social/`, `account/`, `home/`).
  Use IDE "move file" so imports update automatically; verify with
  `flutter analyze` afterwards.

## Performance (deferred, higher-risk)

- 🟡 Option chain / charts: virtualize rows, lazy-load chart history, defer the
  WebView chart until the advanced chart is opened.
- 🟡 Move order execution / settlement / alert evaluation fully to server cron
  (currently driven by in-app timers).
- 🟡 Reduce unnecessary rebuilds via `Selector`/`ValueListenableBuilder` on
  per-tick price updates.

## Security / business logic (deferred — money paths)

- 🔴 `credit_demo_cash` and `activate_subscription` are callable by any signed-in
  user. Gate behind a verified Razorpay payment (guests are already blocked).
- 🟡 Payment idempotency uses a `LIKE` on notification body — add a `payments`
  table with `UNIQUE(razorpay_payment_id)`.
- 🟡 `validate-order` trusts `body.user_id` — derive the user from the JWT.
- 🟡 Pin `search_path` on the remaining flagged DB functions; rate-limit public
  market endpoints; add CAPTCHA on anonymous sign-ins.

## Testing & CI/CD (deferred)

- 🟡 No CI: add a GitHub Actions workflow running `flutter analyze`,
  `dart format --set-exit-if-changed`, and `flutter test` on PRs.
- 🟡 Add widget/integration tests for the order, portfolio, signup, and guest
  flows; add load/stress tests for the order/quote endpoints.

## Reliability / ops (deferred)

- 🟡 Define RTO/RPO, enable + test PITR, write a DR runbook.
- 🟡 Add uptime monitoring and alerting (error rate, failed payments, stale
  Upstox token) wired to Slack/PagerDuty.
