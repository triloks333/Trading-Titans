# Why Trading Titans Can't Get Real-Time Market Data (and Why FrontPage Can)

**Prepared for:** Trading Titans founders
**Topic:** Root-cause analysis of real-time market-data access for an Indian stock-market app
**Last updated:** July 2, 2026

---

## TL;DR (Executive Summary)

Our repeated failures to enable real-time stock / F&O / options-chain data were **not** a
technical skills gap. We hit a **regulatory + licensing wall that is specific to our app's
category**.

- **FrontPage** is a **community / discussion app** that *displays* market data for
  information. Displaying data for discussion is a **permitted, licensable** use, so they
  buy a commercial redistribution feed from an NSE-authorized vendor and fan it out to users.
- **Trading Titans** is a **virtual / paper-trading app**. NSE's April-2023 circular
  **prohibits the use of exchange market data in gaming and virtual-trading applications**,
  and SEBI has publicly cautioned against virtual / paper-trading / fantasy platforms.
- **Same data, different legal bucket.** FrontPage didn't out-engineer us; they chose a
  product category that can legally license live data. We are in the one category NSE
  fenced off from live data.

---

## 1. The core reason

Two rules decide everything here:

1. **NSE circular (April 2023)** explicitly **prohibits the use of exchange market data in
   gaming and virtual-trading applications.**
   Source: Zerodha Z-Connect —
   <https://zerodha.com/z-connect/rainmatter/stock-trading-games-copy-trading-platforms-in-india>

2. **SEBI** has issued public cautions against **unauthorised virtual trading / paper
   trading / fantasy-game platforms.**
   Source: ET Now (2026) —
   <https://www.etnownews.com/markets/sebi-issues-fresh-warning-over-unauthorised-platforms-trading-unlisted-securities-article-154657903>

Trading Titans **is** a virtual/paper-trading app. FrontPage **is not** — it's a
community/discussion app that *displays* market data (heatmaps, option-chain views,
gainers/losers) for people to talk about. Displaying data for information and discussion is
a permitted, licensable use. Letting users place simulated trades against live prices is the
disallowed use. That single distinction is why they can and we can't.

---

## 2. How FrontPage actually gets the data

They pay for a **commercial redistribution license from an NSE-authorized data vendor**, then
fan that one feed out to all users. This is not exotic — the vendor exists and openly sells
exactly what we were missing:

- **TrueData** describes itself as an **"Authorised Data Vendor for NSE, BSE and MCX"**
  delivering real-time APIs including **live options chain and option greeks.**
  Source: <https://www.truedata.in/market-data-apis>
- **Global Datafeeds** is another authorized real-time tick vendor for NSE F&O / MCX /
  currency.
  Source: <https://www.marketcalls.in/demo>

So the real options-chain / futures data we couldn't get **does exist and is buyable** —
through an authorized vendor with a redistribution license, **not** through a personal broker
login.

### How the data flows in an app like FrontPage (typical architecture)

A small number of backend workers hold the upstream vendor WebSocket feed → normalize the
ticks → push into an in-memory bus (Redis pub/sub or Kafka) → the app's own realtime gateway
fans out only the symbols each client has on screen. One upstream tick reaches thousands of
users without re-querying the vendor. (This part is standard industry inference, not
FrontPage's published internals.)

---

## 3. Why our specific attempts failed

Everything we tried (Zerodha Kite, Upstox, Fyers) was a **personal, single-user broker API**,
and it fails for a multi-user app for structural reasons — not because of anything we did
wrong:

| Problem | What happened |
| --- | --- |
| **Redistribution is banned** | Personal broker APIs are licensed for *you* trading *your own* account. Piping that feed to thousands of app users breaches the exchange agreement — redistribution without a commercial license means immediate termination. |
| **Single session** | One login = one live WebSocket. It can't serve many users, and it collides with the user's own broker session. |
| **Daily token death** | Kite/Upstox access tokens expire every morning and need a fresh interactive login — which is why our autologin scripts were brittle and kept breaking. |
| **Symbol limits** | A single connection caps how many instruments you can subscribe to; the full F&O universe (all option strikes) blows past that. |
| **Category ban on top of all that** | Even if the mechanics worked, the NSE circular disallows feeding a virtual-trading app. |

That's why it "drastically failed": we were using a personal-use tool for a multi-user,
disallowed purpose. No amount of engineering fixes a licensing prohibition.

---

## 4. Realistic paths forward

Ordered from most compliant / practical to hardest:

1. **Keep the current simulation model (EOD bhavcopy + Black-Scholes).**
   Fully legitimate for a learning sim; needs no live feed. This is where we are today — the
   fix is cadence/quality, not a live feed.

2. **Use 15-minute delayed data.**
   NSE / LSEG offer delayed post-trade data with much looser redistribution terms. Label
   prices "15-min delayed." Good enough for education, far easier to license.
   Source: <https://www.lseg.com/en/data-analytics/financial-data/pricing-and-market-data/equities-market-data/national-stock-exchange-india>

3. **Change what the app *is*.**
   If we add a genuine **community / analytics** layer (like FrontPage) where live data is
   shown for information/discussion rather than to trade against, an authorized vendor feed
   (TrueData / Global Datafeeds) may become licensable. This is a positioning + compliance
   decision, not a coding one.

4. **Negotiate a specific license for virtual trading.**
   Some fantasy/learning platforms get explicit written permission from the exchange/vendor
   for a simulated-trading use case. It's the hardest path and needs a compliance advisor.

---

## 5. Important caution

Before pursuing real-time data for a virtual-trading app, get a **written read from the
vendor (TrueData)** and ideally a **compliance / legal advisor** on whether our specific use
is allowed. Paying for an authorized feed does **not** override the NSE gaming/virtual-trading
restriction if we're still classified as a game — we'd just be paying and still
non-compliant.

---

## 6. Bottom line

FrontPage didn't out-engineer us. They chose a product category (community / data display)
that can legally license live data, and they buy it from an authorized vendor. Our app is in
the one category NSE fenced off from live data. The most sensible move is to either:

- **Stay a clean simulation** (delayed / EOD data), or
- **Evolve toward a community / analytics product** if we genuinely want live feeds.

---

## Appendix: Confidence & sourcing notes

- **Verified facts (cited):** the NSE April-2023 circular, SEBI cautions, TrueData's status
  as an NSE/BSE/MCX authorized vendor offering live options chain + greeks, Global Datafeeds
  as an authorized real-time vendor, and NSE/LSEG delayed-data availability.
- **Informed inference (not published by FrontPage):** their exact tech stack, database
  choices, and fan-out architecture. FrontPage is a private company and has not published
  these internals; the architecture description reflects standard industry patterns for a
  data-display community app.

### Source list

1. NSE prohibits data for gaming / virtual-trading apps (Zerodha Z-Connect) —
   <https://zerodha.com/z-connect/rainmatter/stock-trading-games-copy-trading-platforms-in-india>
2. SEBI caution on virtual / paper-trading / fantasy platforms (ET Now) —
   <https://www.etnownews.com/markets/sebi-issues-fresh-warning-over-unauthorised-platforms-trading-unlisted-securities-article-154657903>
3. TrueData — Authorised Data Vendor (NSE/BSE/MCX), live options chain + greeks —
   <https://www.truedata.in/market-data-apis>
4. Global Datafeeds — authorized real-time NSE F&O / MCX / currency vendor —
   <https://www.marketcalls.in/demo>
5. LSEG / NSE — delayed post-trade market data —
   <https://www.lseg.com/en/data-analytics/financial-data/pricing-and-market-data/equities-market-data/national-stock-exchange-india>
6. FrontPage company profile (YC) — <https://www.ycombinator.com/companies/frontpage>

_Content in this document was rephrased and summarized from the sources above for licensing
compliance; external claims should be independently verified with the vendor and a compliance
advisor before acting._
