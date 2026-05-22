# Migration Strategy: Trading Titans (MongoDB to Supabase)

## Current Architecture
- **Database**: MongoDB (motor AsyncIOMotorClient)
- **Backend**: FastAPI (Python), JWT Auth.
- **Data Models**: `users`, `orders`, `holdings`, `watchlist`, `upstox_token`, `upstox_state`.
- **Integrations**: Upstox (OAuth, Quotes), Yahoo Finance, CoinGecko.

## Target Architecture
- **Database**: Supabase PostgreSQL.
- **Auth**: Supabase Auth (replaces custom JWT + bcrypt).
- **Backend APIs**: Supabase Edge Functions (Deno/TypeScript) or keep FastAPI and connect to Postgres. Moving to Edge Functions is recommended to reduce hosting overhead.
- **Data Access**: PostgREST / Supabase JS client for direct frontend access, Edge Functions for market data / trading execution to maintain secure operations.

## Step-by-Step Migration Plan

### 1. Database Schema Translation
- Created `supabase/schema.sql` defining relational tables for the NoSQL collections.
- `users` maps to `public.profiles` (1:1 with `auth.users`).
- Used constraints to ensure data integrity (e.g., `CHECK (quantity > 0)` for orders/holdings).
- Designed indices to optimize order history queries (`user_id`, `created_at`).

### 2. Security Configuration (RLS)
- Implemented Row Level Security (RLS) in `schema.sql`.
- Users have full access to their own `orders`, `holdings`, and `watchlist`.
- Restricted `upstox_tokens` and `upstox_states` to backend (Service Role) only.

### 3. Data Migration
To move existing data from MongoDB to Supabase:
1. Extract data from MongoDB to JSON/CSV formats using a migration script.
2. For Users:
   - Map `password_hash` to Supabase Auth using the [Supabase Auth Import tools](https://supabase.com/docs/guides/auth/managing-user-data).
   - Insert `profiles` with the wallet balances and subscription info.
3. For Orders/Holdings/Watchlist: Insert records mapping the old user IDs (if UUIDs were used) or update references to new `auth.users` IDs.

### 4. Application Logic Migration
- **Auth**: Replace custom `auth/login` and `auth/register` endpoints with `@supabase/supabase-js` auth methods on the frontend.
- **Trading Execution (`/trade/order`)**: Move this logic to a Supabase Edge Function to prevent clients from manipulating balances or order totals. Alternatively, use a PostgreSQL function / trigger.
- **Market Data APIs (`/market/*`)**: These require outgoing HTTP requests to Upstox, Yahoo Finance, and CoinGecko, and caching mechanisms. These should be implemented as Edge Functions.

### 5. Deployment
- Use Supabase CLI to apply migrations: `supabase migration new init` and copy `schema.sql` into it.
- Run `supabase start` for local development.
- Deploy to Supabase Cloud using `supabase link` and `supabase db push`.
