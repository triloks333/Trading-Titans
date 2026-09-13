# Testing guide — what runs where

This project's test coverage spans several layers. Some run in CI today; others
need infrastructure (a device, a Deno runner, a k6 binary, a staging backend)
and are provided here as ready-to-run scripts.

## ✅ Runs today with `flutter test` (in `app/test/`)

| Layer | Files | What it covers |
|---|---|---|
| Regression | `exit_position_order_test.dart`, `fo_settlement_test.dart`, `order_notifications_and_runaway_lots_test.dart` | Bugfix specs converted to property/unit tests |
| Unit (logic) | `gating_test.dart`, `glossary_test.dart`, `app_constants_test.dart`, `option_pricing` etc. | Pure functions and constants |
| Widget/UI | `widgets_test.dart`, `widget_test.dart` | EmptyState, ErrorState, StatCell, TrendArrow, INR formatter |

Run: `cd app && flutter test`

To add a coverage gate locally:
```
cd app
flutter test --coverage
# then inspect coverage/lcov.info (e.g. with genhtml or a lcov badge tool)
```

## ⚙️ Needs a runner / backend — provided here, not in `flutter test`

### Load test — quotes (k6)
```
k6 run -e SUPABASE_URL=https://<ref>.supabase.co -e ANON_KEY=<key> \
  scripts/load_tests/quote_load_test.js
```

### Stress test — concurrent orders (k6)
> Run against a **dev/staging project or a Supabase branch DB**, never production.
```
k6 run -e SUPABASE_URL=https://<ref>.supabase.co -e USER_JWT=<test-user-token> \
  scripts/load_tests/order_stress_test.js
```

### API tests — edge functions (Deno)
Each function under `supabase/functions/<name>/` can be tested with Deno's
built-in test runner. Co-locate a `*_test.ts` beside the function and run:
```
supabase functions serve   # in one terminal (local)
deno test --allow-net supabase/functions/<name>/<name>_test.ts
```

### Integration test — login → trade → settle (Flutter)
Requires adding `integration_test` to `app/pubspec.yaml` dev_dependencies and a
connected device/emulator:
```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```
```
cd app && flutter test integration_test/app_flow_test.dart
```

### Security assertions (SQL / RLS)
These are verifiable directly against the database (already manually confirmed
once via MCP — see TECH_DEBT.md). To automate, run as a non-admin user:
```sql
-- guests must be blocked from crediting demo cash
select credit_demo_cash();              -- expect: permission/JWT error

-- non-admins must read zero profile rows
select count(*) from profiles;          -- expect: 0 for a non-owner/non-admin
```

## Why the split
The Flutter test sandbox has no network, no device, and no Deno/k6 binaries, so
HTTP/concurrency/integration suites genuinely cannot run there. Rather than fake
green checks, those layers live as scripts you run in their proper environment.
