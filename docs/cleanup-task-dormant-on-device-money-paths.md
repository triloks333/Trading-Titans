   # Cleanup task — remove the dormant on-device money paths

   **Status: NOT STARTED. Deliberately deferred.** Raised while doing the financial
   write lockdown; explicitly kept out of that change so a security migration and a
   large deletion did not land together.

   **Do not start this until the server-only architecture has been stable in
   production for a meaningful period** — long enough to cover a full trading week,
   expiry settlement, and at least one app release cycle.

   ## What to remove

   Three code paths in `app/lib/services/supabase_service.dart`, all currently inert:

   | Path | Gated by | What it writes |
   |---|---|---|
   | `_placeOrderLocal` | `_useServerPlaceOrder = true` | INSERT `orders`, UPDATE `profiles.wallet_balance`, INSERT/UPDATE/DELETE `holdings`, `place_fo_order_transaction` |
   | `_executePendingOrdersInner` | `_serverExecOnly = true` | UPDATE `orders` status/fill columns, UPDATE `profiles`, holdings mutations, DELETE `orders` |
   | `settleExpiredDerivatives` on-device body | `_serverExecOnly = true` | INSERT `orders`, INSERT `settlement_ledger`, UPDATE `profiles` |

   Roughly 1,000 lines, and a second complete implementation of the money logic
   alongside the Deno one.

   ## Why they should go

   They stopped being a revert path the moment the lockdown landed. Every table they
   write is now server-owned, so flipping `_serverExecOnly = false` or
   `_useServerPlaceOrder = false` no longer restores old behaviour — it produces a
   client that fails on `42501` at the first write. The comment on those flags already
   said they must stay `true` once the RLS lockdown was applied; that is now the case.

   Keeping them costs something real: two implementations of charges, margin, average
   price and P&L that can drift. They have drifted before — the intraday-versus-
   delivery charge-rate disagreement came from exactly this duplication.

   ## Why not now

   - A security migration should be auditable on its own. Mixing in a 1,000-line
   deletion makes the diff unreviewable and the rollback ambiguous.
   - If the lockdown does surface an unexpected problem, the smallest possible diff
   between "before" and "after" is worth having.
   - Deleting code is irreversible in practice even when it is reversible in git.

   ## Preconditions

   - [ ] Server-only execution stable across a full trading week, including expiry
   - [ ] `20260831000100_finish_orders_lockdown.sql` applied (temporary cancel grant gone)
   - [ ] `app_config.min_supported_version` at or above the release carrying
         `modify-order` / `cancel-order`
   - [ ] No production incident traced to the lockdown

   ## Scope when it happens

   1. Delete the three code paths and the `_useServerPlaceOrder` / `_serverExecOnly`
      flags, since a flag with one reachable value is noise.
   2. Delete whatever becomes unreachable with them — the local charge maths, the
      on-device claim helper, the local settlement helpers.
   3. Keep `place_fo_order_transaction` itself: `execute-pending-orders` still calls it
      as `service_role`. Only the Dart caller goes.
   4. Run `flutter analyze` and the full test suite; expect some tests to reference
      deleted helpers and need re-pointing at the server path.
   5. Re-run `supabase/tests/financial_integrity_probe.sql`. It must stay at all-PASS,
      which proves the deletion changed no privilege.

   Explicitly **not** in scope: the execution trigger rules, `resolveFillPrice`, the
   claim/CAS idempotency, bid/ask, partial fills, or the polling architecture.
