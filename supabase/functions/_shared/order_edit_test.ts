import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { authoriseEdit, type EditableOrder, resolveEdit } from "./order_edit.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

function order(overrides: Partial<EditableOrder> = {}): EditableOrder {
  return {
    id: "order-1",
    user_id: OWNER,
    status: "pending",
    order_type: "limit",
    side: "sell",
    quantity: 500,
    price: 145.80,
    is_exit: false,
    instrument_type: "EQUITY",
    ...overrides,
  };
}

function denied<T>(d: { ok: boolean; status?: number; error?: string } | { ok: true; value: T }) {
  if (d.ok) throw new Error("expected the edit to be refused");
  return d as { ok: false; status: number; error: string };
}

function allowed<T>(d: { ok: false } | { ok: true; value: T }) {
  if (!d.ok) throw new Error(`expected the edit to be allowed, got: ${JSON.stringify(d)}`);
  return d.value;
}

// ── authorisation ──────────────────────────────────────────────────────────

Deno.test("a missing order is not found", () => {
  assertEquals(denied(authoriseEdit(null, OWNER)).status, 404);
});

Deno.test("another user's order reports not found, never forbidden", () => {
  // 403 would confirm the id exists and make this a probe for other people's
  // order ids, so the status code itself is part of the fix.
  const d = denied(authoriseEdit(order(), OTHER));
  assertEquals(d.status, 404);
  assertEquals(d.error, "Order not found.");
});

Deno.test("an executed order cannot be edited", () => {
  const d = denied(authoriseEdit(order({ status: "executed" }), OWNER));
  assertEquals(d.status, 409);
  assertEquals(d.error, "That order has already been filled.");
});

Deno.test("a cancelled order cannot be edited", () => {
  assertEquals(denied(authoriseEdit(order({ status: "cancelled" }), OWNER)).status, 409);
});

Deno.test("an order mid-fill cannot be edited", () => {
  // `executing` is the claim/CAS state. Editing it would race the engine.
  assertEquals(denied(authoriseEdit(order({ status: "executing" }), OWNER)).status, 409);
});

Deno.test("the owner may edit their own pending order", () => {
  assertEquals(allowed(authoriseEdit(order(), OWNER)).id, "order-1");
});

// ── validation ─────────────────────────────────────────────────────────────

Deno.test("modifying a pending SELL limit keeps price and limit_price in step", () => {
  const r = allowed(resolveEdit(order({ side: "sell" }), { price: 149 }, 0));
  assertEquals(r.price, 149);
  assertEquals(r.limitPrice, 149);
  assertEquals(r.total, 500 * 149);
});

Deno.test("modifying a pending BUY limit keeps price and limit_price in step", () => {
  const r = allowed(resolveEdit(order({ side: "buy" }), { price: 143.20, quantity: 100 }, 0));
  assertEquals(r.price, 143.20);
  assertEquals(r.limitPrice, 143.20);
  assertEquals(r.quantity, 100);
  assertEquals(r.total, 100 * 143.20);
});

Deno.test("a market order never receives a limit_price", () => {
  const r = allowed(resolveEdit(order({ order_type: "market" }), { quantity: 25 }, 0));
  assertEquals(r.limitPrice, null);
});

Deno.test("a market order refuses a price change", () => {
  const d = denied(resolveEdit(order({ order_type: "market" }), { price: 200 }, 0));
  assertEquals(d.status, 400);
});

Deno.test("quantity must be positive and finite", () => {
  for (const q of [0, -5, Number.NaN, Number.POSITIVE_INFINITY]) {
    assertEquals(denied(resolveEdit(order(), { quantity: q }, 0)).status, 400);
  }
});

Deno.test("price must be positive and finite", () => {
  for (const p of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    assertEquals(denied(resolveEdit(order(), { price: p }, 0)).status, 400);
  }
});

Deno.test("an empty edit is refused rather than written", () => {
  assertEquals(denied(resolveEdit(order(), {}, 0)).status, 400);
});

Deno.test("total is recomputed from the new quantity", () => {
  // The web client's old direct PATCH changed quantity and left `total` stale.
  const r = allowed(resolveEdit(order({ quantity: 500, price: 100 }), { quantity: 10 }, 0));
  assertEquals(r.total, 1000);
});

// ── the exit clamp ─────────────────────────────────────────────────────────

Deno.test("an exit sell cannot exceed the position held", () => {
  const d = denied(resolveEdit(order({ is_exit: true }), { quantity: 600 }, 500));
  assertEquals(d.status, 400);
});

Deno.test("an exit sell may close the whole position", () => {
  assertEquals(allowed(resolveEdit(order({ is_exit: true }), { quantity: 500 }, 500)).quantity, 500);
});

Deno.test("an exit sell against no position is refused", () => {
  assertEquals(denied(resolveEdit(order({ is_exit: true }), { quantity: 1 }, 0)).status, 400);
});

Deno.test("a short position is exitable by its absolute size", () => {
  // holdings.quantity is negative for a short; the exit is a BUY, but the same
  // absolute cap applies when the row is flagged is_exit.
  assertEquals(allowed(resolveEdit(order({ is_exit: true }), { quantity: 300 }, -300)).quantity, 300);
});

Deno.test("a plain sell above holdings is allowed: that is a short, not an oversell", () => {
  // Capping every sell at holdings would silently remove short selling, which
  // the engine supports via EQ_SHORT_NEW and margin-checks at fill.
  const r = allowed(resolveEdit(order({ is_exit: false }), { quantity: 10_000 }, 0));
  assertEquals(r.quantity, 10_000);
});
