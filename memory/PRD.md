# Trading Titans - Product Requirements Document

## Vision
A premium "paper trading" mobile app for Indian investors: trade real markets (NSE/BSE stocks + global crypto) with demo money. Pay ₹199 to unlock ₹1,00,000 virtual cash and the full Titan experience.

## Brand
- Name: Trading Titans
- Tagline: "Trade Bold. Lose Nothing." / "Real Market. Virtual Risk."
- Aesthetic: Parchment + Imperial Gold (premium, Dalal Street veteran)
- Fonts: Playfair Display (display), DM Sans (body), DM Mono (data)

## Stack
- Frontend: Expo Router + React Native + react-native-svg
- Backend: FastAPI + Motor (MongoDB)
- Market data: Yahoo Finance (yfinance, NSE/BSE) + CoinGecko (crypto), 15s server cache
- Auth: JWT (bcrypt, 7-day tokens) stored in expo-secure-store
- Payments: Razorpay (MOCKED activation flow — real keys can be wired via RAZORPAY_KEY_ID env)

## Features (MVP)
1. Email/password auth, secure JWT storage
2. Dashboard: portfolio value, P&L, market overview ticker strip (Nifty/Sensex/Bank Nifty + BTC/ETH/SOL), quick actions, holdings, watchlist
3. Trade tab: search NSE stocks + crypto, popular tiles
4. Stock/Crypto detail: live price, 6 timeframes (1D/1W/1M/3M/1Y/5Y), SVG line chart, key stats, watchlist toggle, position summary, Buy/Sell modal
5. Buy/Sell with wallet deduction, avg-price updates, realized P&L
6. Portfolio: holdings with current P&L, invested vs current, unrealized P&L
7. Wallet: balance, subscription status, transaction history
8. Subscription: ₹199 Razorpay flow (MOCKED) → credits ₹1,00,000
9. Compete (Leagues): leaderboard by realized P&L, podium for top 3
10. Analytics: total trades, win rate, best/worst trade, realized P&L
11. What-If Simulator: historical investment hypothetical (yfinance/coingecko)
12. Loss Autopsy: rule-based insights on losing trades (open + closed) with educational tips
13. Orders history, Profile, Sign out

## Backend API Endpoints
- POST /api/auth/register, /api/auth/login, GET /api/auth/me
- GET /api/market/overview, /api/market/quote, /api/market/search, /api/market/history
- POST /api/trade/order
- GET /api/portfolio, /api/orders, /api/analytics, /api/leaderboard
- GET/POST/DELETE /api/watchlist
- POST /api/whatif
- GET /api/autopsy
- POST /api/subscription/create-order, /api/subscription/activate

## Known Limitations / Future
- Razorpay integration is MOCKED (no real key currently). Real flow requires user-provided RAZORPAY_KEY_ID and signature verification in backend.
- Yahoo Finance is rate-limited and unofficial; production should use Angel One / NSE official APIs.
- No price alerts/notifications yet (planned).
- League weekly reset is not yet implemented (leaderboard is all-time realized P&L).
