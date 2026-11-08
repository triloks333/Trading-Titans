# Handoff — product analytics + live admin dashboard (2026-11-08)

Read this before starting. It replaces the "indicators / action→reaction" brief.

## Goal

1. **Product analytics the admin can trust.** The app records what users do —
   launches, screens and dwell time, button taps, rage taps, trades per symbol,
   win/loss streaks, margin shortfalls, paywall steps — and sends it to Supabase.
2. **A live admin dashboard** (admin panel → Intelligence tab) that updates
   on its own, with no reload needed: live event feed, active users, per-user drill-down,
   funnels per screen, button tap counts, per-symbol trading stats.
3. **Honest lifecycle messaging only**, e.g. a labelled recap pointing to Trade
   Autopsy after losses, real discounts the payment server honours, a crash
   apology that really credits the cash.

## Out of scope (decided with the owner — do not build)

- Using the `churn_plan/*.md` encyclopedias as the spec. They describe
  persuasion targeting (disguised pushes, fabricated stats, upsells aimed at
  users who are losing, tilting or nearly out of cash). Treat them as
  reference for *which events exist*, nothing more.
- New permissions to profile users (location for Wi-Fi identity, ringer/DND/
  volume/earbuds, battery) or "affluence" scoring from the phone model.
- Any push, banner or message whose text isn't literally true.

## Current state (all uncommitted on branch `titansv2`)

| File | State |
|---|---|
| `app/lib/main.dart` | **Done:** calls `flushToBackend()` + `recordCleanExit()` on `AppLifecycleState.paused`. Before this nothing reached Supabase. |
| `supabase/migrations/20261107233000_customer_intelligence_telemetry.sql` | **Applied to production 2026-11-08.** Creates `user_session_telemetry` with own-insert, own-read and admin-read RLS. The earlier draft's `v_trader_intelligence_metrics` view and RPC were dropped (the view would have leaked all users' order totals). |
| `app/lib/services/churn_telemetry_service.dart` | Existing. Records screens/taps/streaks locally; `flushToBackend()` inserts a session row. Rename/trim as needed. |
| `app/lib/screens/main/admin_customer_intelligence_screen.dart` | Existing. Polls every 4s but shows little and has hardcoded "READY" tiles. Rebuild. |
| `app/lib/services/action_reaction_engine.dart` | Existing. Contains the disguised "84% of traders in profit" push (random stock), a fake "lag smoothed" snackbar and a "+₹2,500 credited" message that credits nothing. **Remove or replace these first.** Called from `portfolio_screen.dart` (~L430). |
| `supabase/migrations/20261108120000_intel_engine.sql` | Written, not applied. Useful parts: `intel_events` table + admin-readable RLS, realtime publication, `intel_admin_overview()`, `intel_claim_crash_apology()` (₹2,500 demo cash, once/7 days). Review the offer-grant cascade before keeping it; trim what the new design doesn't use. |
| `supabase/functions/create-payment-order/index.ts` | Edited, not deployed. Applies a live `intel_offer_grants` row to one-time packs. Deploy only after its migration, and test one discounted purchase end to end. Revert if offers are dropped. |
| `app/lib/services/intel/intel_store.dart` | Done. Bounded local event log (30 days / 6,000 events). Reusable. |
| `app/lib/services/intel/intel_catalog.dart`, `app/assets/intel/catalog.json`, `scripts/gen_intel_catalog.py` | Catalogue of the churn_plan encyclopedias. Not in `pubspec.yaml`. Probably delete — the new design shouldn't depend on it. |

## Suggested build order

1. (Done) Telemetry table + admin read applied; rows appear once users run a build that includes the `main.dart` flush.
2. Replace the three false messages in `action_reaction_engine.dart`.
3. Event pipeline: `intel_store.dart` → batch insert into `intel_events` every 60s and on pause.
4. Dashboard: Supabase realtime on `intel_events`; tabs for Live feed, Users (drill-down), Screens, Buttons, Symbols.
5. `flutter analyze`, run the app, verify rows arrive and the dashboard updates live.

Commit and push per step; the owner builds the APK at the end (see memory "No APK per screen").
