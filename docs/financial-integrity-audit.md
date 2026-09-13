# Financial integrity audit

Scope: every table, RPC and client path that can move money, positions, P&L, order
state or trade history. **Nothing has been applied.** All findings below were
verified empirically against production inside transactions that were rolled back,
by impersonating a real user's `authenticated` role and JWT claims — which is
exactly what PostgREST hands a browser or the app.

Test subject: a regular (non-owner) account, `9886314f…`.

---

## A. Current vulnerabilities

### A1. Verified exploitable

| # | Path | Proven effect |
|---|---|---|
| V1 | `orders` UPDATE | `realized_pnl = 999999` **and** `status = 'executed'` written on own order |
| V2 | `orders` UPDATE `created_at` | **159 rows backdated** to 2020-01-01 in one statement |
| V3 | `orders` INSERT | fabricated row: `status='executed'`, `realized_pnl=9999999` |
| V4 | `holdings` INSERT | position created from nothing: 100,000 units @ ₹0.01 |
| V5 | `holdings` UPDATE | `quantity + 1000000` across **12 rows** |
| V6 | `holdings` DELETE | **12 rows** deleted |
| V7 | `fo_positions` INSERT | `net_qty=5000`, `margin_blocked=0`, `realized_pnl=9999999` |
| V8 | `fo_positions` UPDATE | same three fields rewritten on an existing position |
| V9 | `fo_positions` DELETE | position erased |
| V10 | `trade_autopsies` UPDATE | `pnl` rewritten across **6 rows** |
| V11 | `referral_commissions` INSERT | `commission_amount = 9999999` |
| V12 | `crypto_holdings` INSERT/UPDATE/DELETE | authorised (probe stopped only by a NOT NULL, `SQLSTATE 23502`, not by permissions) |
| V13 | `settlement_ledger` INSERT | authorised (same, `23502`) |
| V14 | `grant_challenge()` RPC | **₹50,000 of claimable cash created in a single call** |
| V15 | `credit_demo_cash()` RPC | up to ₹10,00,000 per call, unlimited calls, no payment check |
| V16 | `activate_subscription()` RPC | ₹1L/₹5L/₹10L credit **and** sets `plan`, no payment check |

The root cause for V1–V13 is one pattern repeated across six tables: a policy of
the shape `USING (auth_uid() = user_id)` with no `WITH CHECK` and no column
restriction, plus a table-wide grant. **RLS cannot restrict columns**, so "may edit
own row" and "may rewrite own P&L" are the same privilege. This is not a
misconfiguration to be spotted — it is the documented API surface of the tables.

### A2. V14 in detail — the only path that creates money without touching a table

`grant_challenge(p_user_id uuid, p_key text, p_cycle text)` is **SECURITY
DEFINER**, `EXECUTE` granted to **`anon` and `authenticated`**, takes an
**arbitrary user id**, and contains **no `auth.uid()` check and no `is_admin()`
check**. Being DEFINER, it bypasses RLS — including the `is_admin()`-only INSERT
policy on `rewards`, which it writes to directly.

Money path: `grant_challenge(my_uid, key, any_string)` → `rewards` row →
`claim_reward(id)` → `profiles.wallet_balance` increases. `claim_reward` itself is
correctly scoped to `auth.uid()`; it is doing its job on a forged reward.

Guards that do exist and do work:
- `repeat_limit` per challenge key (verified: 60 forged calls on a
  `repeat_limit = 1` challenge yielded exactly **1** grant)
- a **₹75,000 per calendar month** ceiling on granted `reward_amount` per user

`p_cycle` is caller-supplied and forms part of the `ON CONFLICT` key, so
per-cycle uniqueness is not a limit at all.

Quantified exposure across the 25 active challenges:

| Measure | Value |
|---|---|
| Largest single forged grant | **₹50,000** |
| Total forgeable across all keys | **₹142,000** |
| Challenges with `repeat_limit = NULL` (unlimited) | **3** |
| Effective sustained rate | **₹75,000 / month, indefinitely** |

It can also be aimed at *other* users — it grants XP and notifications to any
`p_user_id`, so it is a leaderboard-manipulation and nuisance vector too.

### A3. Already safe — verified, not assumed

I expected `profiles` to be the worst of these. It is not, and the previous
session's claim that a user could write their own `wallet_balance` was **wrong**.

| Path | Result | Why |
|---|---|---|
| `profiles` UPDATE (`wallet_balance`, `total_realized_pnl`, `is_admin`) | **BLOCKED** `42501 permission denied for table profiles` | No UPDATE privilege at all — not table-level, not column-level. The UPDATE *policy* is vestigial. |
| `profiles` INSERT | **BLOCKED** RLS | No INSERT policy exists (the grant does) |
| `wallet_transactions` INSERT | **BLOCKED** RLS | SELECT policy only |
| `pnl_history` INSERT | **BLOCKED** RLS | SELECT policy only |
| `realized_pnl_log` INSERT | **BLOCKED** RLS | no policies at all |
| `user_challenges` INSERT | **BLOCKED** RLS | SELECT policy only |
| `rewards` INSERT | **BLOCKED** RLS | requires `is_admin()` |
| `rewards` UPDATE | **BLOCKED** `42501` | no UPDATE privilege |
| `orders` UPDATE `user_id` | **BLOCKED** RLS | with no `WITH CHECK`, Postgres reuses `USING` for the new row, so the row cannot be reassigned |
| `orders` DELETE | 0 rows | no DELETE policy; RLS filters silently rather than erroring |
| `place_fo_order_transaction()` | **BLOCKED** `42501 permission denied for table profiles` | see A4 |
| `record_wallet_transaction()`, `notify_balance_change()` | not callable | both `RETURNS trigger`; the EXECUTE grants are harmless |

### A4. `place_fo_order_transaction` — fragile, not currently exploitable

`(p_user_id, p_wallet_debit, p_wallet_credit, p_margin_blocked, p_margin_released,
p_position_data jsonb, p_order_data jsonb, p_skip_balance_check boolean)`,
**SECURITY INVOKER**, `EXECUTE` to `anon` and `authenticated`. It takes an
arbitrary user id, an arbitrary wallet credit, and a flag that switches off its own
`FOR UPDATE` balance guard.

I called it as a normal user asking for a ₹50,00,000 credit with
`p_skip_balance_check = true`. It **failed** with `42501 permission denied for
table profiles`, wallet delta ₹0.00 — because INVOKER means it runs with the
caller's privileges, and the caller has no `profiles` UPDATE privilege. The whole
call rolled back, so no position or order row survived either.

So its safety is **accidental**: it rests entirely on the absence of one grant. Any
future migration that grants `profiles` UPDATE to `authenticated` turns this into a
money printer, and nothing in the function itself would object. It should be
revoked on that basis, not because it is live-exploitable today.

---

## B. Legitimate client operations

Established by reading every client call site, not by assumption.

| Table | Legitimate client operations | Live client writes found |
|---|---|---|
| `orders` | SELECT own; cancel; modify quantity/limit of a pending order | cancel + modify (both already moved to edge functions in the pending Phase 2 work) |
| `profiles` | SELECT own | **none** — all writes already go through DEFINER RPCs |
| `holdings` | SELECT own | **none live.** All 12 write sites are in `_placeOrderLocal` / `_executePendingOrdersInner`, dormant behind `_useServerPlaceOrder` / `_serverExecOnly` |
| `fo_positions` | SELECT own | **none live** (same dormant paths) |
| `crypto_holdings` | SELECT own | **none** (table is empty, 0 rows) |
| `trade_autopsies` | SELECT own | **none** — written by the `trade-autopsy` edge function |
| `settlement_ledger` | SELECT own | **none live** (dormant settlement path) |
| `referral_commissions` | SELECT own | **none** — `apply_referral_code()` RPC is the write path |
| `wallet_transactions`, `pnl_history`, `realized_pnl_log`, `user_challenges`, `rewards`, `orders_archive` | SELECT own | none (already write-denied) |

The web app (`web/src/**`) writes **only** `orders`, via cancel/modify. It never
touches holdings, positions or profiles.

The legitimate `profiles` write RPCs, all SECURITY DEFINER and all scoped to
`auth.uid()`: `save_user_preferences`, `accept_terms`, `touch_login_streak`,
`ensure_profile`, `convert_guest_account`, `apply_referral_code`, `claim_reward`.

---

## C. Fields that must be server-owned

`profiles` — all 23 columns enumerated; split by owner:

| Server-owned | Client-settable (via the existing DEFINER RPCs, never directly) |
|---|---|
| `id`, `email`, `wallet_balance`, `subscription_active`, `plan`, `total_realized_pnl`, `created_at`, `referral_code`, `referred_by`, `is_admin`, `login_streak`, `longest_login_streak`, `last_login_date`, `total_xp`, `challenge_baseline_capital`, `converted_at`, `terms_accepted_at`, `terms_version` | `name`, `display_currency`, `preferred_markets`, `onboarding_completed_at`, `location` |

Since `profiles` currently has **no** UPDATE grant, this table is already at the
target state. The five client-settable fields are reached through
`save_user_preferences` and are not a reason to grant anything.

Server-owned elsewhere:

- `orders` — everything. `status`, `realized_pnl`, `quantity`, `price`,
  `limit_price`, `total`, `user_id`, `created_at`, `executed_at`,
  `execution_price_source`, `execution_reference_price`, all charge columns.
- `holdings` — everything: `quantity`, `avg_price`, `native_avg_price`, `symbol`.
- `fo_positions` — everything: `net_qty`, `avg_entry_price`, `margin_blocked`,
  `realized_pnl`, `is_settled`, `settlement_price`, `lot_size`.
- `crypto_holdings`, `settlement_ledger`, `trade_autopsies`,
  `referral_commissions` — everything.

---

## D. Proposed RLS policies

```
orders          SELECT  unchanged ("Users can view own orders")
                INSERT  policy dropped
                UPDATE  blanket policy dropped; replaced by
                        "orders_owner_may_cancel_only"
                          USING      (auth_uid() = user_id AND status = 'pending')
                          WITH CHECK (auth_uid() = user_id AND status = 'cancelled')
                        (temporary — see I and K)

holdings        SELECT  unchanged
                INSERT/UPDATE/DELETE policies dropped
fo_positions    SELECT  unchanged
                INSERT/UPDATE/DELETE policies dropped
crypto_holdings SELECT  unchanged
                INSERT/UPDATE/DELETE policies dropped
trade_autopsies SELECT  unchanged
                INSERT/UPDATE/DELETE policies dropped
settlement_ledger SELECT unchanged
                INSERT  policy dropped
referral_commissions SELECT unchanged
                INSERT/UPDATE policies dropped

profiles        unchanged. Already correct; the vestigial UPDATE policy can be
                dropped for clarity but grants nothing today.
```

## E. Proposed GRANT / REVOKE

```sql
-- orders: no column-level write except the one cancel transition
revoke insert, update, delete on public.orders from authenticated, anon;
grant  update (status) on public.orders to authenticated;   -- temporary, see K

-- positions and history: server-owned outright
revoke insert, update, delete on public.holdings            from authenticated, anon;
revoke insert, update, delete on public.fo_positions        from authenticated, anon;
revoke insert, update, delete on public.crypto_holdings     from authenticated, anon;
revoke insert, update, delete on public.trade_autopsies     from authenticated, anon;
revoke insert, update, delete on public.settlement_ledger   from authenticated, anon;
revoke insert, update, delete on public.referral_commissions from authenticated, anon;

-- tidy up grants RLS is already blocking, so a future policy cannot re-open them
revoke insert, update, delete on public.wallet_transactions from authenticated, anon;
revoke insert, update, delete on public.pnl_history         from authenticated, anon;
revoke insert, update, delete on public.realized_pnl_log    from authenticated, anon;
revoke insert, update, delete on public.user_challenges     from authenticated, anon;
revoke insert, update, delete on public.orders_archive      from authenticated, anon;
revoke insert, delete         on public.profiles            from authenticated, anon;
revoke insert, delete         on public.rewards             from authenticated, anon;

-- RPCs
revoke execute on function public.grant_challenge(uuid, text, text)
  from authenticated, anon;
revoke execute on function public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, boolean) from authenticated, anon;

-- DO NOT revoke evaluate_challenges(uuid). The app calls it (as
-- `rpc('evaluate_challenges')`, relying on `p_user_id DEFAULT auth.uid()`), and it
-- is already correctly guarded — a signed-in non-admin has p_user_id overwritten
-- with auth.uid() whatever they pass, and it grants only challenges whose criteria
-- the account actually meets. It is the safe front door; grant_challenge is the
-- unlocked back one.
```

`service_role` is unaffected by all of the above, so every edge function and cron
keeps working.

## F. Required edge function / RPC changes

Already built and tested in the reviewed Phase 2 work:
- `cancel-order`, `modify-order`, `_shared/order_edit.ts` (19 Deno tests passing)

Newly required by this audit:

1. **`grant_challenge`** — leave the body alone and revoke EXECUTE. **Verified
   safe to revoke:** its callers are `evaluate_challenges` (DEFINER) and
   `evaluate_challenges_all` (DEFINER), both owned by `postgres`, so the internal
   privilege check is made as `postgres`, not as the original caller. The nightly
   `evaluate-challenges-daily` cron and the app's own `evaluate_challenges()` call
   both keep working.
2. **`credit_demo_cash` / `activate_subscription`** — must require a verified
   `payment_orders` row before monetisation is switched on. Covered in
   `docs/monetisation-plan.md` Phase 1; still open.
3. No change to `place_fo_order_transaction`'s body — revoke EXECUTE only. It is
   called by `execute-pending-orders` as service_role.

## G. Required Flutter changes

Already done in the reviewed work: `cancelOrder` / `modifyOrder` call the edge
functions via `_invokeOrderFunction`.

Additionally required:
- Update the comment on `_serverExecOnly` / `_useServerPlaceOrder` to record that
  the lockdown is applied and flipping either now fails at the database.
- Consider deleting `_placeOrderLocal`, `_executePendingOrdersInner` and
  `settleExpiredDerivatives`' on-device body. After this migration they cannot
  work, so keeping them is keeping a revert path that no longer reverts. Deleting
  removes ~1,000 lines of duplicated money logic. **Recommend, but out of scope for
  a security migration** — worth its own change.

## H. Required web changes

Already done: `cancelOrder` / `modifyOrder` call the functions via
`callOrderFunction`. The web app has no other write to any audited table, so
nothing else changes.

## I. Backward compatibility

The Android app ships through Play and cannot be force-updated, so anything an
installed build does must keep working or fail visibly.

| Client path | After lockdown |
|---|---|
| Place order | works (already `place-order`) |
| **Cancel, current build** | works via `cancel-order` |
| **Cancel, older build** (direct UPDATE) | works, via the temporary `status` grant |
| **Modify, older build** (direct UPDATE) | **BREAKS** — permission denied, surfaced as "Failed to modify order: …". Visible, not silent. |
| Read orders / holdings / positions / P&L | unaffected |
| Preferences, terms, streaks, rewards, referrals | unaffected (DEFINER RPCs) |
| Legacy on-device execution / settlement | **BREAKS** — already inert behind flags whose own comment says they must stay off once this lands |

The only user-visible regression is Modify on builds older than the release that
routes it through `modify-order`.

## J. Tests proving a normal user cannot manipulate financial state

**Existing, passing:** 19 Deno tests in `_shared/order_edit_test.ts` (ownership,
order state, quantity/price validity, exit clamp, `price`/`limit_price` in step,
market orders get no `limit_price`); 423 Flutter tests; `order_rules_test.dart`
pins the inclusive trigger rule and the modify invariant.

**To add — a repeatable RLS probe** committed as
`supabase/tests/financial_integrity_probe.sql`, being the script used for this
audit, asserting that as `authenticated` with a user's own claims **every** one of
these is refused:

| Assertion | Expected |
|---|---|
| `orders` UPDATE `realized_pnl` / `status` / `created_at` | denied |
| `orders` INSERT | denied |
| `holdings` INSERT / UPDATE `quantity` / DELETE | denied |
| `fo_positions` INSERT / UPDATE `net_qty`,`margin_blocked`,`realized_pnl` / DELETE | denied |
| `crypto_holdings` / `trade_autopsies` / `settlement_ledger` / `referral_commissions` write | denied |
| `profiles` UPDATE `wallet_balance`,`total_realized_pnl`,`is_admin` | denied (already) |
| `grant_challenge(own_uid, key, forged_cycle)` | denied |
| `place_fo_order_transaction(...)` | denied |
| `orders` UPDATE `status` pending→cancelled | **allowed** (until K step 4) |
| `orders` UPDATE `status` pending→executed | denied |
| SELECT own orders / holdings / positions | **allowed** |

Every assertion must distinguish `42501` (permission/RLS) from `23502` (NOT NULL).
Three of my first-pass probes reported "blocked" when the write had in fact been
**authorised** and only stopped by a missing column — `fo_positions`,
`settlement_ledger` and `crypto_holdings` were all wrongly cleared until I retested
with valid data. A probe that does not check SQLSTATE will lie in the safe
direction.

## K. Migration sequencing

1. **Deploy** `cancel-order` + `modify-order`. Additive; nothing references them.
2. **Apply** the lockdown migration (D + E, keeping the temporary `status` grant).
   Nothing live breaks; older-build Modify starts failing visibly.
3. **Release** the Flutter app and deploy the web build.
4. **Wait** for adoption, then apply `20260831000100_finish_orders_lockdown.sql` to
   drop the temporary `status` grant. Gate on `app_config.min_supported_version`
   reaching the release from step 3.
5. **Separately**, close `credit_demo_cash` / `activate_subscription` before
   monetisation goes live.

Steps 1 and 2 can go together. Step 4 must not precede step 3.

---

## Paths that break — the complete list

1. **Modify Order on app builds older than the step-3 release.** Fails with a
   permission error the UI already displays. The only user-visible regression.
2. **`_placeOrderLocal`** (`_useServerPlaceOrder = false`) — INSERT into `orders`,
   UPDATE `profiles`, INSERT/UPDATE/DELETE `holdings`. Dormant.
3. **`_executePendingOrdersInner`** (`_serverExecOnly = false`) — the same set plus
   `place_fo_order_transaction`. Dormant.
4. **`settleExpiredDerivatives`** on-device body (`_serverExecOnly = false`) —
   INSERT `orders`, INSERT `settlement_ledger`, UPDATE `profiles`. Dormant.
5. **Nothing else.** `grant_challenge` has no client caller, and its two internal
   callers are DEFINER functions owned by `postgres`, so the revoke is invisible to
   them. Checked and cleared, not assumed.

Items 2–4 are the intended end state of the server-trust migration this codebase
has been executing; their own comments say the flags must stay on once the RLS
lockdown lands.

---

## Corrections to the previous session

Two things I reported earlier were wrong, and the difference matters:

1. **`profiles` is not client-writable.** I inferred it from a permissive UPDATE
   *policy* without checking the *grant*. There is no UPDATE grant, so the policy
   never applies. The wallet was never directly writable.
2. **`place_fo_order_transaction` is not currently exploitable**, for the same
   reason — it is INVOKER and inherits the caller's lack of privilege.

Both corrections came from probing rather than reading the catalogue, which is why
J insists the probe is committed and run rather than reasoned about.
