# Order execution — diagnosis and fix plan

Response to `docs/tradingtitans-order-execution-fix.md`. That document's closing
instruction was the right one: inspect the backend before changing it. Doing that
first changes the answer substantially, so this plan starts with what the code and
the database actually say.

---

## 1. What actually happened

The AEROENTER order is still in the database. It is not a mystery:

| Field | Value |
|---|---|
| `id` | `001e526e-8725-4974-a23b-c7c5db70f5da` |
| `symbol` / `side` / `order_type` | AEROENTER / sell / limit |
| `quantity` | `500.0` |
| **`price`** | **145.80** ← what the app displayed |
| **`limit_price`** | **149.00** ← what the engine matched against |
| `execution_reference_price` | 145.00 |
| `status` | `cancelled` |
| `created_at` | 2026-08-28 03:49:12 UTC = **08:49:12 IST** (matches the screenshot) |

The executor reads the limit as `limit_price ?? price`
(`execute-pending-orders/index.ts:190`). So it compared **146.03 against 149.00**,
found the limit not reached, and correctly left the order pending. It was then
auto-cancelled after close by `expire_pending_stock_orders()` (cron `10 10 * * 1-5`).

**The matching engine was right. The screen was wrong.** The user saw ₹145.80, saw
an LTP above it, and drew an entirely reasonable conclusion from a number the UI
should never have shown as the limit.

### How the two prices diverged

`price` is an overloaded column, by design:

- While an order is **pending**, `price` holds the limit.
- On execution, the engine **overwrites** it with the fill price
  (`index.ts:457` sets `price: execPrice`).
- `limit_price` was added later to preserve the requested limit across that
  overwrite. `place-order/index.ts:131` populates both.

Then there is `modifyOrder` (`app/lib/services/supabase_service.dart:3529`), wired
to a live **Modify** button in `orders_screen.dart`:

```dart
await client
    .from('orders')
    .update({'quantity': quantity, 'price': price, 'total': total})
    .eq('id', orderId);
```

It updates `price`. It never touches `limit_price`.

So the sequence was: placed at ₹149 through `place-order` (both columns 149) →
modified to ₹145.80 through `modifyOrder` (`price` 145.80, **`limit_price` still
149**) → engine kept matching the old limit while the app kept showing the new one.

Corroborating detail: this row's `quantity` is stored as `500.0` where every other
AEROENTER row is `500` — the signature of a Dart `double` write, i.e. the client
update path rather than the edge function.

**Root cause: modifying a limit order silently leaves the engine matching the
pre-modification limit.** Every modified limit order in the app is affected.

Current blast radius is small because `limit_price` is mostly unpopulated — 2,184
of 2,188 executed limit orders have it NULL, so the executor's `?? price` fallback
has been doing the work. Six rows have the two columns disagreeing (1 pending,
4 cancelled, 1 executed). It grows as `limit_price` coverage grows, so this gets
worse with time, not better.

---

## 2. Where the source document points the wrong way

Worth stating plainly, because three of its recommendations would cost real work
and fix nothing.

**Bid/ask matching (Model B) is not implementable.** `quotes_cache` columns are
`symbol, market, price, previous_close, name, change, change_pct, day_low,
day_high, open, source, updated_at`. There is **no bid or ask anywhere in the
schema**. Model B needs a depth feed the product does not ingest, plus storage,
plus a new staleness model. The doc recommends it as "the better long-term
architecture" without knowing it would be built from scratch. Model A (LTP) is what
exists, and for this incident the model choice is irrelevant — the comparison was
against the wrong *limit*, not the wrong *market price*.

**Duplicate fills are already prevented.** `claim()` at `index.ts:300` does a
compare-and-swap — `update({status:'executing'}).eq('status','pending')` — and
skips the order when it claims nothing (`claim_lost`). Sections 7 and 18 of the doc
ask for work that is already done.

**Polling is 60 seconds, not 5–10.** `execute-pending-orders` runs `* * * * *`, as
does `refresh-quotes`. Two unsynchronised minute-crons mean a fill can be up to
~2 minutes behind the print. That is a genuine latency issue but a second-order
one, and it is already partly mitigated: the executor falls back to a **live
`market-quote` fetch** when the cache row is stale, with results memoised per
underlying (`index.ts:139–171`). That fallback was added after an earlier
investigation of this same order — the code comment at `index.ts:141` still blames
a six-hour-old cache row. **That earlier diagnosis was wrong**, and the comment
should be corrected so the next reader isn't misled the same way.

**A duplicate execution path already exists**, which the doc warns against
introducing. `supabase_service.dart:2863` runs client-side pending-order execution
and reads the limit as `row['price']` — the opposite field from the server. That is
the same divergence as the reported bug, in a second place.

---

## 3. Findings, ranked

| # | Finding | Severity |
|---|---|---|
| **F1** | `modifyOrder` writes `price` but not `limit_price`; engine matches the stale limit | **P0** — the reported bug |
| **F2** | RLS lets a user rewrite **any column** on their own orders | **P0** — integrity |
| **F3** | `price` is overloaded (limit, then fill price); the app displays it as the limit | P1 |
| **F4** | Client-side executor reads `price` as the limit, contradicting the server | P1 |
| **F5** | `orders` has no `updated_at`, so modifications are untraceable | P2 |
| **F6** | Quote refresh and execution are unsynchronised 60s crons | P2 |

### F2 is bigger than the bug that was reported

The UPDATE policy on `orders` is:

```sql
"Users can update their own orders"  USING (auth_uid() = user_id)
-- no WITH CHECK, no column restriction
```

Combined with the client writing orders directly, an authenticated user can `PATCH`
their own order rows and set **any column**, including:

- `realized_pnl` — feeds `total_realized_pnl`, the leaderboard and P&L reporting
- `quantity` on a pending sell — the plausible vector for the historic oversell bug
  that left negative-quantity holdings
- `status` — mark orders executed without any holdings or cash movement

No exploit is needed to trigger this; it is the documented API surface of the
table. The limit-direction check happens to block the obvious "fill me at a great
price" attack, but nothing blocks rewriting P&L. **This should be closed regardless
of what happens to the execution logic.**

---

## 4. Fix plan

Ordered smallest-blast-radius first. Phases 1 and 2 are independently shippable.

### Phase 1 — Stop the divergence (one function, one migration)

1. **`modifyOrder` writes both columns.** For a limit order, `limit_price` is the
   user's intent and must move with `price`:
   ```dart
   .update({'quantity': quantity, 'price': price, 'limit_price': price, 'total': total})
   ```
   Fixing it in `modifyOrder` rather than teaching the executor to prefer `price`
   is deliberate: `limit_price` is the column the executor, `place-order`, and the
   F&O re-insert path (`index.ts:368`) all already agree on. One write is a smaller
   change than three readers.

2. **Backfill the one live row.** The single divergent `pending` order should honour
   the limit the user was shown:
   ```sql
   update orders set limit_price = price
   where status = 'pending' and order_type = 'limit'
     and limit_price is distinct from price;
   ```
   Leave `cancelled` and `executed` rows alone — that is history, and for executed
   rows `price` is legitimately the fill price.

3. **Add a DB-level guard** so this cannot silently recur:
   ```sql
   alter table orders add constraint limit_price_present
     check (order_type <> 'limit' or status <> 'pending' or limit_price is not null)
     not valid;  -- not valid: don't fail on historic NULL rows
   ```

4. **Correct the misleading comment** at `execute-pending-orders/index.ts:141`. The
   live-quote fallback is worth keeping on its own merits; the AEROENTER
   justification attached to it is false and will mislead the next reader.

**Done when** modifying a pending limit order changes what the engine matches, and
a modified order fills at the modified limit.

### Phase 2 — Close the write hole (F2)

5. Replace the blanket UPDATE policy. Clients should not be able to write money
   columns at all. Either:
   - **Narrow the policy** to permit only a pending→cancelled status transition,
     and move modification into a `modify-order` edge function that validates side,
     quantity against holdings, and price sanity; or
   - **Revoke UPDATE entirely** and route both cancel and modify through edge
     functions, matching how `place-order` already works.

   The second is more work but leaves one write path instead of two. Given
   `place-order` already exists and the client insert path is a legacy fallback,
   consolidating is the direction of travel.

6. Audit whether the client-side insert path
   (`supabase_service.dart:2117`) is still reachable. It writes `price` but **not**
   `limit_price`, so every order it creates depends on the executor's `?? price`
   fallback. If `place-order` covers all cases, delete it — that removes F4's root
   cause rather than patching it.

### Phase 3 — Make the UI honest (F3)

7. Display the **limit** on a pending order and the **fill price** on an executed
   one, reading `limit_price` for the former. Right now both read `price`, which is
   exactly why a correct engine looked broken. Label them differently too: "Limit
   ₹149.00" and "Filled at ₹146.26" are different facts and should not share a
   field.

### Phase 4 — Traceability and latency (F5, F6)

8. Add `updated_at` to `orders` with a trigger. I could only *infer* the
   modification from a `500.0`-versus-`500` formatting artefact; that should not be
   how this gets diagnosed next time.

9. Log a row per non-fill decision. The executor already builds a `report` array
   with `limit_not_reached` / `stale_price` / `claim_lost` reasons — it just isn't
   persisted. Writing it to a table would have answered this ticket in one query.
   This is the doc's section 12, and it is worth doing.

10. **Order the two crons instead of rewriting the architecture.** The cheap fix for
    F6 is to have `refresh-quotes` invoke `execute-pending-orders` on completion, so
    execution always runs against a fresh cache rather than racing it. That removes
    the ~2 minute worst case without building a tick-driven matching engine.

    A true event-driven engine (the doc's sections 4–6) needs a persistent
    WebSocket consumer. `ws_health` and `tick_data` exist but `tick_data` is
    **empty**, so there is no tick stream landing in the database today. That is a
    real project, not a fix, and it should not be bundled with a correctness bug.

---

## 5. Tests worth writing

The doc's test matrix (section 17) tests the LTP comparison, which was never
broken. These test what actually failed:

| Scenario | Expected |
|---|---|
| Place sell limit @149, modify to 145.80, LTP 146.03 | **fills at 145.80** (regression test for F1) |
| Place buy limit @144.20, modify to 143.00, LTP 143.50 | stays pending |
| Modified order: `price` and `limit_price` after the write | equal |
| Client attempts `update({realized_pnl: 999999})` | **rejected** (F2) |
| Client attempts `update({quantity: <above holdings>})` on pending sell | rejected (F2) |
| Pending limit order rendered in UI | shows `limit_price`, not `price` (F3) |
| Executed order rendered in UI | shows fill price, labelled as such |
| Two concurrent executor runs, same pending order | one fill (already passing — pin it) |

The boundary cases (`LTP == limit` fills, `LTP` one paise short does not) are worth
pinning as cheap regression cover, but they are not where the bug was.

---

## 6. What not to do

- **Don't build bid/ask matching.** There is no bid/ask data. It is a data-feed
  project wearing a bug-fix costume.
- **Don't add partial fills.** `orders` has no `filled_quantity`; it needs a schema
  change and a state machine. Nothing about this incident calls for it.
- **Don't rewrite execution as event-driven yet.** Fix the wrong-limit bug and
  chain the crons first. If fills are still visibly late after that, revisit with
  measurements rather than assumption.
- **Don't touch the idempotency logic.** `claim()` works. Leave it.
- **Don't loosen the staleness guard.** It exists because production had
  `quotes_cache` rows over 1,000 hours old, and it is the reason a limit order
  cannot trigger against a price from three weeks ago.

---

## 7. Unrelated but worth flagging

Every `cron.job` command in this project embeds a **long-lived service-role JWT in
plaintext**, readable by anyone who can select from `cron.job`. That is a
credential-exposure issue independent of order execution, and it is the kind of
thing worth rotating and moving to `current_setting()` — which two of the jobs
(`sync_fo_instruments_daily`) already do correctly, so the pattern exists in the
codebase.
