# Release notes

Play Store "What's new" copy, newest first. Keep each entry under 500 characters
and user-facing (no internal jargon), per `.kiro/steering/release-process.md`.

This file is also read by `scripts/set_update_prompt.py`, which takes the copy from
the **first** `### Play Store` block below and writes it to
`app_config.latest_version_notes`. So a release whose notes live only in some other
file will arm the update prompt with the *previous* release's changelog. Add the
entry here, at the top, before arming.

---

## 1.2.7 (versionCode 51)

The F&O drift fix, finished. 1.2.6 shipped an incomplete version of it.

**1.2.6 did not fix the reported bug.** P&L kept climbing on the live build: ₹1640 at
18:33, ₹1647 at 20:03, ₹1651 at 21:13, with the LTP frozen at ₹232.88 throughout.

The reason is duplication. 1.2.6 routed the *service layer* through a valuation time
that holds still while the market is shut, but `portfolio_screen._estimateFoPrice`
computes its **own** LTP from `DateTime.now()`. The Portfolio F&O tab is the screen
users actually look at, so fixing the service and not the screen changed nothing
visible.

The calculation turned out to be inlined in **seven** places with **three** different
fallbacks for a missing expiry — 0, 7 and 15 days:

| Site | What it drove |
|---|---|
| `fo_positions` OPTION branch | theta on option positions |
| `fo_positions` FUTURE branch | carry on futures positions |
| synthetic future quote | future LTP elsewhere in the app |
| synthetic option quote | option LTP elsewhere in the app |
| monthly futures list | the futures picker |
| option-chain builder | every premium in the chain |
| `portfolio_screen` ×2 | **the reported bug**, current and previous close |

All seven now share `MarketHours.daysToExpiry`. This is the same tax already paid for
five copies of the session window and two copies of the owner email list.

Left alone deliberately: two sites in `_executePendingOrdersInner`. That path is inert
(`_serverExecOnly = true`, and the financial write lockdown would fail it with
`42501`) and `docs/cleanup-task-dormant-on-device-money-paths.md` has it queued for
deletion. Editing an unreachable money path adds risk for no behaviour change.

The tests now reproduce **each site's own formula** and assert it is stable across the
close, rather than only testing the shared helper — which is precisely the gap that
let 1.2.6 pass its tests while the bug survived. The previous-close variant is pinned
too: if the prior-session base drifted, change and change% would move even with a
static LTP.

**How to verify without taking anyone's word:** note Total P&L with the market shut,
check an hour later. It should be identical to the rupee. Before this it moved about
₹4 an hour on a 2250-unit lot.

### Play Store "What's new" (paste this)

Covers **1.2.4 through 1.2.7**. `app_config.latest_version` is still 1.2.3, so no user
has been prompted to take any of them.

```
• Fixed F&O profit and loss drifting on its own while the market was closed.
• Indian market holidays are now respected — no trades or price moves on a closed day.
• Titans Room: a public chat for every trader. Text, photos, sender names and admin tags.
• Tapping a notification now opens the right screen instead of doing nothing.
• New chart tools: rectangle, Fibonacci, arc and pivot points. Tap any candle for its OHLC.
```

---

## 1.2.6 (versionCode 50)

F&O positions stop drifting while the market is shut.

**REPORTED AS** an F&O position's profit growing hour by hour through the evening,
and through an exchange holiday, with the LTP visibly frozen at ₹232.88 in two
screenshots ninety minutes apart. Deployed capital and Total P&L both moved; Day P&L
did not.

**The cause was time, not price.** A future is priced `spot × (1 + r × T)` and an
option by Black-Scholes, and both were evaluated against `DateTime.now()`. T shrinks
continuously, so the synthetic price drifted with the clock even with the spot frozen
and nothing trading. `.inHours` truncation made it step once an hour rather than
smoothly. Per unit the drift is a fraction of a paisa, which is exactly why the LTP
looked static — but a 2250-unit ONGC lot turned it into about ₹4 an hour on the P&L
line, and because the position was short, a falling futures price displayed as
growing profit. The observed ₹7 over ninety minutes is two hourly steps.

This was never holiday-specific. It happened every evening, every weekend and after
every close, for as long as that code has shipped. The market being closed is simply
what made it visible.

**The fix** is `MarketHours.valuationTime()`: derivatives are now valued at the live
clock while a session is open, and at the most recent session CLOSE once it is not.
So the same position values identically at 18:33 and 20:03, overnight, at weekends
and across a holiday — while a live session still reprices normally, which the tests
assert in both directions. The five call sites that each inlined
`expiry.difference(DateTime.now()).inHours / 24.0`, with two different fallbacks, now
share one helper.

**The app also honours exchange holidays now.** `MarketHours` reads the
`market_holidays` table on every foreground, so the Indian session can be closed
server-side with no further release and the badge stops claiming "Market Open" on a
day nothing can trade. An empty list degrades to the old weekends-only behaviour, so
an offline launch never invents a closure.

Server-side, already live and independent of this build: a trigger on `orders`
declines the execution engine's claim on a holiday, so nothing fills even on 1.2.4
and 1.2.5, and a second trigger freezes Indian quotes so prices stop moving.

Note for the record: 1.2.4 and 1.2.5 both shipped without `app_config.latest_version`
being raised, so no user was ever prompted to take either. The copy below therefore
covers 1.2.4, 1.2.5 and 1.2.6 together.

### Play Store "What's new" (paste this)

Covers **1.2.4, 1.2.5 and 1.2.6**, since nobody was prompted to take the first two.

```
• Fixed F&O profit and loss drifting on its own while the market was closed.
• Indian market holidays are now respected — no trades or price moves on a closed day.
• Titans Room: a public chat for every trader. Text, photos, sender names and admin tags.
• Tapping a notification now opens the right screen instead of doing nothing.
• New chart tools: rectangle, Fibonacci, arc and pivot points. Tap any candle for its OHLC.
```

---

## 1.2.5 (versionCode 49)

The public chat room, and the sender names it shipped without.

**1.2.4 went out without an entry in this file.** Its copy was written to
`docs/whats-new-1.2.4.md` instead, which nothing reads — exactly the failure the
header above warns about. `latest_version` was never raised either, so it is still
`1.2.3` and **no user was ever prompted to take 1.2.4**. That is why the copy below
covers 1.2.4 as well as 1.2.5: in practice almost everyone is jumping straight from
1.2.3, and there is precedent for a combined block in the 1.2.2 entry below.

**Titans Room.** One public room for all users, carrying text and photos. Links are
admin-only and that is enforced by a database trigger, not by the UI, so no write
path can miss it — along with a per-user mute, a report button, admin delete and a
rate limit. Guests can read the room but not post; they get an upgrade prompt where
the composer would be, because an anonymous account costs nothing to create and
abandon, which is what makes a public room worth abusing.

**Names on messages, which 1.2.4 was missing.** 1.2.4 rendered a sender's name only
on other people's messages, WhatsApp-style, so a room with a single sender showed
none at all and looked broken. 1.2.5 keeps that rule but adds the rest of the
pattern: consecutive messages from one person are grouped and only the first is
labelled, and the three admin accounts wear an ADMIN tag. The tag matters because
admins are the only accounts allowed to post links here, so users need to tell a
genuine announcement from someone claiming to be one.

**Sending was broken for a few hours after 1.2.4 shipped**, and was fixed
server-side with no release. `alter default privileges` from the September lockdown
means every new table in `public` arrives SELECT-only, so `chat_messages` had an RLS
insert policy but no table grant — and a missing grant is checked before RLS, so the
policy never ran. Anyone on 1.2.4 can post now without updating.

**Notification taps go somewhere.** Previously nothing was wired to a tap on a
system-tray push. All three paths are now handled — background, terminated and
foreground — and the push carries the same route names the in-app button uses, so
the two cannot drift apart.

Also: country and state in Settings, an admin analytics screen, chart rectangle /
Fibonacci / arc / pivot-point tools, OHLC on tap, remembered timeframe and style,
and a real explanation instead of "User is banned" for a banned account.

Voice notes are deliberately absent. The schema, storage bucket and send path all
accept them, but recording needs microphone permission and `core/legal.dart`
promises users "no microphone or camera access beyond a photo you deliberately
choose to upload". Changing that re-prompts every existing user for consent, because
`termsVersion` is `lastUpdated`.

### Play Store "What's new" (paste this)

Covers **1.2.4 as well as 1.2.5**, since nobody was prompted to take 1.2.4.

```
• Titans Room: a public chat for every trader. Text, photos, sender names and admin tags.
• Tapping a notification now opens the right screen instead of doing nothing.
• New chart tools: rectangle, Fibonacci, arc and pivot points. Tap any candle for its OHLC.
• Your chart timeframe and style are remembered between sessions.
• Set your country and state in Settings.
```

---

## 1.2.3 (versionCode 47)

Derivatives for everyone, timeframes that mean what they say, and drawing on the
chart.

**Futures and options are free.** The plan check in `place-order` is deleted, not
made conditional. It only fired when `app_flags.monetization_enabled` was on, so a
dormant gate would have surprised the next person to flip a flag — which is exactly
how it surprised us. Removing the check needed no app release and is already live;
`monetization_enabled` still governs the wallet top-up card, the Subscribe screen
and the plan badges, so top-ups and plans keep selling. Note what this costs:
`docs/monetisation-pricing.md` sells index F&O as the headline Pro feature, so Pro
now stands on monthly demo cash, US stocks, unlimited autopsies with advice,
unlimited price alerts and the badge.

**The timeframe row was the bug users reported.** The bar sizes were right; the row
was not. It mixed two ideas — `1m 5m 10m 1h` named bar sizes while
`1D 1W 1M 3M 1Y 5Y` named spans:

    `1D` drew 5-minute bars over one day.  `5m` drew 5-minute bars over five days.
    `1M` drew hourly bars over one month.  `1h` drew hourly bars over three.

Tap between either pair and the candles are the same size, only the span moves. In
a row opening `1m 5m`, every chip reads as a bar size, so the ones that silently
changed something else looked broken. The "no two buttons draw the same picture"
check passed throughout, because it compared interval *and* range — it was
measuring the wrong thing. The row is now seven bar sizes and nothing else, and the
check compares intervals alone.

**Crypto charts were drawing whatever CoinGecko felt like.** `coingecko.ts`'s
`fetchHistory` takes an `interval` argument and never reads it: it maps the range to
a day count, calls `/ohlc`, then downsamples to a fixed 120 candles. Measured — a
`1m` request came back in 30-minute bars, `5m` in 4-hourly. Crypto history now comes
from CoinDCX, which serves a named interval and is the venue `market-quote` already
reads the live price from. That closes a second seam: the chart body was CoinGecko
while its right-hand edge was CoinDCX, two venues about 12% apart on Indian crypto.
Verified at the time of writing — `I-BTC_INR` closed at ₹7,895,150 against
`quotes_cache`'s ₹7,895,446, 0.004% apart.

CoinDCX serves only `1m`, `15m`, `1h` and `1d`; `5m`, `30m` and `1w` are rolled up
from those server-side, first open, last close, extremes of all. The rollup lives in
the edge function rather than the chart because which interval you must fetch to
build a 5-minute bar is knowledge about a venue, and a chart should not carry a
table of what each provider can serve.

| change | needs binary |
|---|---|
| Futures and options free for every account | no — already live |
| Read notifications deleted 7 days after reading | no — already live |
| Crypto intraday candles from the right venue | no — already live |
| Timeframe row rebuilt as seven bar sizes (1m…1W) | yes |
| 15m and 30m added | yes |
| Horizontal levels and trendlines, drawn on the chart | yes |
| Admin can attach a button to a notification | yes |
| Request a Feature reachable from a notification | yes |

**Drawings** are anchored in time and price, never pixels, so a level drawn on the
1h chart is the same level on the 5m one and survives pan, zoom and rotation.
Stored per symbol in localStorage, same store and reasoning as saved indicator
templates. Two tools rather than Zerodha's six: rectangle and Fibonacci are new
maths on the same foundation, but support and resistance is what people draw, and
two that feel right beat six that are fiddly under a thumb.

Three bugs the browser caught that the type checker could not: a tool stayed armed
after drawing, so the overlay kept swallowing gestures and the chart silently
stopped panning; the overlay spanned study panes, so a gesture in the RSI area was
handed to `coordinateToPrice` on the price series and the drawing silently failed to
record; and `setPointerCapture` throws when the pointer id is not active, which was
abandoning the whole gesture.

**Notifications** gained `read_at`, stamped by a trigger on the false→true
transition only, so re-reading does not restart the clock and unreading clears it.
The trigger is why every already-shipped build gets the sweep without updating —
they only set `is_read`. The 10,052 existing read rows were backfilled to `now()`
rather than `created_at`: back-dating would have deleted 9,869 of them the instant
the migration landed, inventing a fact in order to destroy data. They age out over
the following week instead. The sweep is capped at 5,000 rows a run so it cannot
hold a long transaction over a table the app reads on every launch.

Still open: `Money._fmt` prints `$` when the display is USD and no FX rate is
available, so the header can read `$1322` for rupee values while the chart honestly
reads `₹1322`. Fixing it changes formatting on every screen, so it is not bundled
into a chart release.

### Play Store "What's new" (paste this)

```
• Futures and options are now free for everyone — no plan needed
• Chart timeframes rebuilt: 1m, 5m, 15m, 30m, 1h, 1D and 1W each now draw the bar size you pick
• Crypto charts finally have real intraday candles, priced from the same feed your trades fill at
• Draw support and resistance levels and trendlines on any chart — they stay saved per instrument
• Notifications you have read now clear themselves after 7 days
```

---

## 1.2.2 (versionCode 46)

Our own charts, on our own prices.

Every chart in the app was a WebView pointed at `tradingview.com/chart`. That meant
downloading a third-party web app on every open — no chart at all on a weak
connection — and when it did load it drew somebody else's feed, so the candles
could disagree with the price we fill orders at and nothing on screen explained the
gap. It also needed an ~80-entry hand-maintained table mapping our symbols onto
TradingView venues, a spoofed user agent, and injected CSS to hide the parts of
their site we did not want.

The replacement is `app/assets/chart.html`: one self-contained file built from the
new `chart/` package, holding the charting library, nineteen indicators, the
saved-strategy sheet and the period selector, with no external request. History
comes from our `market-history` function; the live right-hand bar comes from
`quotes_cache`, which is the table `execute-pending-orders` prices fills from.

The web app renders from the same package, so there is now one chart in this
product instead of three that disagreed.

| change | needs binary |
|---|---|
| Charts drawn from our own data, bundled in the app, no third-party site fetched | yes |
| Nineteen indicators, with editable parameters | yes |
| Indicator sets saveable under a name, one starrable to open charts with | yes |
| 1m, 5m, 10m and 1h timeframes added to the existing 1D–5Y spans | yes |
| Chart follows the display-currency preference, at the rate the header uses | yes |
| Option charts draw their underlying instead of failing (Yahoo has no contract listing) | yes |
| Live bar comes from the same table order fills are priced from | yes |
| Same chart on the web app | no |
| ~80-entry TradingView venue table, user-agent spoof and CSS injection deleted | yes |

**Currency.** Prices are converted once at the data boundary, so the axis, the
crosshair, the legend, the last-price badge and every price-pane indicator land in
the same units. The rate comes from `CurrencyService` — the same pair `Money`
formats the header with — rather than being fetched by the chart, because a header
and a chart disagreeing about one instrument reads as a pricing bug. With no rate
available the chart draws the instrument's own currency and labels it honestly;
the axis label is derived from the conversion factor, not from the preference, so
it cannot claim dollars over rupee values.

Known, untouched: `Money._fmt` still prints `$` when the display is USD and no
rate is available, so the header can read `$1322` for rupees while the chart reads
`₹1322`. The chart is the honest one. Fixing `Money` changes formatting on every
screen, so it is not bundled into a chart release.

**Timeframes.** `10m` is not a Yahoo interval — it answers 400 — so that view
fetches 5m and rolls pairs up, taking the first open, the last close and the
extremes of both. Crypto gets no intraday buttons: CoinGecko ignores the interval
and picks granularity from the day count, returning 30-minute bars for a `1m`
request and 4-hour bars for `5m`, so a bar-size button there would be mislabelled.
That also means crypto's existing 1D/1W/1M spans are mislabelled today; it predates
this release and is recorded in `chart/src/core/periods.ts` with its upgrade path.

Saved strategies are per device: one saved on the phone will not appear on the web
app. That is deliberate for now — it works for guests, offline, with no production
table or migration. The upgrade path is a `chart_templates` table, confined to one
file.

Quote polling inside the chart runs once a minute, not every four seconds like the
screen header: `refresh-quotes` rewrites `quotes_cache` on a one-minute cron, so a
faster poll re-reads the same number and costs an edge function invocation for any
symbol outside the ~74-symbol refresh universe.

### Play Store "What's new" (paste this)

The copy below covers **1.2.1 as well as 1.2.2**. versionCode 45 was built but
never uploaded, so the live build is still 1.2.0 (versionCode 44) and everyone
updating lands on 1.2.2 carrying both sets of changes. Shipping the chart notes
alone would hand users dollar billing and single-sign-in checkout with nothing on
the listing about either.

```
• Brand-new charts built by us — they open instantly, even on a weak connection
• 1m, 5m, 10m and 1h timeframes alongside 1D to 5Y
• 19 indicators — RSI, MACD, Bollinger Bands, Supertrend — and save your own sets by name
• Charts follow your chosen currency, and price off the same feed your orders fill at
• Members outside India are billed in US dollars, with dollar pricing on every plan
• Buying a plan or top-up no longer needs a second sign-in
```

---

## 1.2.1 (versionCode 45)

Dollar pricing for members outside India, and buying without a second sign-in.

Why this is 1.2.1 and not another 1.2.0: `app_config.latest_version` was already
armed to `1.2.0`. The soft-update window is
`min_supported_version <= installed < latest_version`, so a second binary carrying
the same version name leaves that window empty for everyone already on 1.2.0 and
**no user is ever prompted to take it**. A new build needs a new version name, not
just a new version code.

| change | needs binary |
|---|---|
| Members outside India are billed in US dollars, at dollar price points | yes |
| Plan prices show the exact amount charged, not an FX conversion of the rupee price | yes |
| Prices carry an `≈` equivalent in the member's chosen display currency | yes |
| Buying no longer opens a login wall in the browser | yes |
| Login-free checkout page at /app/pay | no |
| Web plans page priced in the member's own currency | no |
| Webhook rejects a payment whose currency differs from its order | no |

Billing currency follows residency (`profiles.location`), not the display
preference. Nine accounts are in India while reading the app in dollars; for them
the price tag leads with the rupee charge and shows the dollar equivalent beside
it, because the dollar price points are separate price points rather than
conversions, and charging an Indian resident in dollars would cost them more and
complicate GST.

### Play Store "What's new" (paste this)

```
• Members outside India are now billed in US dollars, with dollar pricing on every plan
• Buying a plan or top-up no longer sends you through a second sign-in — payment opens directly
• Plan prices now show the exact amount charged, with the equivalent in your chosen currency beside it
• Taxes included in every price, as before, with no charge added at checkout
```

---

## 1.2.0 (versionCode 44)

The League tab, a rebuilt plans screen, and a sign-out bug that reached across
devices. Full engineering detail in `docs/release-notes-1.2.0.md`; this entry is
the user-facing copy.

| change | needs binary |
|---|---|
| League tab — the leaderboard, previously unreachable in every shipped build | yes |
| Plans and top-ups rebuilt; monthly in the app, annual on the website | yes |
| PRO / TITAN badges beside your name on the profile and the League | yes |
| Bottom navigation rebuilt so six tabs fit legibly | yes |
| Terms and Privacy updated for optional paid plans, renewals and refunds | yes |
| Web sign-out no longer ends your session on the phone | yes |
| Leaderboard returning only your own row | no |
| Web app made usable on a phone | no |

### Play Store "What's new" (paste this)

```
• New League tab — a proper leaderboard showing your rank, the top three and everyone else
• Signing out on the web no longer signs you out on your phone
• Plans and top-ups redesigned, with live pricing and GST included
• PRO and TITAN badges now show beside your name on your profile and the League
• Cleaner bottom navigation with labels on every tab
• Updated Terms and Privacy Policy to cover optional paid plans, renewals and refunds
```

(439 characters, limit 500)

The League tab leads because it is the only genuinely new place to go. The
cross-device sign-out is second: it is the one thing users could have hit and been
annoyed by. Terms last, because it needs no action but should not be silent.

---

## 1.1.9 (versionCode 42)

One user-visible bug and one wording fix, on top of a large server-side security
change that is already live for everyone including older builds.

The bug: editing a pending limit order changed the price on screen but not the
price the engine matched against, so a modified order went on waiting at its
original limit. Reported as "the order didn't fill even though the price crossed" —
and the engine was right every time; the screen was wrong.

| change | needs binary |
|---|---|
| Editing a pending order now moves the trigger the engine actually uses | yes |
| Pending orders labelled "Limit Price" rather than "Price" | yes |
| Modify and cancel routed through server-side endpoints | yes |
| Money, holdings, positions and order records made server-authoritative | no |
| Existing mis-set limit orders repaired in place | no |

### Play Store "What's new" (paste this)

```
• Editing a pending order now updates the price it actually triggers at — a changed limit used to be ignored, leaving the order waiting at its original price
• Pending orders show "Limit Price" instead of "Price", so a resting order is no longer mistaken for a filled one
• Order changes and cancellations are handled on our servers for better reliability
• Security hardening across wallet, holdings and order records
```

(418 characters, limit 500)

Four bullets. The first one leads because it is the only thing a user actually
noticed and complained about. The label change is second because it is what made
the bug look like a bug — a resting order and a filled one showed the same word.
The security bullet is deliberately last and deliberately vague: it is real work,
but it landed server-side and needs no action from anyone.

---

## 1.1.8 (versionCode 41)

A large batch: consent and disclosure on the auth screens, plus fixes for four
separate user complaints — expired F&O still on the board, option premiums far from
the real market, limit orders that would not fill, and P&L that disagreed with
itself between screens.

Most of it is server-side and is already live for users on older builds. The
version NAME stays 1.1.8 as requested; only the build number moved, 40 to 41,
because 40 was built but never rolled out and Play refuses a code it has seen.

| change | needs binary |
|---|---|
| T&C + Privacy consent and the virtual-money disclaimer on both auth screens | yes |
| 117,247 expired F&O contracts hidden, with a daily sweep after each expiry | no |
| Expiry picker stops offering dates that have already passed | yes |
| NSE bhavcopy sync repaired — real premiums and open interest, 8 days stale to current | no |
| Option chain says premiums are estimated, and shows the exchange's last close | yes |
| Futures contract symbols no longer open a chain around a ₹0.00 spot | no |
| Limit orders fill when the market crosses them, even if the price cache lagged | no |
| Crypto perpetual orders can be priced at all (one had been stuck 6 days) | no |
| Quote refresh no longer fails silently or rate-limits itself | no |
| Total P&L shows its minus sign; Dashboard and Portfolio now agree | yes |
| Order details show gross → charges → net instead of one ambiguous figure | yes |

### The four complaints, and what was actually wrong

**Expired F&O still showing.** `instruments` never deletes a row, and all 117,247
already-expired futures and options were still flagged tradeable, going back to
2026-06-09. They are now flagged off, with a daily sweep at midnight IST — after
settlement, and never before a contract's own expiry day is over. Flagged rather
than deleted on purpose: lot-size lookup ignores the tradeable flag, so deleting
the rows would have settled open positions on expired contracts at a lot size of 1.

**Option premiums far from the market.** The daily NSE bhavcopy download had been
returning 404 for five straight trading days. The cause was not the date logic:
NSE's CDN serves a 404, not a 403, to requests without a browsing context, and the
same URLs returned a 900KB file from a normal connection. The sync now primes NSE
session cookies first and walks back through recent dates instead of giving up
after today. A second failure was hiding behind it — the import then died on
"numeric field overflow", because turnover was capped at ₹1e13. Result: DIXON
15000 CE went from a stale ₹427.95 to Friday's real ₹273.25.

Premiums shown in the chain are still Black-Scholes estimates off the live spot,
and deliberately so: that is the same number the fill engine charges, so an order
cannot fill at a price the user never saw. What was missing was saying so. The
chain now states it, and each strike's detail shows the exchange's own last close
next to the estimate.

**Limit orders not filling.** Reported on an AEROENTER sell limit at ₹145.80 that
sat through a print above it. The engine refuses to price a fill off a quote older
than ten minutes, which is right, but it then gave up — and the refresher is
best-effort, so one failed upstream pass left that symbol behind. The engine now
fetches a live quote before writing an order off. The refresher itself was doing a
74-wide simultaneous fan-out and swallowing every per-symbol error, so a pass that
refreshed 32 of 54 symbols looked identical to a healthy one; it now runs a bounded
pool, retries, and reports which symbols failed. That report immediately surfaced
two real faults on its first run: Supabase was rate-limiting our own quote function
(three internal passes per minute, now one), and a crypto perpetual symbol had been
404ing forever.

**P&L disagreeing between screens.** Four distinct defects, none of them arithmetic:
the Portfolio card formatted losses with `.abs()` and only prepended a sign when
positive, so a loss rendered as "₹3654 (-2.27%)" in red; the Dashboard summed every
holding while Portfolio summed only open ones, so closing a trade made the two
screens disagree; order details showed gross realized P&L while the Portfolio showed
the same trade net of charges; and "Charges reduced your return by X%" divided one
order's charges by gross P&L, so a ₹1 win against ₹20 brokerage announced
"2000.0%". Net of charges is now the canonical figure everywhere, and order details
show the full arithmetic instead of asking the user to trust a total.

### Consent, in detail

Two additions, both on the sign-in AND sign-up screens:

1. A mandatory checkbox — "I accept the Terms & Conditions and Privacy Policy" —
   with both names tappable, opening the full documents through the sheet Profile
   already uses. Acceptance is recorded server-side with the policy revision date,
   so we can say which text a user agreed to and when.
2. A standing disclaimer at the foot of the page, separate from the checkbox:
   everything is simulated, we are not a registered broker, and market data may be
   delayed.

The scope decision worth recording: an account can be created from BOTH screens by
four routes — email/password and Google on sign-up, Google and Guest on sign-in.
A checkbox on the sign-up screen alone would have been bypassable in two taps, so
all four are gated. Email/password SIGN-IN is deliberately not gated: that user
accepted at signup and it is already recorded, so re-asking every login would be
friction with no legal value.

Acceptance is written by the `accept_terms` RPC. It has to be an RPC rather than a
direct write, because 1.1.7's security work revoked client UPDATE on `profiles`.
Accounts created before this build have `terms_accepted_at` NULL — they are not
retro-consented, and the column tells you exactly who has and has not accepted.

### Play Store "What's new" (paste this)

```
• Expired F&O contracts no longer appear anywhere in the app
• Option premiums and open interest now use the latest NSE data
• Limit orders no longer sit unfilled once the market passes your price
• Profit & loss now matches across Portfolio, Dashboard and order details, with a breakdown showing charges
• Terms & Conditions and Privacy Policy acceptance added at sign-up, plus a clear notice that all money here is simulated
```

(440 characters, limit 500)

Five bullets, ordered by how many people complained. The consent work is last
despite being the only thing that strictly needed this build: it is the change
users asked for least. The P&L bullet names all three screens on purpose — the
complaint was specifically that they disagreed with each other, so naming them is
what tells a user their issue is the one that got fixed.

---

## 1.1.7 (versionCode 39)

A correctness release: six production bugs, all found while investigating one
user report that a sell limit order placed at ₹281 filled at ₹281.40.

Most of the work is server-side and already live regardless of this build. Two
things genuinely need the new binary: the Indian session close (the Flutter copy
of the window closed at 3:15 PM) and the F&O lot size shown on the order screen.
Everything else — fill prices, charges, stale-quote protection — is enforced by
the engine and applies to users on older builds too.

What changed, and whether a user can see it:

| change | user-visible |
|---|---|
| Resting limit orders fill AT their limit, not at the polled price | yes, in the fill price and notification |
| Indian session closes at 3:30 PM, not 3:15 PM | yes, the last 15 min now works |
| F&O lot sizes resolved by exact underlying (NIFTY 65, not 25) | yes, on the order screen |
| SENSEX lot size 20 instead of 1 | yes |
| STT and exchange charges on 2026 rates | yes, in charges |
| Stale-quote guard, 24/7 quote refresh, crypto execution gap | indirectly, fewer odd fills |
| Admin "Give Reward" RLS fix, profiles privilege escalation | no, admin/security only |

### Play Store "What's new" (paste this)

```
• Limit orders now execute at exactly the price you set
• F&O lot sizes corrected — NIFTY is now 65, Sensex 20
• Trade right up to the 3:30 PM market close
• Charges updated to current 2026 STT and exchange rates
• More reliable live prices across stocks, US stocks and crypto
```

(272 characters, limit 500)

Deliberately omits the security fixes. The rewards RLS bug and the profiles
privilege escalation are not user-facing, and advertising a closed escalation
hole to everyone including the users who could have exploited it is not something
a release note should do.

The lot size and market close bullets are the two worth leading with: those are
the two a user reported directly, and both were visibly wrong in the UI.

---

## 1.1.6 (versionCode 38)

Builds on 1.1.5+37, which is live on Play, so this copy covers only the guest
upgrade. One entirely new feature: a guest can attach a Google account or an
email and password from Profile and keep everything. New guests start at ₹5,000
instead of ₹11,000 and are paid the remaining ₹6,000 once, on upgrade. The 44
guests who signed up before this build keep their ₹11,000 and are not paid the
bonus.

### Play Store "What's new" (paste this)

```
• Guests can now make their account permanent — sign in with Google, or set an email and password
• Everything carries over: portfolio, orders, rewards and your login streak stay exactly as they are
• Upgrading credits ₹6,000 demo cash, taking you to the full ₹11,000
• New guest accounts start with ₹5,000. Existing guests keep the balance they already have
```

(358 characters, limit 500)

Four bullets rather than five: everything else in this build is server-side and
invisible to a user, and padding the list with the ₹5,000 change stated twice
would read as filler.

After the Play rollout, two follow-ups:

1. `python scripts/set_update_prompt.py` so `app_config.latest_version` catches
   up. It still reads 1.1.2, which is why nobody was ever prompted to move to
   1.1.5 — the prompt compares version *names*, so a stale value silently
   notifies no one.
2. Enable the upgrade nudges. They ship switched off so no guest is told to visit
   a screen their installed build does not have:

   ```sql
   select cron.alter_job(
     (select jobid from cron.job where jobname = 'notify-guest-upgrade'),
     active := true);
   ```

---

## 1.1.5 (versionCode 37, live on Play)

Supersedes 1.1.4+36 and 1.1.3+35, neither uploaded — the
wallet ledger below landed after 1.1.4 was built and replaced it.

Last build users actually received is 1.1.2+34, so the copy covers everything
since then. The free-app, US-stocks, currency and live-price items were announced
in the 1.1.2 entry below and are not repeated.

### Play Store "What's new" (paste this)

```
• Wallet now has its own money history: credits, rewards and trade settlements, with a running balance
• Fixed duplicate notifications — one alert per order, not two
• Order history opens on today. Tap the date to browse any earlier day
• Pending orders stay in view until they fill or you cancel them
• The app now tells you when a new version is available
```

(357 characters, limit 500)

Dropped from the draft to stay within five bullets: the rating prompt (the only
line offering the user nothing) and "steadier when your connection drops" (the
504 fix was a stuck spinner, not something users could name). Both still ship.

### Wallet has its own transaction history

The Wallet tab's "Transaction History" was rendering `getOrders()` — the order
list, restyled. It duplicated the Orders screen and still omitted every non-trade
movement, because until now no record of those existed: signup bonus, referral
credit, claimed rewards and top-ups were all bare
`UPDATE profiles SET wallet_balance = ...` with nothing left behind.

New `wallet_transactions` ledger (`20260821000000_wallet_transactions_ledger.sql`,
applied and verified) records every balance change with amount, balance before and
after, kind and description. The Wallet now shows that, with a running balance so
the list reconciles against the figure at the top, plus an "Order history" link so
trade detail stays one tap away.

**No money path was modified to do this** — not the execution engine, not
`place_fo_order_transaction`, not `claim_reward` / `credit_demo_cash` /
`activate_subscription` / `apply_referral_code` / `handle_new_user`. Balances are
captured by *observing* `profiles.wallet_balance` from an `AFTER UPDATE OF
wallet_balance` trigger, so every existing path — and any future one — is recorded
for free. Four safety properties follow:

1. The ledger is never the source of truth; `profiles.wallet_balance` stays
   authoritative and these rows are derived from it.
2. A ledger failure cannot roll back a money movement. The whole trigger body is
   inside `BEGIN ... EXCEPTION WHEN OTHERS`, so if the table is dropped, locked or
   full, the balance update still commits and the user misses one history row.
   Losing a history row is acceptable; rolling back someone's trade for
   bookkeeping is not.
3. Clients cannot write to it: RLS grants SELECT only, and the sole writer is the
   SECURITY DEFINER trigger. Verified — an anon INSERT is refused with 401.
4. Idempotent, and the backfill is guarded by `NOT EXISTS` so re-running can never
   double-count.

- Existing accounts were backfilled with one "Balance brought forward" line at
  their current balance, so the statement reconciles from day one rather than
  starting mid-story. **All 102 accounts** got exactly one, and every one
  reconciles to the cent.
- `kind` is inferred from what else changed in the same statement
  (`total_realized_pnl` moved → a trade settled; `referred_by` set → signup bonus;
  any debit → a trade, since nothing else in the app debits a wallet).
  **ponytail ceiling:** three credit sources — claimed reward, self top-up, and
  being credited as the referrer — collapse into one `credit` label, because each
  only touches `wallet_balance`. Upgrade path without touching the trigger: a
  caller runs `set_config('app.wallet_reason', 'reward_claim', true)` before its
  UPDATE and the hint is used verbatim.
- The Wallet no longer calls `getOrders()` at all, which *removes* the 504 crash
  path patched earlier rather than merely guarding it.
- `scripts/verify_wallet_ledger.py` added, following the existing `verify_*.py`
  convention: checks table/columns, backfill coverage, that no account has a
  duplicate opening row, that the newest `balance_after` equals the live
  `wallet_balance`, and that an anon INSERT is refused. That reconciliation check
  doubles as a trigger liveness test — if the trigger ever stops recording, the
  ledger and the balance drift apart and the check goes red.

### Orders page is now day-scoped

`getOrders()` capped at 50 rows with no separation, so a few active days buried
today's fills and anything older than 50 orders was simply unreachable. The page
now opens on **Today** with a `‹ Today ›` bar: arrows step a day, the label opens
a date picker floored at the account's creation date. Filtering happens in the
query, so long histories are never fetched.

- Day boundaries are **IST**, not device-local. The backend already books
  day-scoped things (`green_day`, login streaks) `AT TIME ZONE 'Asia/Kolkata'`,
  so keying off the phone's timezone would let a user abroad disagree with the
  server about which day a fill belongs to. Helpers live in `MarketHours`
  (`istDate`, `istDayRangeUtc`) next to the existing IST conversion.
- **Live pending orders stay pinned to Today.**
  `expire_pending_stock_orders()` filters on `market <> 'crypto'`, so a crypto
  limit order is never auto-cancelled and outlives the day it was placed.
  Date-scoping it out of the current view would hide its only Edit/Cancel
  controls, so the Today query is `created_at >= todayStart OR status = 'pending'`.
- The five duplicated `getOrders()` call sites in the screen collapsed into one
  `_reload()`. Not cosmetic: with a selected day in play, any missed site would
  silently revert to all-time.

### Update prompt actually reaches users now

The "update available" dialog never fired, and it was not a code bug. Nothing in
the app asks Google Play anything — the prompt is driven entirely by
`app_config.latest_version`, which has to be raised every release. The window is
half-open (`min_supported <= installed < latest`), so leaving the row at the
version you just shipped puts every user on the previous build exactly on the
closed end and nobody is ever prompted.

- **`release-process.md` now carries this as a required step** (section 3), and
  `scripts/set_update_prompt.py` run with no arguments reads the version name
  from `app/pubspec.yaml` — stripping the `+35`, which would fail the client's
  `x.y.z` validation and silently disable gating. Run it *after* the rollout is
  live, never before.
- **Fixed: the prompt only ever ran once, 2s after launch.** The resume
  re-evaluation in `AppLifecycleGate` could arm the flag mid-session with
  nothing left to show the dialog, so it never appeared until a full restart.
  `MainNavigation` now listens to `AuthService` and offers it on the rising
  edge, guarded to once per session — which also stops a barrier tap (no snooze
  written) from immediately re-opening it.
- **Fixed: the 24h snooze was global, not per-version.** Dismissing one
  release's prompt also silenced the next release's for 24h, exactly wrong for a
  hotfix. The key is now `soft_update_dismissed_time_<version>`.
- `min_supported_version` is still `1.0.0`, so the blocking gate remains dormant
  and only the dismissible prompt is doing any work. Raising it locks out every
  older client immediately, so it stays a deliberate manual decision.
- `evaluateConfig` had **zero** test coverage (its property tests were the
  optional ones in the notification-sounds spec and were skipped). Now 17 tests,
  including the `installed == latest` case that made this look broken.

### Rating prompt

On the second consecutive day of use (`login_streak >= 2`) the app asks for a
Play Store rating. "Rate now" opens the listing and suppresses it permanently;
"Remind me later" defers 14 days, re-applied on each dismissal.

- Reuses the existing `SoftUpdateDialog` shape and its store-launch failure
  handling; the timing decision is a pure `RatePrompt.shouldShow` alongside
  `selectActiveGate` / `evaluateConfig`.
- Yields to the update prompt and the reward celebration, and writes no snooze
  when it stays silent, so skipping costs nothing.
- "Rated" means "tapped Rate now" — Play gives no callback confirming a review
  was left. State is device-local, so a reinstall asks again. Upgrade path for
  both is the Play In-App Review API, which replaces the two-button dialog with
  Google's own sheet and is quota-limited.

### Every order and price alert arrived twice in the tray

Users reported paired notifications: "Order Pending" + "Order Placed (Pending)",
then "Order Executed" + "Buy Order Executed". The formatting gave each source
away — `200` vs `200.0`, `₹2964.8` vs `₹2964.80`.

Two producers reached the tray for one event. The server writes a `notifications`
row ("Order Pending" from `place-order`, "<Side> Order Executed" from the
`notify_order_executed` trigger), and `trg_push_on_notification` turns every such
row into an FCM push. The app *also* fired its own local notification from
`order_entry_screen`.

- **Why the earlier `order-notifications-and-runaway-lots-fix` missed it.** That
  spec deliberately kept the local push, on the stated premise that "the trigger
  does not drive FCM and the push writes no feed row, so it is not a feed
  duplicate". The second half was right, the first half was not —
  `push_on_notification_insert` makes every row a push. So the *feed* was fixed
  correctly (still one row per event) while the *tray* only went 3 → 2.
- **Fix: the client no longer posts order notifications.** The block in
  `order_entry_screen` is gone. The server path is strictly more capable — it
  works when the app is closed and is the only path that can announce a pending
  limit order filling later.
- **Price alerts had the identical bug, unreported.** `evaluatePriceAlerts()`
  inserted a row *and* posted a local notification, so every triggered alert
  arrived twice too. The local one is gone; this also makes the client path match
  the server `evaluate-price-alerts` cron, which already relied on the row alone.
- **Pending orders were playing the executed sound.** `place-order` wrote
  `action_type: "order"`, which `channelFor()` maps to `order_executed_channel_v1`.
  Now `"order_pending"`. **Deployed** — `place-order` version 5, `verify_jwt: true`
  preserved, deployed source verified to match the repo and a live request
  confirmed the function boots and its `../_shared/us_market.ts` import resolves.
- **Paired change so nothing broke:** `notifications_screen` gated tap-through to
  the stock screen on `action_type == 'order'`, so the new value would have
  silently killed it. It now accepts both. The feed icon comes from
  `_iconForTitle(title)`, not `action_type`, so it was unaffected. Old rows with
  `action_type: 'order'` stay tappable, so a partial rollout is safe either way.
- The immediate executed-vs-pending signal the local push provided is now in the
  confirmation snackbar, so it is not delayed by the server round trip.
- `_categoryFromType` became the public `categoryFromType`, plus a new
  `channelIdFor`, because the sound is now decided entirely by
  `action_type` → `channelFor()` (TS) → `data.type` → category. That chain
  crosses two languages with nothing checking the ends agree, so 13 tests now pin
  it — including that pending and executed resolve to different channels.

Known gap: a device where Firebase failed to initialise has no FCM, so it now
gets no tray notification for its own orders (it previously got the local one).
The snackbar and the in-app notifications list still cover it. Not worth
reintroducing a second producer behind a condition that is hard to get right.

### Supabase 504s were being filed as crashes

Crashlytics showed 15 "crashes" from `PostgrestException(code: 504, Gateway
Timeout)`. Not a code bug and not a real crash: a completed HTTP round trip
carrying a server-side timeout. `FirebaseService.isTransientNetworkError` only
recognised *socket-level* failures (DNS, dropped connections), so a 504 matched
nothing, was classified non-transient, and both Flutter error handlers reported
it fatal. The app almost certainly never died — `PlatformDispatcher.onError`
returns `true` — so what users actually saw was a spinner that never stopped.

- **Classifier now understands server statuses**: `PostgrestException`,
  `FunctionException`, `AuthException` and `StorageException` are transient on
  408/425/429/502/503/504/522/524. Every one of the ~15 existing guards in
  `supabase_service.dart` delegates to this helper, so they all start falling
  back to cache instead of rethrowing.
- **500 is deliberately excluded** so a malformed filter or broken function still
  surfaces as a bug. A cancelled statement (which PostgREST reports as 500) is
  matched by text instead. The first attempt matched `'gateway timeout'` anywhere
  in the error text, which the new test caught: it also excused a 400 whose
  details merely mentioned it.
- **`wallet_screen._loadOrders()` was `try`/`finally` with no `catch`** — the
  concrete path by which a 504 escaped as an unhandled async error. Now catches,
  keeps the existing list, and its `setState` is `mounted`-guarded (it could
  previously fire after the tab was disposed).
- **`AuthService.refreshUser()` was unguarded** and is called un-awaited from the
  `onAuthStateChange` listener, so a throw there was unhandled by construction.
  It now keeps the last-known profile.
- **Which query timed out is now recorded.** A `PostgrestException` carries no
  table or URL and its stack is entirely postgrest internals, so the report named
  nothing. `DiagnosticsService.noteDbCall()` tracks the operation in two plain
  Dart fields — no platform channel, safe on the 4-second poll — and the error
  handlers attach it, via `recordError(reason:)` where that is set synchronously
  and cannot lose a race with the report. Instrumented: `orders.select`,
  `profiles.select`, `watchlist.select`, `holdings+fo_positions.select`,
  `app_config.select`, `price_alerts.select`, `quotes_cache.select`.

Still open: *why* Supabase timed out. The app polls every 4s (four parallel
queries), 12s and 10s, which is the load that provokes gateway timeouts. Worth
revisiting once the breadcrumb names the slow query.

### Not in the store copy

- No dependencies added. Version bumped 1.1.2+34 → 1.1.3+35 → 1.1.4+36 → 1.1.5+37.
- `flutter analyze` clean; 389 tests pass, up from 318 (71 new: 8 rating-prompt
  timing, 11 IST day-range, 17 update-gate, 9 transient-error classification,
  13 notification routing, 13 wallet-ledger display).
- `place-order` is already deployed (version 5), so no edge-function step is
  needed for this release.
- **After the rollout is live**, run `python scripts/set_update_prompt.py` (it
  reads `1.1.4` from pubspec) so 1.1.2 users are actually told this build exists.
  `latest_version` is currently `1.1.2`, so without this step the window is empty
  for everyone on 1.1.2 and nobody hears about this release — the exact bug this
  release fixes.

---

## 1.1.2 (versionCode 34)

**Upload this one.** Supersedes 1.1.1+33 and 1.1.0+32, neither uploaded. Because
neither went out, a user updating from the store is coming from 1.0.x and sees
everything below for the first time — so the copy covers the whole jump, not just
this build's policy rewrite.

### Play Store "What's new" (paste this)

```
Trading Titans is now completely free.

• No paid plans or top-ups. Everything is unlocked
• Challenges, XP and Titan levels earn you demo cash
• US stocks are live: Apple, Microsoft, Nvidia and more
• Pick rupees or dollars and the whole app follows
• Live prices now update properly in every market
• Refreshed Terms & Conditions and Privacy Policy
```

(319 characters, limit 500)

### Terms & Privacy rewritten for a free app

The Profile screen carried a four-line summary of each policy. It now shows full
documents, written for the app as it actually behaves rather than copied from the
website.

- **The website text was wrong for this app.** `TermsPage.tsx` and
  `PrivacyPage.tsx` still describe Razorpay purchases, non-refundable credits and
  collecting payment reference IDs. `app_flags.monetization_enabled` is `false`
  and there is no billing, so those clauses describe something no user can do.
  The app text drops them entirely.
- **Terms** (8 sections) adds "The App is Free": no subscriptions, plans,
  top-ups or in-app purchases; no card, bank or UPI details collected; and an
  anti-fraud line stating that anyone asking a user to pay for Trading Titans or
  for demo cash is not us. It also commits to updating the Terms *before*
  charging anything, so switching `monetization_enabled` back on stays possible
  without having misled anyone. Refunds are answered by explaining there is
  nothing to refund, rather than the old "strictly non-refundable", which implied
  purchases exist. New acceptable-use section covers bug exploitation, quote
  tampering and scraping.
- **Privacy** (9 sections) removes all payment collection and adds a "What We Do
  Not Collect" section. It also discloses what the app genuinely uses and neither
  the old app text nor the website mentioned: Firebase crash reporting,
  analytics, push notifications and remote config, the FCM token, Google
  sign-in, stored preferences, price alerts and challenge progress. Play requires
  those disclosures, so this closes a real gap. Retention/deletion rights and a
  children's section added.
- Both sheets were byte-identical scaffolding differing only by title and body,
  so they collapsed into one `showLegalSheet()` renderer — about 3,800 characters
  of duplicated widget code deleted. Content lives in `core/legal.dart` as data;
  the sheet opens at 0.85 height because a long policy opened half-collapsed
  buries the first section.

`app/test/legal_free_app_test.dart` pins the free-app invariants: no
payment-gateway or purchase language, the free claim and anti-fraud line present,
demo cash described as worthless and non-withdrawable, sections consecutively
numbered, and the real third parties named. If monetisation is ever switched back
on, these tests fail deliberately — flip the expectations rather than deleting
them.

### Known follow-up, not done here

- **The website still contradicts this.** `TermsPage.tsx`, `PrivacyPage.tsx` and
  `RefundPage.tsx` remain paid-era. The website is the publicly binding version
  and Play cross-checks the privacy policy URL against declared data collection,
  so this is worth fixing before the listing goes live.
- Policy text is compiled in, so amending it needs a release. Upgrade path is two
  `app_config` rows (that table is already re-read on every resume) or a WebView
  onto the live pages.

---

## 1.1.1 (versionCode 33)

**Upload this instead of 1.1.0+32.** Same feature set, plus the trade-page price
fix below. The 1.1.0 store copy still applies; add one line about live prices.

### Play Store "What's new" (paste this)

```
Trading Titans is now free, and bigger.

• No more paid plans or top-ups. Everything is free
• Challenges, XP and Titan levels earn you extra demo cash
• US stocks are live: Apple, Microsoft, Nvidia and more
• Choose rupees or dollars and the whole app follows
• Prices on the Trade page now update live, in every market
• Quick setup on first launch, changeable any time
```

(365 characters, limit 500)

### What was actually wrong

Measured with `scripts/diagnose_price_movement.py` before changing anything.

- **The server cache was swallowing the poll.** `refresh-quotes` writes
  `quotes_cache` every ~20s (verified: consecutive `updated_at` at 06:23:00,
  06:23:20, 06:23:39, 06:24:01), but the client accepted any row up to **45s**
  old — more than twice the write cadence, so a row was effectively *always*
  accepted and the app never went live. Prices only stepped when the job happened
  to write, which reads as a frozen list even though the 4s poll was firing.
  Window is now 10s, so a row the job has not just refreshed falls through to a
  live fetch.
- **The popular lists were not in the refresh universe.** `buildUniverse()`
  collected symbols from watchlist, holdings, unsettled F&O, active alerts and
  pending orders, plus NIFTY/BANKNIFTY/SENSEX. The Trade screen's popular
  symbols were not included, so they landed in the cache only if some user
  happened to hold them — one list mixed cache-served rows with live-fetched
  ones, moving at different rates. All 25 are now in the universe; verified
  every one is present and fresh with `scripts/verify_quote_freshness.py`.
- **US stocks were gated on the Indian session.** `refreshOnce` skipped every
  non-crypto symbol when NSE was shut, which got US equities exactly backwards:
  refreshed while NSE was open (US market closed, so a stale close kept being
  restamped as fresh) and skipped the moment the US market opened. Now gated per
  market via the already-tested `isUsMarketOpen()` from `_shared/us_market.ts`.
  Verified live: `usOpen: false` correctly skips US symbols outside US hours,
  and a forced pass refreshes all 38 universe entries.
- **Per-row polling replaced with one batched call.** Each row owned its own
  timer and fetched independently, so nine popular rows on a 4s poll cost one
  `quotes_cache` query *plus* a live fetch **per row per tick** — roughly 4.5
  requests a second from a single phone, which is the most likely reason the
  list wedged until restart. The screen now makes one `MarketService.quotes()`
  call per tick for everything visible. The per-row `StatefulWidget` and its
  timer are deleted.
- **A wedged feed is now visible.** Failures were swallowed, so a stuck row
  looked identical to a price that simply was not moving. After two consecutive
  failed polls the rows dim and show a cloud-off icon, and the error is logged.
- Removed a wasted round trip: the batch path's live fallback now passes
  `forceRefresh`, since the batch read already proved there is no fresh cache
  row for that symbol.

`app/test/popular_symbols_sync_test.dart` pins the Dart popular lists against the
TypeScript universe and the US session gate. Verified it fails on drift by
mutating the TS list and watching it name the missing symbol.

**Cost note:** this is the deliberate "consistent and fast, highest cost" option.
Rows the job has just written still come from cache; anything else is a live
fetch per tick. If edge function volume becomes a problem, the upgrade path is a
realtime subscription on `quotes_cache`, not a longer acceptance window — a long
window is what caused this.

---

## 1.1.0 (versionCode 32) — first public release of all of the above

**This is the build to upload.** The version *name* was renumbered from 1.5.3 to
1.1.0 on request: production is still on 1.0.x, and every 1.2.0–1.5.3 build was
local-only, so 1.1.0 is the honest next step for a user coming from the store. The
version *code* keeps climbing (32) because Play compares the code, not the name,
and rejects any upload whose code is not strictly greater than the last one.

### Play Store "What's new" (paste this)

```
Trading Titans is now free, and bigger.

• No more paid plans or top-ups. Everything is free
• Challenges, XP and Titan levels earn you extra demo cash
• US stocks are live: Apple, Microsoft, Nvidia and more
• Choose rupees or dollars and the whole app follows
• Quick setup on first launch, changeable any time
• Faster live prices and a long list of pricing fixes
```

(337 characters, limit 500)

### Detailed changelog (for the listing description or a release post)

**Now completely free**
- Paid plans, wallet top-ups and the Subscribe screen are gone. Nothing in the
  app costs money. Existing plan badges no longer appear.

**Challenges, XP and Titan levels**
- 16 challenges covering trading milestones, profit targets, daily login streaks
  and learning. Completing one credits demo cash straight to your wallet.
- XP accumulates into Titan levels so progress is visible.
- A glossary quiz pays out once when you pass it.
- Weekly podium rewards for the top traders of each week.

**US stocks**
- Apple, Microsoft, Nvidia and the rest of the US market, tradable end to end.
- US market hours are handled automatically, including daylight saving.
- The order screen shows the rupee amount that will actually leave your wallet
  before you confirm.
- No brokerage or Indian taxes applied to US trades.

**One currency for the whole app**
- Pick rupees or dollars once; every price, balance, holding and P&L figure
  follows that choice, including Indian stocks and crypto.
- Change it any time from your profile.

**Quick setup on first launch**
- Three steps: where you trade from, your currency, and which markets you follow.
- Your location pre-fills the other two, so it is mostly confirmation.
- Preferred markets decide which trade tab opens first. No market is ever hidden.

**Prices and charts**
- Live prices refresh continuously on the trade list and the stock sheet instead
  of freezing at whatever they were when the screen opened.
- Tapping a stock or coin now shows it in your chosen currency.
- Crypto charts follow your currency too, so the chart and the price above it
  agree.
- Polygon now tracks POL, its current token, at the correct price.
- Price alerts, limit orders and "amount to invest" read the number you typed in
  the currency you are viewing.

### Not in the store copy

- Supersedes 1.5.3+31, 1.5.2+30, 1.5.1+29, 1.5.0+28, 1.4.1+27, 1.4.0+26,
  1.3.0+25 and 1.2.0+24 — all built locally, none uploaded. Everything listed in
  their entries below ships to users for the first time in this build.
- **Existing users will see onboarding once.** `onboarding_completed_at` is NULL
  on every account, which is correct: nobody has chosen a currency yet.
- `app_flags.us_stocks_enabled` is already `true` and
  `monetization_enabled` is `false`, verified with
  `scripts/show_release_gate.py`. Old clients cannot read `app_flags` at all, so
  the switches only take effect for people on this build.
- Version gate is still non-gating (`min_supported_version` and `latest_version`
  both `1.0.0`). Raise `latest_version` to `1.1.0` *after* the rollout reaches
  users, so the soft-update prompt points at a build Play is actually serving.
  Leave `min_supported_version` alone until adoption is high: raising it locks
  every 1.0.x user out immediately.
### Fixes carried in from the unreleased 1.5.x builds

- **The crypto chart ignored the display currency.** 1.5.2 pinned BTC, ETH and
  SOL to `COINBASE:*INR` to close a 3-4% gap against our rupee quotes, which was
  right for a rupee header and wrong for a dollar one: the header read `$1962.38`
  while the chart drew 190,168 rupees. `_resolveFor` now takes the preference, so
  a dollar view gets `BINANCE:ETHUSDT` and a rupee view keeps the Coinbase INR
  pair. Equities are unaffected — TradingView has no dollar-quoted NSE chart, so
  there is no second venue to switch to.
- `didUpdateWidget` now compares the URL it would load against the one on screen
  instead of comparing the widget's own fields. A currency change moves the chart
  between venues without the `symbol` prop changing, so field comparison missed
  it; the detail screen's 4s price poll then triggers the reload on its own.
- **Live prices were frozen.** `_LivePriceWidget` fetched once in `initState`
  with no timer, so the trade list and the action sheet showed the price from
  whenever the screen opened. Both now poll `AppConstants.dashboardPricePoll`
  (4s) silently, keeping the last good price if a fetch fails rather than
  flickering a spinner.
- **The action sheet ignored the currency preference.** It printed bare numbers
  with no currency symbol at all, which is why a `₹` search never found it. Nine
  figures now go through `Money`.
- **Change value was in the wrong currency.** `stock_detail_screen` and
  `option_detail_screen` printed a raw rupee change next to a dollar price, so
  ETH read `$1957.68 +68.80 (0.04%)` — the percentage was right, the number was
  95x too big.
- **Crypto charts disagreed with the header by 3-4%.** Our quotes come from
  CoinDCX in rupees; a USDT chart prices off a different implied rate (98.66 vs
  spot 95.42). Measured with `scripts/diagnose_crypto_premium.py`: the gap was
  identical across coins, so it was venue-wide rather than a data error. BTC, ETH
  and SOL now chart as `COINBASE:*INR`, the only INR pairs TradingView carries
  (confirmed with `scripts/probe_tradingview_symbols.py`); they track our price
  to within 0.8%. Every other coin keeps its USDT chart and the chart now shows
  the symbol it drew, so the residual gap is explainable.
- **Polygon was quoting the dead token.** CoinDCX delisted `MATICINR` after the
  MATIC → POL rebrand, so the quote fell through to Binance's stale `MATICUSDT`
  and served ₹36.20 against POL's real ₹7.45 — about 5x. `market-quote` now
  aliases MATIC → POL during symbol normalisation, alongside the existing
  ZOMATO → ETERNAL rule, so all three providers agree. No holdings, orders,
  alerts, watchlist rows or cached quotes referenced MATIC, so no data migration
  was needed. `scripts/diagnose_matic.py` re-checks the live path.
- **Typed input read as the wrong currency.** Limit-price prefill was the worst:
  viewing dollars, the field showed `1310` for a ₹1310 stock, so a confirm would
  have placed a $1310 limit. Also fixed: alert target saved raw, alert direction
  comparing dollars against a rupee price, and modify-order prefills. All now use
  `Money.bare` to write and `Money.fromDisplay` to read.

### Known, deliberately not changed

- `quotes_cache` is stale (`refresh-quotes` is deployed but has no cron
  schedule). Harmless today: the app discards anything older than 45s, so the
  cache is simply doing nothing. `scripts/diagnose_stale_quotes.py` reports it.
  Scheduling it is a separate decision.

---

## 1.5.0 (versionCode 28)

```
Set the app up your way in three quick taps.

• Tell us where you trade from and we pick sensible defaults for you
• Choose rupees or dollars, and every price follows your choice
• Pick your markets and we open your favourite first
• Change any of it later from your profile
• US stocks, Challenges and XP all included
```

(283 characters, limit 500)

### Not in the store copy

- Supersedes 1.4.1+27, 1.4.0+26, 1.3.0+25 and 1.2.0+24; none were uploaded.
- Onboarding is now three steps, location first. Location pre-selects the
  currency and pre-ticks the markets, so the remaining steps are confirmations
  rather than cold questions. A Back link preserves anything already chosen.
- `profiles.location` is `india` | `outside_india`, nullable, CHECK-constrained.
  NULL means unanswered — existing accounts are not silently defaulted to India.
- Location gates nothing. Every market stays tradable either way.
- Both preference RPCs were dropped and recreated with a `p_location` parameter
  rather than overloaded: PostgREST resolves by argument name, so two candidates
  would make every call ambiguous. Verified live that no ambiguity error occurs.
- Fixed in 1.4.1 and carried here: a UTF-8/Latin-1 corruption in two screens that
  broke the rupee glyph and silently skipped ~20 currency conversions, plus
  typed-input conversion (`Money.fromDisplay`) so a limit price or amount entered
  in dollars is not sent to the order engine as rupees.
- `scripts/find_mojibake.py` detects that encoding class of bug; worth running
  after any bulk edit.

---

## 1.4.0 (versionCode 26)

```
Choose your currency and see the whole app your way.

• Pick rupees or dollars on first launch, change it any time from your profile
• Every price, balance and profit figure follows your choice
• Tell us which markets you trade and we open your favourite first
• US stocks are live: Apple, Microsoft, Nvidia and more
• Challenges, XP and Titan levels to earn extra demo cash
```

(324 characters, limit 500)

### Not in the store copy

- Supersedes 1.3.0+25 and 1.2.0+24, neither of which was uploaded.
- **Existing users will see onboarding once.** `onboarding_completed_at` is NULL
  for every current account, so the two questions appear on first launch of this
  build. That is intended: nobody has chosen a currency yet.
- Display currency is presentation only. The wallet ledger, order prices,
  holdings and P&L stay INR in the database and every engine calculation is
  unchanged; conversion happens at render time against a live rate.
- Formatting inverted: call sites now declare the *source* currency
  (`Money.wallet` for wallet figures, `Money.instrument(market:)` for prices) and
  `Money` converts into the user's choice. That is how one setting repaints ~95
  call sites across 12 screens.
- Deliberately never converted: Play Store product prices in subscribe_screen
  (real money), stored notification bodies (would freeze a stale rate), glossary
  copy, and the "this is the rupee amount that will move" line on order entry.
- Preferred markets reorder the trade tabs; they never hide one, because hiding a
  market would strand an open position in it.
- Backend: migration `20260807000000_user_preferences.sql`
  (`display_currency` with a CHECK constraint, `preferred_markets`,
  `onboarding_completed_at`, plus `save_user_preferences` /
  `get_user_preferences` RPCs) and a `market=fx` branch on market-quote serving
  USD/INR.

---

## 1.3.0 (versionCode 25)

```
US stocks are coming to Trading Titans, priced in dollars.

• Trade Apple, Microsoft, Nvidia and more, shown in USD
• US market hours handled automatically, including daylight saving
• Order screen shows the rupee amount before you confirm
• No brokerage or Indian taxes on US trades
• Plus everything from 1.2.0: Challenges, XP and Titan levels
```

(300 characters, limit 500)

### Not in the store copy

- Superseded 1.2.0+24, which was built but never uploaded.
- US equities are gated by `app_flags.us_stocks_enabled` (seeded `false`). The tab
  shows "Coming soon" until you flip it.
- Currency model: `orders.price` and `holdings.avg_price` stay INR because that
  is what the wallet moved; `native_price` / `native_avg_price` hold the USD
  figures the user saw, and `fx_rate` records the rate used at each fill.
- A US position displays entirely in dollars (cost, value, P&L) with no FX
  involved, since both its cost basis and live price are USD. Only the wallet and
  portfolio-wide totals stay in rupees.
- Backend: migration `20260806000000_us_stocks.sql`, `_shared/us_market.ts`, and
  redeploys of market-quote, market-search, market-status, place-order and
  execute-pending-orders. New cron `execute-pending-us-orders`
  (*/5 13-21 UTC Mon-Fri) covers the overnight US session under both EDT and EST.
- US derivatives are explicitly rejected: no contract master, no lot sizes, and
  the option model assumes an Indian risk-free rate.

---

## 1.2.0 (versionCode 24)

```
Trading Titans is now completely free. No top-ups, no paid plans.

• New Challenges screen: earn demo cash for trading milestones, daily streaks and learning
• Titan levels and XP track how far you have come
• Pass the glossary quiz for a reward
• Cleaner market switcher on the Trade screen
• US Stocks tab added, opening soon
```

(327 characters, limit 500)

### Not in the store copy

- 16 challenges, 25 catalogue rows. Rewards are granted server-side and paid
  through the existing `rewards` table, so the confetti dialog and wallet credit
  are unchanged.
- Paid surfaces are gated by `app_flags.monetization_enabled` (seeded `false`).
  Flip that row to bring the top-up card, Subscribe screen and plan badges back
  for everyone without shipping a build.
- US Stocks is gated by `app_flags.us_stocks_enabled` (seeded `false`). The tab
  shows a "Coming soon" state until quotes are wired up.
- Login streaks start from zero for every account, because `touch_login_streak()`
  is only called by this build onwards. First streak rewards land 3 days after
  release.
- Backend: migration `20260805000000_gamification_and_app_flags.sql`, plus two
  pg_cron jobs (`evaluate-challenges-daily` Mon–Fri 10:45 UTC,
  `award-weekly-podium` Saturdays 19:00 UTC).
