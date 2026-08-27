import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isRestingLimit, resolveFillPrice } from "./fill_price.ts";

// The bug this guards against, with the real production numbers:
// order 01743bdc, SELL 250 VEDL limit 281, reference price 275.85 at placement,
// triggered on the 04:33 cron tick when the cached spot read 281.4. It was booked
// at 281.4. VEDL's day range was 273.25-284.45, so it traded straight through 281
// rather than gapping over it, and the fill should have been 281.00.
Deno.test("a resting sell limit fills at its limit, not at the polled price", () => {
  assertEquals(resolveFillPrice("sell", "limit", 281, 281.4, 275.85), 281);
  assertEquals(isRestingLimit("sell", "limit", 281, 275.85), true);
});

Deno.test("a resting buy limit fills at its limit, not at the polled price", () => {
  // Mirror case: buy limit 100 placed while the market was at 108, triggers when
  // the poll reads 99.5. Filling at 99.5 would hand out a phantom discount.
  assertEquals(resolveFillPrice("buy", "limit", 100, 99.5, 108), 100);
  assertEquals(isRestingLimit("buy", "limit", 100, 108), true);
});

Deno.test("a marketable limit keeps its genuine price improvement", () => {
  // Sell limit 281 placed when the market was ALREADY at 282: the order crosses
  // the spread immediately, so 282 is real improvement and must be preserved.
  assertEquals(resolveFillPrice("sell", "limit", 281, 282, 282), 282);
  assertEquals(isRestingLimit("sell", "limit", 281, 282), false);
  // Buy limit 100 placed when the market was already at 95.
  assertEquals(resolveFillPrice("buy", "limit", 100, 95, 95), 95);
  assertEquals(isRestingLimit("buy", "limit", 100, 95), false);
});

Deno.test("an unusable reference price is treated as resting", () => {
  // place-order stamps execution_reference_price = the limit itself when the
  // pre-trade quote fetch fails, so ref == limit means "unknown", not
  // "marketable". Older rows may have null or 0. All must fill at the limit;
  // if any of these leaked through to `polled` the original bug would survive
  // for exactly the orders with the least trustworthy data.
  for (const ref of [null, 0, -5, Number.NaN]) {
    assertEquals(resolveFillPrice("sell", "limit", 281, 281.4, ref), 281);
    assertEquals(resolveFillPrice("buy", "limit", 100, 99.5, ref), 100);
  }
  assertEquals(resolveFillPrice("sell", "limit", 281, 281.4, 281), 281);
  assertEquals(resolveFillPrice("buy", "limit", 100, 99.5, 100), 100);
});

Deno.test("market orders always fill at the polled price", () => {
  assertEquals(resolveFillPrice("sell", "market", 281, 281.4, 275.85), 281.4);
  assertEquals(resolveFillPrice("buy", "market", 100, 99.5, 108), 99.5);
  assertEquals(isRestingLimit("sell", "market", 281, 275.85), false);
});

Deno.test("the resting fill is never worse for the user than the trigger", () => {
  // The engine only calls this after the trigger passed (sell: polled >= limit,
  // buy: polled <= limit). Property check: clamping to the limit must move the
  // price against the user by no more than the overshoot, and must never move it
  // in the user's favour beyond the limit. Catches a flipped comparison.
  for (let i = 0; i < 500; i++) {
    const limit = 50 + Math.random() * 500;
    const overshoot = Math.random() * 5;

    const sellPolled = limit + overshoot; // trigger satisfied for a sell
    const sellFill = resolveFillPrice("sell", "limit", limit, sellPolled, limit - 10);
    assertEquals(sellFill, limit);
    if (sellFill > sellPolled) throw new Error("resting sell filled above the market");

    const buyPolled = limit - overshoot; // trigger satisfied for a buy
    const buyFill = resolveFillPrice("buy", "limit", limit, buyPolled, limit + 10);
    assertEquals(buyFill, limit);
    if (buyFill < buyPolled) throw new Error("resting buy filled below the market");
  }
});
