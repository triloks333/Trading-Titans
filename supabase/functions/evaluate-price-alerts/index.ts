import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON = Deno.env.get("SUPABASE_ANON_KEY");

function json(body, status = 200) { return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }); }

// Shared session window: the old inline copy closed at 15:15, so price alerts
// stopped firing 15 minutes before the exchange closed.
import { isStockOpen as isMarketOpen } from "../_shared/market_hours.ts";

// NOTE: FCM push is handled centrally by the notifications AFTER INSERT trigger
// (-> push-notification fn). This function only inserts the notification row.
serve(async (req) => {
  try {
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";
    if (!isMarketOpen() && !force) return json({ skipped: "market_closed", checked: 0, triggered: 0 });

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: alerts, error } = await supabase.from("price_alerts").select("*").eq("status", "active");
    if (error) return json({ error: error.message }, 500);
    if (!alerts || alerts.length === 0) return json({ checked: 0, triggered: 0 });

    const uniq = new Map();
    for (const a of alerts) uniq.set(a.symbol + "\u001f" + a.market, { symbol: a.symbol, market: a.market });

    const prices = new Map();
    await Promise.all([...uniq.entries()].map(async ([key, v]) => {
      try {
        const qurl = SUPABASE_URL + "/functions/v1/market-quote?symbol=" + encodeURIComponent(v.symbol) + "&market=" + encodeURIComponent(v.market);
        const r = await fetch(qurl, { headers: { Authorization: "Bearer " + ANON, apikey: ANON } });
        if (r.ok) { const q = await r.json(); if (q && typeof q.price === "number" && q.price > 0) prices.set(key, q.price); }
      } catch (_) {}
    }));

    let triggered = 0;
    for (const a of alerts) {
      const price = prices.get(a.symbol + "\u001f" + a.market);
      if (price == null) continue;
      const target = Number(a.target_price);
      const crossed = a.direction === "above" ? price >= target : price <= target;
      if (!crossed) continue;

      const { data: claim } = await supabase.from("price_alerts").update({ status: "triggered", triggered_at: new Date().toISOString() }).eq("id", a.id).eq("status", "active").select();
      if (!claim || claim.length === 0) continue;

      const disp = a.name && a.name.length > 0 ? a.name : String(a.symbol).replace("NSE:", "");
      const title = "Price Alert: " + disp;
      const body = disp + " is now \u20b9" + price.toFixed(2) + " (" + a.direction + " your target of \u20b9" + target.toFixed(2) + ").";

      await supabase.from("notifications").insert({ user_id: a.user_id, title, body, is_read: false, action_type: "price_alert", action_data: { symbol: a.symbol, market: a.market } });
      triggered++;
    }

    return json({ checked: alerts.length, triggered });
  } catch (e) { return json({ error: e instanceof Error ? e.message : String(e) }, 500); }
});
