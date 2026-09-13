# TradingTitans — Order Execution Issue & Backend Fix Specification

## Context

TradingTitans is a paper-trading application. A user created a SELL limit order and noticed that the order remained `PENDING` even though the displayed LTP was above the order price.

The screenshot showed:

- Symbol: `AEROENTER`
- Side: `SELL`
- Quantity: `500`
- Limit/order price: `₹145.80`
- Displayed LTP: `₹146.03`
- Order status: `PENDING`
- Order creation time shown: `08:49:12`

The user expected the order to execute because:

```text
₹146.03 > ₹145.80
```

This document describes the issue, the two possible execution models, and the recommended backend architecture/fixes.

---

# 1. Core Problem

There are potentially TWO separate problems:

1. **Incorrect execution condition**
   - The backend may be using LTP alone to decide whether a limit order is executable.
2. **Backend processing latency**
   - Even if the execution condition is correct, the order may not be evaluated immediately when a new market-price tick arrives.

The implementation should address both.

---

# 2. Important Trading Rule

LTP means **Last Traded Price**. It represents the price of the most recent completed trade.

LTP does NOT necessarily mean that there is currently a buyer/seller available at that price.

For a realistic order-book-based simulator:

### SELL LIMIT

A sell limit order should execute when there is sufficient buying interest at or above the user's limit price.

Conceptually:

```pseudo
if order.side == SELL:
    if bestBid >= order.limitPrice:
        execute(order)
```

### BUY LIMIT

A buy limit order should execute when there is sufficient selling interest at or below the user's limit price.

```pseudo
if order.side == BUY:
    if bestAsk <= order.limitPrice:
        execute(order)
```

Therefore:

```text
SELL @ ₹145.80
LTP = ₹146.03
Best Bid = ₹145.50
```

The SELL limit order should remain pending in a realistic order-book simulation, because the current executable bid is below ₹145.80.

However:

```text
SELL @ ₹145.80
LTP = ₹146.03
Best Bid = ₹146.03
```

The SELL order can execute.

---

# 3. Alternative Simple Simulator Model

TradingTitans may intentionally choose a simplified paper-trading model where LTP is the execution trigger.

If that is the product decision, then:

### SELL LIMIT

```pseudo
if order.side == SELL:
    if LTP >= order.limitPrice:
        execute(order)
```

### BUY LIMIT

```pseudo
if order.side == BUY:
    if LTP <= order.limitPrice:
        execute(order)
```

Under this model, the screenshot is definitely an execution problem:

```text
LTP = ₹146.03
SELL limit = ₹145.80

146.03 >= 145.80
=> TRUE
=> order should execute
```

If the order remains `PENDING`, investigate the market-data processing and pending-order evaluation pipeline.

---

# 4. Recommended Approach for TradingTitans

Use a small virtual matching engine rather than relying on periodic database polling.

Recommended architecture:

```text
LIVE MARKET DATA
       |
       v
MARKET PRICE / ORDER-BOOK UPDATE
       |
       v
ORDER MATCHING ENGINE
       |
       +----> Find executable pending orders
       |
       +----> Execute / partially execute
       |
       v
UPDATE ORDER
       |
       v
UPDATE HOLDINGS / CASH / P&L
       |
       v
WEBSOCKET / REALTIME EVENT
       |
       v
MOBILE APP
```

Avoid an architecture like:

```text
Market API
    |
    v
Database
    |
    v
Cron job every 5–10 seconds
    |
    v
Check pending orders
```

Periodic polling can create noticeable execution delays and race conditions.

---

# 5. Event-Driven Execution

Whenever a new market-data tick arrives, immediately evaluate relevant pending orders.

Conceptually:

```pseudo
onMarketTick(symbol, marketData):

    pendingOrders = getPendingOrdersForSymbol(symbol)

    for order in pendingOrders:

        if order.side == SELL:
            if marketData.bestBid >= order.limitPrice:
                executeOrder(order, marketData.bestBid)

        if order.side == BUY:
            if marketData.bestAsk <= order.limitPrice:
                executeOrder(order, marketData.bestAsk)
```

If TradingTitans uses the simplified LTP model:

```pseudo
onMarketTick(symbol, marketData):

    pendingOrders = getPendingOrdersForSymbol(symbol)

    for order in pendingOrders:

        if order.side == SELL:
            if marketData.ltp >= order.limitPrice:
                executeOrder(order, marketData.ltp)

        if order.side == BUY:
            if marketData.ltp <= order.limitPrice:
                executeOrder(order, marketData.ltp)
```

---

# 6. Do NOT Process Orders Only on a Fixed Timer

Avoid:

```pseudo
every 10 seconds:
    checkPendingOrders()
```

This can cause:

- delayed execution
- stale prices
- orders executing late
- users seeing price crossed but order still pending
- inconsistent P&L
- difficult-to-debug race conditions

Prefer:

```pseudo
marketTickReceived
    -> matching engine
    -> order execution
```

A periodic reconciliation job can still exist as a safety mechanism, but it should NOT be the primary execution path.

---

# 7. Idempotent Order Execution

The execution function must be safe against duplicate market events or concurrent workers.

Before executing:

```pseudo
BEGIN TRANSACTION

order = SELECT ... FOR UPDATE

if order.status != "PENDING":
    return

if executionConditionIsMet(order, marketData):
    execute order
    update holdings
    update cash
    update P&L
    create execution record

COMMIT
```

The important rule is:

```text
Only PENDING orders may transition to EXECUTED/PARTIALLY_FILLED.
```

This prevents the same order from being executed twice.

---

# 8. Suggested Order State Machine

Use explicit order states.

```text
PENDING
   |
   +----> PARTIALLY_FILLED
   |           |
   |           +----> FILLED
   |
   +----> CANCELLED
   |
   +----> EXPIRED   (if supported)
```

For a fully filled order:

```text
PENDING -> FILLED
```

Do not use ambiguous status changes.

---

# 9. Partial Fills

If TradingTitans supports a virtual order book, consider partial fills.

Example:

```text
User SELL:
500 shares @ ₹145.80

Available bid:
200 shares @ ₹146.00
```

Result:

```text
200 shares -> FILLED
300 shares -> remain pending
```

Order state:

```text
PARTIALLY_FILLED
```

If the simulator does not support an order book, partial fills can be omitted and the entire order can execute according to the selected simplified model.

---

# 10. Execution Price

If using an order-book model, do not automatically assume:

```text
executionPrice = LTP
```

For a SELL, use the executable bid price according to the simulator's matching rules.

For example:

```pseudo
SELL:
executionPrice = bestBid

BUY:
executionPrice = bestAsk
```

If using the simplified LTP model:

```pseudo
executionPrice = LTP
```

The execution model should be consistent throughout the application.

---

# 11. Screenshot-Specific Diagnosis

For the screenshot:

```text
SELL
Quantity: 500
Limit Price: ₹145.80
LTP: ₹146.03
Status: PENDING
```

If TradingTitans intentionally uses LTP-triggered execution:

```text
146.03 >= 145.80
```

is true.

Therefore the order should have executed.

Investigate:

1. Whether the backend received the latest market-price tick.
2. Whether the order existed in the pending-order query at that moment.
3. Whether the symbol mapping matched exactly.
4. Whether the order side was correctly interpreted as `SELL`.
5. Whether the comparison uses the correct numeric values.
6. Whether prices are being compared as numbers rather than strings.
7. Whether the pending-order worker has excessive polling latency.
8. Whether a transaction/lock prevented execution.
9. Whether the order was rejected by another validation.
10. Whether the mobile app is displaying a stale order status.
11. Whether the execution happened in the backend but the realtime update failed.
12. Whether there is a timezone/timestamp issue.
13. Whether the price source has delayed/stale data.
14. Whether multiple workers are processing the same symbol/order.

---

# 12. Add Execution Audit Logging

This is strongly recommended.

Every execution evaluation should be traceable.

Store/log:

```text
orderId
symbol
side
orderType
orderPrice
orderQuantity

ltp
bestBid
bestAsk

orderCreatedAt
marketTickAt
matchingStartedAt
matchingCompletedAt

executionPrice
executionQuantity

previousOrderStatus
newOrderStatus

reason
```

For a non-executable order, log something like:

```text
Order: ABC123
Side: SELL
Limit: 145.80
LTP: 146.03
BestBid: 145.50
Result: NOT_EXECUTABLE
Reason: BEST_BID_BELOW_SELL_LIMIT
```

For an executable order:

```text
Order: ABC123
Side: SELL
Limit: 145.80
LTP: 146.03
BestBid: 146.03
Result: EXECUTED
ExecutionPrice: 146.03
```

This will make future debugging significantly easier.

---

# 13. Numeric Precision

Do NOT rely on floating-point comparisons for financial values if avoidable.

Bad:

```javascript
if (ltp >= orderPrice)
```

when both are arbitrary floating-point values.

Prefer integer price units, e.g.:

```text
₹145.80 -> 14580 paise
₹146.03 -> 14603 paise
```

Then:

```pseudo
if bestBidPaise >= orderPricePaise:
    execute()
```

Or use a proper decimal type/library supported by the backend stack.

This avoids floating-point edge cases.

---

# 14. Holdings / Cash / P&L

A pending SELL order must NOT be treated as an executed sale.

Correct flow:

```text
SELL ORDER CREATED
        |
        v
500 shares remain in holdings
        |
        v
ORDER = PENDING
        |
        v
Executable market condition
        |
        v
MATCHING ENGINE
        |
        v
SELL EXECUTED
        |
        +--> remove 500 shares from holdings
        |
        +--> increase available cash
        |
        +--> calculate realized P&L
        |
        +--> create execution/trade record
```

Do not increase cash or remove holdings before the order is actually filled.

---

# 15. P&L Sanity Check From Screenshot

The screenshot showed approximately:

```text
Deployed Capital: ₹71,650
Current Value:    ₹73,015
Total P&L:        +₹1,365
```

Calculation:

```text
₹73,015 - ₹71,650 = ₹1,365
```

That arithmetic is correct.

The SELL order:

```text
500 × ₹145.80 = ₹72,900
```

represents a large portion of the displayed portfolio value.

Make sure a PENDING SELL does not accidentally affect completed-trade calculations.

---

# 16. Realtime App Update

After the backend executes an order, immediately publish an order-status event.

Example:

```json
{
  "event": "ORDER_EXECUTED",
  "orderId": "ABC123",
  "symbol": "AEROENTER",
  "status": "FILLED",
  "quantity": 500,
  "executionPrice": 146.03,
  "executedAt": "2026-08-31T08:49:13Z"
}
```

The mobile app should consume this event over WebSocket/realtime infrastructure and update:

- Order status
- Holdings
- Available cash
- Portfolio value
- P&L
- Trade history

Do not make the UI wait for a slow polling cycle if realtime infrastructure is available.

---

# 17. Recommended Testing Matrix

Create automated tests for at least these scenarios.

### SELL LIMIT

```text
SELL @ 145.80
LTP = 145.79
=> PENDING
```

```text
SELL @ 145.80
LTP = 145.80
=> EXECUTE (if using LTP model)
```

```text
SELL @ 145.80
LTP = 146.03
=> EXECUTE (if using LTP model)
```

### Order-book model

```text
SELL @ 145.80
BestBid = 145.79
=> PENDING
```

```text
SELL @ 145.80
BestBid = 145.80
=> EXECUTE
```

```text
SELL @ 145.80
BestBid = 146.03
=> EXECUTE
```

### BUY LIMIT

```text
BUY @ 145.80
LTP = 145.81
=> PENDING (LTP model)
```

```text
BUY @ 145.80
LTP = 145.80
=> EXECUTE
```

```text
BUY @ 145.80
LTP = 145.79
=> EXECUTE
```

For an order-book model, test against `bestAsk`.

---

# 18. Race Condition Test

Simulate multiple market ticks arriving simultaneously:

```text
Tick 1 -> LTP 146.00
Tick 2 -> LTP 146.03
Tick 3 -> LTP 146.05
```

The same order must only execute once.

Expected:

```text
PENDING
   ↓
FILLED
```

Never:

```text
FILLED
FILLED
FILLED
```

and never deduct the holdings/cash multiple times.

---

# 19. Backend Performance Target

For a paper-trading application, aim for:

```text
Market tick received
       ↓
Matching decision
       ↓
Database update
       ↓
Realtime notification
```

within a small, predictable latency budget.

The important thing is not merely making the polling interval shorter. The correct architecture is **event-driven execution triggered by market-data updates**.

---

# 20. Implementation Checklist

Use this checklist while modifying the codebase:

- [ ] Find current pending-order execution logic.
- [ ] Find where LTP is received/updated.
- [ ] Find whether execution is timer/cron based.
- [ ] Determine whether TradingTitans intentionally uses LTP or bid/ask execution.
- [ ] If using realistic matching, implement SELL against `bestBid`.
- [ ] Implement BUY against `bestAsk`.
- [ ] If using simplified LTP execution, ensure SELL uses `LTP >= limit`.
- [ ] Ensure BUY uses `LTP <= limit`.
- [ ] Trigger matching immediately after market-price updates.
- [ ] Remove unnecessary 5–10 second execution polling dependency.
- [ ] Keep a reconciliation worker as a fallback only.
- [ ] Make execution transactional/idempotent.
- [ ] Prevent duplicate fills.
- [ ] Handle partial fills if order-book simulation supports them.
- [ ] Use decimal/integer price representation.
- [ ] Update holdings only after execution.
- [ ] Update cash only after execution.
- [ ] Update realized P&L only after execution.
- [ ] Create trade/execution records.
- [ ] Emit realtime order-status events.
- [ ] Verify the mobile app receives those events.
- [ ] Add detailed execution audit logs.
- [ ] Add automated tests for price-crossing cases.
- [ ] Add concurrency/race-condition tests.
- [ ] Test with the AEROENTER scenario from the screenshot.

---

# 21. Important Product Decision

Before changing the code, decide which model TradingTitans wants.

## Model A — Beginner-friendly simulator

```text
SELL LIMIT -> execute when LTP >= limit
BUY LIMIT  -> execute when LTP <= limit
```

Pros:
- Simple
- Easy to understand
- Easy to implement
- Works even without a full virtual order book

Cons:
- Not a realistic representation of bid/ask execution

## Model B — Realistic paper-trading simulator (recommended)

```text
SELL LIMIT -> execute against Best Bid
BUY LIMIT  -> execute against Best Ask
```

Pros:
- Much closer to real trading
- More realistic execution behavior
- Allows proper spread simulation
- Can eventually support partial fills/order-book depth

Cons:
- Requires bid/ask market data
- More backend complexity

For TradingTitans, Model B is the better long-term architecture if the goal is to teach users how markets actually work.

---

# 22. Immediate Fix If You Want the Smallest Change

If the current product intentionally uses LTP as its execution trigger, inspect the code for something equivalent to:

```pseudo
if order.side == SELL:
    if ltp > order.price:
        execute(order)
```

and make sure:

```pseudo
if order.side == SELL:
    if ltp >= order.price:
        execute(order)
```

and:

```pseudo
if order.side == BUY:
    if ltp <= order.price:
        execute(order)
```

Then make sure this check runs whenever a new LTP tick arrives rather than only on a slow timer.

For the screenshot:

```text
LTP:          146.03
SELL LIMIT:   145.80

146.03 >= 145.80
```

Therefore, under the LTP model, the order must transition from:

```text
PENDING -> FILLED
```

---

# Final Instruction for the IDE

Inspect the existing TradingTitans backend before making changes. Do not blindly replace the current order system.

First identify:

1. Market-data ingestion
2. LTP/bid/ask storage
3. Pending-order retrieval
4. Order matching/execution function
5. Order database schema
6. Holdings update logic
7. Cash/P&L update logic
8. Realtime/WebSocket event system
9. Any cron/interval/queue responsible for order execution

Then implement the smallest safe architectural change that fixes execution latency and incorrect limit-order matching while preserving existing APIs, database contracts, authentication, portfolio calculations, and frontend behavior.

Do not introduce duplicate order execution paths.

Add automated tests for the execution conditions and concurrency behavior before considering the fix complete.
