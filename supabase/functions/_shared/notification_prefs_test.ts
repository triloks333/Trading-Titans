import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { prefKeyFor } from "./notification_prefs.ts";

Deno.test("each Settings switch covers its action types", () => {
  assertEquals(prefKeyFor("price_alert"), "price");
  for (const t of ["order", "order_executed", "order_pending", "order_failed", "trade", "expiry", "risk_alert"]) {
    assertEquals(prefKeyFor(t), "orders", t);
  }
  assertEquals(prefKeyFor("reward"), "league");
  assertEquals(prefKeyFor("league"), "league");
  assertEquals(prefKeyFor("news"), "news");
});

Deno.test("chat, account and broadcast messages are never switched off here", () => {
  for (const t of ["chat", "wallet", "custom", "broadcast", null, undefined]) {
    assertEquals(prefKeyFor(t), null, String(t));
  }
});
