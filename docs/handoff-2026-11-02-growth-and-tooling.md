# Session handoff — 2026-11-02 (growth plan, analytics, GSC baseline, tooling)

Read this first in the next session. It is everything a previous Claude Code
session learned and did, so you can continue from the same point. Branch:
`automation`. Last commit: `670ee57`.

---

## 1. Goals (from the user and `CLAUDE.md`)

- **₹5,000/month MRR.** The target is in rupees, not dollars. The previous
  session first assumed $5k; `CLAUDE.md` corrected it. ₹5k is roughly 34 Pro subs
  (₹149) or 7 Titan subs (₹799), or a mix such as 15 Pro + 4 Titan. One-time top-ups
  (₹29 / ₹199 / ₹599 / ₹999) bring in cash but are **not** MRR.
- **100,000 Google Search impressions/month** on thetradingtitans.com
  (1,000–5,000 a day).
- Rank top 3 in India for "paper trading app india", "options trading simulator"
  and "brokerage calculator nse".

---

## 2. Key findings so far

### Revenue / checkout
- `Trading-Titans-53-Unpaid-Buyers-Report.pdf` (repo root): **53 people started a
  checkout and only 5 paid** (~9% completion). The abandoned carts add up to
  ₹27,439, of which ₹14,191/mo would have been subscription revenue. Most of the 53
  dropped off at the "external browser bridge" before Razorpay could capture a phone
  number (42 of 53 have no phone on record).
  Recovering a third of these alone roughly reaches the ₹5k MRR goal.
  **The biggest lever is fixing checkout completion, not getting more traffic.**
- Win-back reminders are built: `supabase/functions/winback-reminders/` plus the
  migration `20261031010000_winback_payment_reminders_cron.sql`. It runs every 6
  days and sends email + SMS + push with Razorpay payment links.
  Minor issue: the owner/test exclusion list (real names and emails) is hardcoded in
  `index.ts`. It should move to a table or a flag.
- **Google Play policy risk:** the Android app sells virtual cash and passes through
  `razorpay_flutter` (1.2.12 added native in-app UPI checkout). Play policy requires
  Play Billing for digital goods. `docs/monetisation-plan.md` §0.3 already flags
  this. The user still has to make that decision: Play Billing in the app, web-only
  Razorpay, or Play's alternative-billing route in India. Not yet discussed further.

### Search Console baseline (pulled 2026-11-02, read-only)
- The range 2026-08-03 → 2026-10-31 gives **952 impressions and 74 clicks**
  (~10–25 impressions a day, flat).
- **100% of queries are branded** ("trading titans", "trade titans"). There are zero
  non-brand impressions.
- A different business shares the name: "trading titans institute of stock market".
- Only `/` and `/privacy` earned impressions.
- URL Inspection on 2026-11-02:
  - `/`, `/blog`, `/about` and several blog posts: indexed today, after a sitemap
    resubmit.
  - `/paper-trading-app-india`, `/options-trading-simulator`, `/brokerage-calculator`,
    `/topup`: **"Discovered – currently not indexed", never crawled.**
- The sitemap has 116 URLs, 105 of them blog posts. Most posts are generic
  global-macro news (IMF, Fed/ECB, gold). They are unlikely to rank and are off-topic
  for paper trading. Treat roadmap item 4 in `CLAUDE.md` ("publish trending news")
  with care: thin or rewritten news risks Google's scaled-content-abuse policy.
- **The raw server HTML of `/` and `/blog` contains 0 links to the 3 landing pages.**
  The navbar only links to them after JavaScript runs. This is the likely reason they
  were never crawled.
- A request with a spoofed Googlebot user-agent takes ~10 s to respond, versus 0.13 s
  for a normal browser. This is probably Vercel delaying fake bots. Ask the user to
  check *Settings → Crawl stats* in Search Console to confirm the real Googlebot is
  fast.
- The baseline is also saved in memory: `gsc-baseline-2026-11`.

---

## 3. What was done (committed in `670ee57`)

The commit bundled the user's pre-existing 1.2.12 work (native Razorpay UPI
checkout, phone capture, win-back reminders, SEO landing pages, sitemap,
robots.txt) together with the analytics work below.

### Website analytics (new)
- `website/api/analytics.js`: one GA4 loader served at `/api/analytics`, used by
  the marketing SPA, the server-rendered pages and the `/app` web app. Changing the
  ID does not need a rebuild. Its behaviour:
  - It reads `GA_MEASUREMENT_ID` when each request is served. Until that is set it
    loads nothing, so no data is recorded yet.
  - It fires `play_store_click` and `open_web_app_click` events.
  - It adds `referrer=utm_source=website&utm_campaign=<page>&utm_content=<section>`
    to Play Store links, so Play Console can attribute installs.
- `website/api/_analytics-tags.js`: adds Vercel Insights + `/api/analytics` to the
  server-rendered pages, through `landing.js` (`COMMON_HEAD`), `blog.js` and `post.js`.
- `website/index.html` and `web/index.html` load `/api/analytics`.
- `web/src/lib/analytics.ts` + `web/src/lib/payments.ts`: GA4 ecommerce events
  `begin_checkout`, `purchase`, `checkout_dismissed`, `payment_failed`.
  Analytics can never throw into the checkout code.
- Verified: both builds pass, the 12 `post.check` checks pass, and a browser test
  with a fake ID showed gtag loading, events firing and the referrer tag added
  exactly once.
- **The user still has to:**
  1. Create a GA4 property and set `GA_MEASUREMENT_ID=G-…` in the Vercel **website**
     project.
  2. Redeploy both website and web.
  3. Mark `purchase` and `play_store_click` as key events.
  4. Link GA4 to Search Console.
  5. Consider a consent banner (India's DPDP Act).

### Not committed
- `CLAUDE.md`: written by Antigravity after the commit, untracked. It contains no
  secrets, so it is safe to commit; ask the user first.
- `test_orig.png`: a scratch screenshot. Leave it out of commits.
- This handoff file.

---

## 4. Tooling installed (user scope, all projects)

`~/.claude/settings.json` now carries `extraKnownMarketplaces`, `enabledPlugins`
and `CLAUDE_MEM_ONLINE_OPTIN=false`. The original is backed up in
`~/.claude/backups/`. `~/.claude.json` is backed up as `~/.claude.json.bak-*`.

| Item | Source | Notes |
|---|---|---|
| ponytail | `ponytail@ponytail` (DietrichGebert/ponytail) | Local ledger only; webhook empty |
| code-review | `code-review@claude-plugins-official` | |
| claude-mem | `claude-mem@thedotmack` | Cloud sync off; installs Bun and runs a local worker |
| obsidian | `obsidian@obsidian-skills` (kepano) | |
| superpowers | `superpowers@claude-plugins-official` | |
| headroom | `uv tool` headroom-ai 0.42.0 + user MCP `headroom` → `headroom.exe mcp serve` | **The MCP server timed out on connect (30 s)** in the session that loaded it. Fix: raise the MCP startup timeout (`MCP_TIMEOUT`) or check `headroom mcp serve` by hand. `headroom wrap claude` was deliberately **not** used: it would clash with the existing `ANTHROPIC_BASE_URL=localhost:8000` proxy. |
| playwright | `playwright@claude-plugins-official` | |
| firecrawl | `firecrawl@claude-plugins-official` | **Needs `FIRECRAWL_API_KEY`**, which the user must set themselves |
| chrome-devtools-mcp | `chrome-devtools-mcp@claude-plugins-official` | |
| find-skills | `~/.claude/skills/find-skills` (vercel-labs/skills) | |
| impeccable | `impeccable@impeccable` (pbakaus) | |
| task-observer | `~/.claude/skills/task-observer` (rebelytics) | Wants to run at the start of each session |
| claude-code-setup | `claude-code-setup@claude-plugins-official` | |
| OmniRoute skills (10) | `~/.claude/skills/{omni-auth,cli-serve,cli-setup,cli-health,cli-providers,cli-models,cli-routing,cli-cost-usage,omni-mcp,omni-inference}` | From cheaper-inference/OmniRoute (formerly diegosouzapw). The other 36 were skipped to save context, including their copy of `ponytail`, which would clash with the plugin. |

Running the nested `claude plugin …` CLI hangs inside the desktop-app session (exit
124), so plugins were installed by hand.

**Status, confirmed on disk:**
- The 6 official plugins are cached in `~/.claude/plugins/cache/claude-plugins-official/`.
- The 4 third-party marketplaces (ponytail, thedotmack, obsidian-skills, impeccable)
  were shallow-cloned into `~/.claude/plugins/marketplaces/`. Their plugins were
  copied into `cache/<marketplace>/<plugin>/<version>`: ponytail 5.3.3,
  claude-mem 15.8.3, obsidian 1.0.1, impeccable 4.8.0. They are registered in
  `known_marketplaces.json` and `installed_plugins.json`; both files have `.bak-*`
  backups.
- claude-mem's hooks call a `claude-mem` binary, so `npm i -g claude-mem@15.8.3` was
  also installed (it lives in `%APPDATA%\npm`). On first start it installs Bun and
  runs a local worker.
- Not yet seen loading in a fresh session. Run `/plugin` to confirm all 10 show as
  installed. If the hand-made registry entries are rejected, run
  `/plugin install <name>@<marketplace>` from an interactive terminal session.

### OmniRoute gateway — installed, not yet configured
- The system Node is v22.19.0; OmniRoute 3.8.52 needs ≥22.22.2. The system Node was
  **not** changed.
- A private Node **v24.22.2** (checksum-verified) is at
  `~/.local/share/omniroute/node`.
- The app is installed at `~/.local/share/omniroute/app`. Its postinstall script was
  reviewed: it only rebuilds the native `better-sqlite3` module.
- Wrappers: `~/.local/bin/omniroute.cmd` and `~/.local/bin/omniroute`, both pinned to
  the private Node. `~/.local/bin` is on PATH. `omniroute --version` prints `3.8.52`.
- **Next steps:**
  1. `omniroute setup`: first-run password; the user should type it themselves.
  2. `omniroute serve --headless`.
  3. `curl http://localhost:20128/v1/models` or `omniroute health`.
  Do not reroute Claude Code through it without asking: the user already points
  `ANTHROPIC_BASE_URL` at `localhost:8000`, which was **not answering** when checked.

---

## 5. Recommended next actions (in priority order)

1. **Server-rendered internal links** to `/paper-trading-app-india`,
   `/options-trading-simulator` and `/brokerage-calculator`, from the homepage HTML,
   `/blog`, every post (`post.js` CTA box) and the footer. Then ask the user to use
   *Request indexing* in Search Console, which needs their own login.
2. **Checkout completion:** remove the external-browser hop. Contact the 53
   abandoned buyers by hand with a one-time offer.
3. **Decide the Play Billing approach** (policy risk).
4. **Change the blog from news to search-intent content** ("how to practise options
   trading", "Nifty option chain explained", "lot size in F&O", brokerage
   comparisons), with every post linking to a landing page.
5. **Programmatic `/paper-trade/[symbol]` pages** (CLAUDE.md roadmap), server-rendered
   with JSON-LD and real simulator data.
6. **Connectors worth adding:** Vercel, Supabase, Razorpay, PostHog, Ahrefs or
   OpenSEO (all in the Claude connector directory). Search Console works today
   through the service-account key below.

---

## 6. Useful references

- **Search Console (read-only)** works with the service account key
  `.antigravity/trading-titans-8375f-64a2cd65a182.json` (git-ignored) and the scope
  `webmasters.readonly`, for `sc-domain:thetradingtitans.com`. The pull scripts
  were in the old session's temp scratchpad, which may be gone. They are simple:
  `searchconsole v1`, using `searchanalytics.query` (dims date/query/page/country/
  device), `sitemaps.list` and `urlInspection.index.inspect`. Run Python without
  `-I` (google libs live in user site-packages).
- `scratch/resubmit_and_inspect.py`, referenced in CLAUDE.md, **does not exist**.
- Pricing in the database (`plan_catalogue`):
  - Top-ups: `topup_mini` ₹29, `topup_boost` ₹199, `topup_plus` ₹599, `topup_max` ₹999.
  - Subscriptions: `pro_monthly` ₹149, `pro_annual` ₹1,199, `titan_monthly` ₹799,
    `titan_annual` ₹5,999.
- Monetisation docs: `docs/monetisation-plan.md`, `docs/monetisation-pricing.md`.
