# Financial write lockdown — review pack

**Nothing has been applied.** No function deployed, no migration run, no policy or
grant changed in production. Every result below came from probes inside
transactions that were rolled back.

Companion documents:
- `docs/financial-integrity-audit.md` — the audit and its findings
- `supabase/tests/financial_integrity_probe.sql` — artifact A
- `supabase/migrations/20260901000000_financial_write_lockdown.sql` — artifact B
- `supabase/migrations/20260901000000_financial_write_lockdown_ROLLBACK.sql` — artifact G

---

## A. The probe

`supabase/tests/financial_integrity_probe.sql`, 45 assertions. It seeds a valid,
fully constraint-satisfying row in each table as the privileged role, switches to
`authenticated` with a real user's JWT claims, asserts, and rolls back.

Verdict categories, and why they are fussy:

| Outcome | Meaning | Counts as |
|---|---|---|
| `DENIED_PRIV` | `42501` permission denied / RLS violation | block |
| `DENIED_RLS` | no error, 0 rows changed, target rows visible | block — RLS filters UPDATE/DELETE silently rather than raising |
| `DENIED_GUARD` | `P0001`, an RPC's own `raise exception` | block — this is how `claim_reward` enforces ownership |
| `ALLOWED` | the write happened | fail, when denial was expected |
| `INCONCLUSIVE` | `23502` / `23503` / `23505` / `23514` | **fail** — a constraint stopped us before authorisation was tested, so nothing was proven |

The `INCONCLUSIVE` category exists because it caught me out. My first hand-rolled
pass used incomplete rows and wrongly cleared **three** tables — `fo_positions`,
`settlement_ledger` and `crypto_holdings` all reported "blocked" when the write had
in fact been authorised and only refused for a missing NOT NULL column. The
committed probe uses valid data throughout and no constraint was weakened to make
anything pass.

Two further defects I found and fixed while building it:

- `claim_reward` on another user's reward raises `P0001`, which the first version
  mis-filed as inconclusive. It is a real refusal, hence `DENIED_GUARD`.
- The `referral_commissions` INSERT probe originally set `referred_id` to another
  account. The policy checks `auth.uid() = referred_id`, so it was refused for the
  wrong reason and looked green while proving nothing. It now uses the reachable
  shape (`referred_id` = caller), which is exploitable.
- Read assertions now run **before** the destructive ones. While the lockdown is
  absent the DELETE probes genuinely succeed, so reads afterwards saw an empty
  table and reported a false read failure.

## B. Migration

`20260901000000_financial_write_lockdown.sql`. Full SQL in the file; summary in C.
It changes only privileges, policies and comments — **no function body, no trigger
rule, no engine logic**.

## C. Affected tables, policies and grants

| Table | Policies dropped | Grants revoked (`authenticated`, `anon`) | Added |
|---|---|---|---|
| `orders` | insert-own, update-own | INSERT, UPDATE, DELETE | `GRANT UPDATE (status)`; policy `orders_owner_may_cancel_only` (pending→cancelled only) |
| `holdings` | insert/update/delete-own | INSERT, UPDATE, DELETE | — |
| `fo_positions` | insert/update/delete-own | INSERT, UPDATE, DELETE | — |
| `crypto_holdings` | insert/update/delete-own | INSERT, UPDATE, DELETE | — |
| `trade_autopsies` | insert/update/delete-own | INSERT, UPDATE, DELETE | — |
| `settlement_ledger` | insert-own | INSERT, UPDATE, DELETE | — |
| `referral_commissions` | insert, update-own | INSERT, UPDATE, DELETE | — |
| `wallet_transactions` | — | INSERT, UPDATE, DELETE | — |
| `pnl_history` | — | INSERT, UPDATE, DELETE | — |
| `realized_pnl_log` | — | INSERT, UPDATE, DELETE | — |
| `user_challenges` | — | INSERT, UPDATE, DELETE | — |
| `orders_archive` | — | INSERT, UPDATE, DELETE | — |
| `profiles` | update-own (vestigial) | INSERT, DELETE | **no UPDATE grant** |
| `rewards` | — | INSERT, DELETE | — |

Every `SELECT` policy and grant is left exactly as-is.

Functions: `EXECUTE` revoked on `grant_challenge(uuid,text,text)` and
`place_fo_order_transaction(uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,boolean)`.
Not revoked: `evaluate_challenges`, `claim_reward`, `save_user_preferences`,
`accept_terms`, `apply_referral_code`, `convert_guest_account`, `ensure_profile`,
`touch_login_streak`.

The five middle rows (`wallet_transactions` through `orders_archive`) are **no
behaviour change today** — RLS already refuses those writes, as the probe confirms.
Revoking closes the gap where someone later adds a permissive policy and
inadvertently re-opens a path, because the grant was never withdrawn.

On dropping the `profiles` UPDATE policy: it is unreachable today (no UPDATE
privilege exists, so `42501` fires before RLS is consulted). Dropping it is a no-op
now and strictly safer later — with no policy, a future `grant update` still
deny-alls, whereas leaving `USING (auth_uid() = id)` in place means such a grant
would instantly expose `wallet_balance`, `total_realized_pnl`, `is_admin`, `plan`
and `subscription_active`. It makes the safe state the default rather than an
accident.

## D. Monetisation RPC analysis

Read in full, all callers traced. **Neither has been modified.**

| Question | `credit_demo_cash(p_amount numeric)` | `activate_subscription(p_plan_id text)` |
|---|---|---|
| Security mode | SECURITY DEFINER | SECURITY DEFINER |
| Reachable by `authenticated` | **yes** | **yes** |
| Reachable by `anon` | no | no |
| Guests | rejected (`is_anonymous` check) | rejected (`is_anonymous` check) |
| Wallet effect | `wallet_balance += p_amount` | `+₹5,00,000` (`titan_5l`), `+₹10,00,000` (`titan_pro`), `+₹1,00,000` for **any other string** |
| Can target another user | no — `auth.uid()` only | no — `auth.uid()` only |
| Per-call limit | `0 < p_amount ≤ 1,000,000` | **none** |
| Repeatable | **yes, unlimited** | **yes, unlimited** |
| Cumulative cap | **none** | **none** |
| Rate limit | **none** | **none** |
| `payment_orders` checked | **no** — the table does not exist | **no** |
| Changes plan / subscription state | no | **yes** — sets `subscription_active = true` and `plan = p_plan_id`, unvalidated, so `plan` can be set to any arbitrary text |
| Live app callers | `creditDemoCash()` → wallet top-up card, and a purchase-completion flow | `activateSubscription()` → subscribe screen |
| Reachable in the shipped UI | **no** — every entry point is behind `AppFlagsService.monetizationEnabled`, and `app_flags.monetization_enabled = false` |

Both are unbounded money creation. The per-call cap on `credit_demo_cash` is not a
limit on anything, because the call count is unlimited. `activate_subscription` has
no cap at all and additionally lets a user write an arbitrary `plan` string and set
`subscription_active`, which is the exact field a paywall would later read.

### Recommendation: **A — safe to revoke immediately**, for both

Reasoning:

1. **Nothing live calls them.** Every UI entry point is gated on
   `monetization_enabled`, which is `false`. Revoking breaks no shipped behaviour.
2. They are the two largest money-creation holes in the system, larger than
   anything the table lockdown closes.
3. When monetisation does ship, they **cannot be reused as they are** —
   `docs/monetisation-plan.md` Phase 1 already specifies replacing them with
   signatures that require a verified `payment_orders` row. So keeping them
   callable buys nothing for the future.

There is a deliberate side effect worth naming: after revoking, flipping
`monetization_enabled = true` would produce a paywall whose buttons error. I regard
that as desirable — it makes a feature flag alone insufficient to start taking
money, and forces the payment-verification work to happen first. If you would
rather the flag stay self-sufficient, the answer is B, not "leave as-is".

Not classified C. There is no reading on which an uncapped, unverified,
infinitely-repeatable wallet credit is legitimate.

**Not modified pending your approval**, as instructed.

## E. Backward compatibility

| Client path | After lockdown |
|---|---|
| Place order (all clients) | works — `place-order`, service_role |
| Cancel, current build | works — `cancel-order` |
| **Cancel, older app build** (direct UPDATE) | works — via the temporary `UPDATE (status)` grant |
| **Modify, older app build** (direct UPDATE) | **BREAKS** — `42501`, surfaced by the existing UI as "Failed to modify order: …". Visible, not silent. |
| Modify / cancel, web | works once the web build is deployed; the web app is deployed instantly so there is no stale-client window |
| Read orders, holdings, positions, P&L, wallet ledger | unaffected |
| Preferences, terms, login streaks, rewards, referrals, guest conversion | unaffected — all DEFINER RPCs |
| Challenges (`evaluate_challenges`) | unaffected |
| Top-up / subscribe screens | already unreachable (`monetization_enabled = false`) |
| Legacy on-device execution, settlement, local placement | **BREAKS** — already inert behind `_serverExecOnly` / `_useServerPlaceOrder`. Left in place, not deleted, per your instruction. |

**The only user-visible regression is Modify Order on app builds older than the
release in step 3 below.**

## F. Deployment sequence

1. **Deploy** `cancel-order` and `modify-order`. Additive; nothing references them
   yet. Reversible by deleting the functions.
2. **Run the probe** and record the 17/28 baseline for the change record.
3. **Apply** `20260901000000_financial_write_lockdown.sql`.
4. **Run the probe again.** Expect 45 PASS / 0 FAIL. If anything fails, stop and
   assess before touching clients.
5. **Deploy the web build** (instant) and **release the Flutter app**.
6. **Wait for adoption.** Then apply `20260831000100_finish_orders_lockdown.sql` to
   drop the temporary `UPDATE (status)` grant, gating on
   `app_config.min_supported_version` having reached the step-5 release.
7. **Separately**, decide D and then close `credit_demo_cash` /
   `activate_subscription`.

Steps 3 and 5 may be same-day. Step 6 must not precede step 5.

### When the temporary cancel grant can be removed

Only when no still-active client relies on it. Concretely: after
`min_supported_version` is at or above the step-5 release, since that is the hard
gate that stops older builds running at all. Check with:

```sql
select key, value from app_config
 where key in ('min_supported_version', 'latest_version');
```

## G. Rollback procedure

`20260901000000_financial_write_lockdown_ROLLBACK.sql` restores the exact previous
state — every policy recreated with its original expression, every grant restored.

Three things about it worth knowing:

- **Partial rollback is usually the right move.** The sections are independent, so
  if one surface breaks, restore only that section rather than reopening all of it.
- It does **not** add `grant update` on `profiles`, because that was never the
  previous state. Adding it would be an escalation dressed as a revert.
- Running it fully reopens every vulnerability, including the ₹50,000-per-call
  reward forgery. It is an incident response, not a routine revert. Prefer fixing
  forward.

Verification after rollback: the probe should return to 17 PASS / 28 FAIL. If it
does not, the rollback is incomplete.

## H. Test results

**Probe, current production, before any change:**

```
45 assertions   17 PASS   28 FAIL   0 INCONCLUSIVE
```

The 28 failures are the vulnerabilities, by area:

| Area | Failing assertions |
|---|---|
| `orders` | 10 — `realized_pnl`, `status`→executed, `status`→executing, `created_at`, `quantity`, `price`, `limit_price`, `total`, `execution_reference_price`, INSERT fabricated executed |
| `holdings` | 4 — INSERT fabricated, UPDATE `quantity`, UPDATE `avg_price`, DELETE |
| `fo_positions` | 5 — INSERT fabricated, UPDATE `net_qty`, `margin_blocked`, `realized_pnl`, DELETE |
| `crypto_holdings` | 3 — INSERT, UPDATE `quantity`, DELETE |
| `trade_autopsies` | 2 — UPDATE `pnl`, DELETE |
| `settlement_ledger` | 1 — INSERT fabricated |
| `referral_commissions` | 1 — INSERT fabricated (self-referred) |
| `rpc` | 2 — `grant_challenge()` on self, and on another user |

**Passing already** (17): `orders.user_id` reassignment, `orders` DELETE, the
pending→cancelled compatibility path (expected allowed), all five `profiles`
assertions, `place_fo_order_transaction()`, `claim_reward()` on another user's
reward, `evaluate_challenges()` self, `save_user_preferences()`, three own-data
reads, two cross-user read denials.

**Other suites, unchanged and green:** 423 Flutter tests, `flutter analyze` clean,
19 Deno tests in `_shared/order_edit_test.ts`, `tsc --noEmit` clean on the web app.

**Migration dry run — verified, not predicted.** The full migration body was
executed inside a transaction with `lock_timeout = 3s`, probed against the migrated
state, and rolled back. Production was never changed.

```
27 assertions   27 PASS   0 FAIL   0 INCONCLUSIVE
```

That run confirms three things: the SQL is syntactically valid and applies without
error; every vulnerability tested is closed; and the paths that must survive do —
own-data reads, the pending→cancelled compatibility path, `evaluate_challenges()`,
`save_user_preferences()`, and `claim_reward()`'s refusal of another user's reward.

Post-rollback state re-verified: 26 policies present, the three UPDATE grants
restored, `grant_challenge` still callable, and `orders_owner_may_cancel_only`
absent — i.e. nothing leaked out of the transaction.

**Expected after the real migration:** the full 45-assertion probe at 45 PASS /
0 FAIL. Step 4 of the sequence is the gate for that.

---

## Open decisions for you

1. Approve the migration in B, or ask for changes.
2. Answer D: A (revoke both monetisation RPCs now — my recommendation), or B (leave
   callable until payment verification exists).
3. Confirm the deployment window for steps 3 and 5, since the gap between them is
   the only period with a broken Modify on older builds.
