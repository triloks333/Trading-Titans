# TRADING TITANS — COMPREHENSIVE SYSTEM MEMORY & CODEBASE ATLAS
> **Target Audience**: AI context windows (ChatGPT, Claude, Gemini), senior developers, and system architects.  
> **Last Updated**: September 2026  
> **Active Branch**: `upto14sep`  
> **Production App Version**: `1.2.7` (`versionCode: 51`)  
> **Supabase Project Ref**: `bftvimnhpoiuoyryyiff`

---

## 1. PRODUCT & EXECUTIVE SUMMARY

- **Product Name**: Trading Titans
- **Entity**: KashivWealth Management (KWM) / Xenith
- **Tagline**: *"Trade Bold. Lose Nothing."* / *"Real Market. Virtual Risk."*
- **Core Value Proposition**: A realistic virtual trading flight simulator for Indian stock, derivatives (F&O), US equities, and crypto markets. Users trade with risk-free virtual money in an environment that faithfully reproduces real-world exchange mechanics, order books, lot sizes, and option Greeks.
- **Visual & Brand Identity**:
  - **Color Palette**: Royal financial blue (`#1A73E8`), Deep navy surface for dark mode, Bull green (`#0F9D58`), Bear red (`#D93025`).
  - **Typography**: Inter (400, 500, 600, 700, 900) across all platforms.
  - **Base Currency**: Indian Rupee (₹, INR). Automatic FX conversion for US stocks.

---

## 2. REPOSITORY & WORKSPACE TOPOLOGY

```
Trading-Titans/
├── app/                  # Core Mobile Client (Flutter / Dart) - Android, iOS, Web
│   ├── lib/
│   │   ├── core/         # Market hours, currency, country/state maps, app constants
│   │   ├── models/       # PODO models (Order, Position, Instrument, Option, Quote)
│   │   ├── screens/      # 31 Main screens (Trading, Portfolio, Chat, Admin, etc.)
│   │   ├── services/     # 17 Domain services (Supabase, Auth, Market, Chat, etc.)
│   │   ├── theme/        # Royal blue light & dark theme definitions
│   │   └── widgets/      # Shared UI primitives (TrendArrow, Shimmer, SwipeButton, etc.)
│   └── assets/
│       └── chart.html    # Compiled standalone canvas charting engine bundle
├── chart/                # Custom TypeScript Canvas Charting Subsystem
│   ├── src/
│   │   ├── core/         # Tick aggregation, 15+ indicators, drawings, templates
│   │   ├── data/         # Storage preferences (timeframe, chart style)
│   │   └── webview/      # Bridge between Flutter InAppWebView and Canvas engine
├── web/                  # Desktop Trading Portal (React + Vite + TypeScript + Tailwind)
│   └── src/pages/        # Dashboard, Trade, Portfolio, Plans, Leaderboard, Autopsy
├── website/              # Public Marketing Site + Serverless Edge Blog
│   ├── api/              # Vercel serverless functions (SSR blog / SEO / payments)
│   └── src/              # React landing pages
├── supabase/             # Backend Infrastructure
│   ├── functions/        # 36 Deno Edge Functions (Orders, Quotes, Bhavcopy, FCM, etc.)
│   └── migrations/       # Complete chronological SQL migration history + RLS
├── kashiv_vault/         # Sister Flutter Android App: Corporate document & credential vault
├── kashivwealth-web/     # Web front-end for KashivWealth Vault
├── scripts/              # Python automation suite (Broker autologins, PDF gen, release gates)
├── docs/                 # Product specs, financial audit reports, release notes
└── .kiro/                # Standing architectural rules, steering policies, owner exemptions
```

---

## 3. CORE FEATURES & USER EXPERIENCES

1. **Authentication & Profile**:
   - Supabase Auth (Email/Password, Guest mode with safe conversion path).
   - Country & state picker (249 ISO codes + India 28 states/8 UTs).
   - Explicit dialog-based account moderation (banned users see clear rationale).
2. **Real-Time Trading Simulation**:
   - **Indian Equities**: Nifty 50, Sensex, Midcaps, and Bhavcopy-synced stocks.
   - **F&O (Futures & Options)**: Full Option Chain with real Open Interest (OI), strike selection, Greeks calculation, and synthetic Futures pricing.
   - **Crypto**: Real-time BTC, ETH, SOL and top coins via CoinDCX WebSocket.
   - **US Equities**: Top US stocks with real-time INR/USD FX conversion.
3. **Advanced Order Execution**:
   - Market, Limit, and Stop-Loss orders with intra-day and delivery margin checks.
   - F&O orders run through atomic database RPC (`place_fo_order`).
   - Server-side settlement engine runs every Thursday for expiring contracts.
4. **Custom Canvas Charting**:
   - High-performance 60fps HTML5 Canvas charting loaded via WebView.
   - Indicators: Supertrend, Bollinger Bands, Ichimoku Cloud, Pivot Points, VWAP, EMA, SMA, WMA, RSI, MACD, Stochastic, ATR, Parabolic SAR, ADX.
   - Drawing Tools: Fibonacci Retracement, Rectangle, Arc, Trendlines, Horizontal levels.
   - Tap-to-inspect OHLC candle chips with persistent timeframe/style memory.
5. **Community & Gamification**:
   - **Titans Room**: Live public community chat with anti-spam moderation, image attachments, WhatsApp-style grouping, and official `ADMIN` badges.
   - **Weekly League & Competitions**: Real-time P&L leaderboard excluding owner/admin test accounts from podium prizes.
   - **Wishlist & Voting**: Community-driven feature request board with upvoting and moderation.
6. **Trader Skill Enhancement**:
   - **What-If Simulator**: Backtests hypothetical investments across historical timelines.
   - **Trade Autopsy**: Rule-based educational post-mortem analyzing winning and losing streaks.
   - **Glossary & Quizzes**: Interactive financial literacy flashcards and quizzes.
7. **Administration & Growth**:
   - In-app **Admin Blog Authoring** publishing to SSR `/blog/<slug>` for SEO.
   - Dynamic **Admin Analytics** broken down by platform, region, and activity dimensions.
   - In-app push notification trigger suite and customer support ticket tracking.

---

## 4. FINANCIAL ENGINE, FORMULAS & VALUATION

### A. F&O Margin Rules
- **Futures & Short Options**: Require `0.15` (15%) margin:
  $$\text{Required Margin} = \text{Price} \times \text{Lot Size} \times 0.15$$
- **Long Options**: Require 100% premium upfront:
  $$\text{Required Margin} = \text{Premium} \times \text{Lot Size}$$

### B. Valuation Time & Zero-Drift at Market Close (v1.2.7 Fix)
- **Problem Solved**: Synthetic futures and Black-Scholes options pricing previously evaluated time-to-expiry ($T$) against continuous wall-clock `DateTime.now()`. This caused P&L to artificially drift overnight and over weekends when markets were closed.
- **The Fix**: All pricing calls pass through `MarketHours.valuationTime()`. When the market is open, live clock is used; when closed, valuation freezes precisely at the session close timestamp (15:30 IST) or the prior active session.
- Centralized helper `MarketHours.daysToExpiry(expiry)` is shared across all 7 pricing locations.

### C. Server-Side Market Holidays
- Managed via the `market_holidays` table.
- A database trigger on `orders` rejects order execution claims on holidays without requiring app store updates or client code changes.
- Indian quotes are frozen server-side to prevent artificial price moves on holidays.

---

## 5. DATABASE ARCHITECTURE (SUPABASE POSTGRES)

### Primary Tables & Schemas
- `profiles`: User accounts, virtual demo balance, `is_admin`, country/state, platform tag.
- `orders`: All trade records (`EQUITY`, `FO`, `CRYPTO`, `US`), status (`PENDING`, `EXECUTED`, `CANCELLED`, `REJECTED`).
- `holdings`: Current portfolio holdings for cash-segment stocks and crypto.
- `fo_positions`: Open derivatives contracts (Futures/Options), strike, option type, lot size, expiry, entry price.
- `wallet_transactions`: Double-entry audit ledger for credits, debits, margins, payouts, and referral bonuses.
- `instruments` & `fo_instruments`: Master lists of NSE equities, strike prices, lot sizes, contract expiries.
- `quotes_cache`: In-memory/table quote cache populated by Upstox/Fyers/CoinDCX.
- `market_holidays`: Designated exchange holiday calendar.
- `chat_messages` & `chat_reports`: Public Titans Room messaging, spam flags, and media URLs.
- `blog_posts`: Content engine for articles, meta descriptions, and OpenGraph SEO cards.
- `notifications`: Push and in-app notifications with automated 7-day read_at purge cron.
- `app_config`: Remote version governance (`latest_version`, `min_supported_version`, update notes).
- `kv_*`: KashivWealth Vault tables (isolated via `kv_` prefix and private storage buckets).

### Security & RLS Patterns
- Public client write access is heavily restricted. Tables created after 2026-09-03 are revoked by default (`alter default privileges in schema public revoke insert, update, delete, truncate on tables from anon, authenticated`).
- Financial paths run through `SECURITY DEFINER` RPCs (`place_fo_order`, `record_platform`, etc.).
- Critical database triggers have pinned `search_path = public, pg_temp`.

---

## 6. BROKER INTEGRATIONS & DATA PIPELINE

1. **Upstox API v2**: Primary live feed for NSE equity quotes and indices. Managed via daily OAuth token refreshed by `scripts/upstox_autologin.py`.
2. **Fyers API**: Secondary market data source and live websocket quote engine (`scripts/fyers_autologin.py`).
3. **CoinDCX**: Real-time WebSocket connection streaming crypto live prices directly to client/edge cache.
4. **NSE Bhavcopy Sync**: Deno Edge Function (`sync-nse-bhavcopy`) regularly ingests end-of-day official NSE closing prices.
5. **Firebase Cloud Messaging (FCM)**: Push notifications dispatched via `push-notification` and `kv-push` edge functions.

---

## 7. STANDING STEERING POLICIES & OPERATIONAL RULES

### A. Owner Accounts Policy (`.kiro/steering/owner-accounts.md`)
The following accounts represent founders and system owners:
- **Pawan**: `pawan.2u2@gmail.com`
- **Trilok Singh**: `triloks34@gmail.com` (Admin)
- **Manav Agarwal**: `mr.engineer5000@gmail.com` (Admin)
- **Manav Agarwal**: `manavagg2003@gmail.com` (Secondary owner)

**Mandatory Rules**:
1. **Never reset, reduce, or modify** wallet balances, positions, or P&L of owner accounts. Large balances are intentional test/operating capital.
2. Owner accounts are permanently excluded from leaderboard weekly podiums and anomaly alerts.

### B. Release & Deployment Protocol (`.kiro/steering/release-process.md`)
1. **Always bump version**: In `app/pubspec.yaml`, increment both version name (e.g. `1.2.7`) and versionCode (e.g. `51`).
2. **Version Codes are Burned**: Once a build is generated and reported, assume it is live. Never reuse a versionCode.
3. **Release Notes Order**: Always append release notes to `docs/release-notes.md` under the top `### Play Store` block **before** building, because `scripts/set_update_prompt.py` reads that specific section.
4. **Arming In-App Update**: After Google Play rolls out the bundle, execute:
   ```powershell
   python scripts/set_update_prompt.py
   ```

### C. "Ponytail" Developer Principle (`.kiro/steering/ponytail.md`)
- **Lazy senior developer mode**: Efficiency over boilerplate. Best code is unwritten code.
- YAGNI first: reuse existing utilities, rely on stdlib, write root-cause fixes across all callers rather than superficial patches.
- Every non-trivial fix must leave behind a verification check or unit test.

---

## 8. ACTIVE TECHNICAL DEBT & ROADMAP

1. **Service Layer Modularization**: `app/lib/services/supabase_service.dart` is ~3,000+ lines. Target: split into domain services (`orders_service`, `wallet_service`, `market_service`).
2. **Consolidate Equity Orders**: Migrate equity buy/sell client paths to an atomic server RPC matching `place_fo_order`.
3. **Payment Webhook Hardening**: Move wallet credits exclusively behind verified server-side Razorpay webhooks.
