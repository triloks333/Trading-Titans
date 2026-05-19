# Trading Titans - Product Requirements Document (v1.1)

## Vision
Premium paper-trading mobile app for Indian investors. Real markets (NSE/BSE + crypto), virtual cash. Free tier credits ₹1,00,000 instantly on signup; paid tiers (kept ready) add up to ₹10L.

## Brand & Visual Identity
- Name: Trading Titans
- Tagline: "Trade Bold. Lose Nothing." / "Real Market. Virtual Risk."
- Theme: **Light Blue** (Zerodha/Groww-inspired) — primary #1A73E8, surface #F4F7FB
- Font: **Inter** (400/500/600/700/900) — single family across display, body, mono
- Bull green #0F9D58 / Bear red #D93025

## Stack
- Frontend: Expo Router + React Native + react-native-svg + Inter fonts
- Backend: FastAPI + Motor (MongoDB) + pymongo (sync, for Upstox quote path)
- Market data sources (in priority order):
  1. **Upstox API v2** for real-time NSE/BSE (when developer OAuth is active)
  2. **Yahoo Finance (yfinance)** as fallback when Upstox not connected — ~15min delayed for Indian markets
  3. **CoinGecko** free API for crypto (real-time, 120s server cache + 429 fallback)
- Live polling: dashboard 12s, stock detail 8s (stocks) / 12s (crypto)

## Auth & Payments
- JWT email/password (bcrypt, 7-day tokens)
- **MVP mode: signup auto-credits ₹1,00,000 demo cash, subscription_active=true, plan='free_starter'**
- 3 paid top-up plans kept in code (for activation when Razorpay live keys arrive):
  - titan_1l → ₹199 → ₹1,00,000 cash
  - titan_5l → ₹899 → ₹5,00,000 cash (MOST POPULAR)
  - titan_10l → ₹1499 → ₹10,00,000 cash
- Razorpay flow is MOCKED — `/api/subscription/activate` directly credits cash

## Upstox Integration (real-time NSE/BSE)
- Env vars in `/app/backend/.env`: UPSTOX_API_KEY, UPSTOX_API_SECRET, UPSTOX_REDIRECT_URI
- Endpoints:
  - `GET /api/upstox/status` — connection state + expiry
  - `GET /api/upstox/authorize-url` — returns Upstox OAuth URL for admin
  - `GET /api/upstox/callback` — handles code → exchanges for access token → stores in `db.upstox_token` (id: "main") with expiry at next 3:30 AM IST
- One-time daily login (developer flow). Quote function automatically falls back to yfinance when not authorized.
- Connect from app: Profile → Data Source → "Connect" button

## Features
1. Auth (Login, Register with auto ₹1L credit)
2. Dashboard — portfolio value, P&L, market overview ticker (Nifty/Sensex/Bank Nifty + BTC/ETH/SOL), holdings, watchlist, **auto-polls every 12s**
3. Trade tab — search NSE stocks (curated 50) + crypto (CoinGecko full list)
4. Stock/Crypto detail — SVG line chart with 6 timeframes, live quote polling (8s stocks / 12s crypto), Buy/Sell modal, watchlist toggle
5. Portfolio, Orders, Analytics (win rate, best/worst trade)
6. Compete — leaderboard with podium
7. Wallet — balance, Top-up CTA, transaction history
8. Top-up screen — 3-plan picker (MVP free), Razorpay-ready
9. What-If Simulator (historical hypothetical)
10. Loss Autopsy — rule-based educational insights
11. Profile — Upstox status/connect, tools links, sign out

## Open Items / Next Steps
1. Razorpay live keys → wire real checkout WebView in subscribe.tsx
2. Upstox needs the redirect URI registered in Upstox developer dashboard pointing to the backend callback
3. Upstox instrument master ingestion (right now using NSE_EQ|SYMBOL convention; works for top stocks)
4. Weekly league reset (cron)
5. Price alerts (push notifications)
6. Candlestick charts (intraday OHLC)
