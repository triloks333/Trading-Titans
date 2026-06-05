import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Call CoinDCX markets_details or exchange ticker
    const detailsRes = await fetch("https://api.coindcx.com/exchange/v1/markets_details");
    
    let coins = [];
    if (detailsRes.ok) {
      const details = await detailsRes.json();
      if (Array.isArray(details)) {
        // Filter only INR markets and map them
        coins = details
          .filter((d: any) => d.target_currency_short_name === "INR" && d.active === true)
          .map((d: any) => ({
            symbol: d.coindcx_name, // e.g. BTCINR
            base_currency: d.base_currency_short_name, // e.g. BTC
            quote_currency: d.target_currency_short_name, // e.g. INR
            min_quantity: Number(d.min_quantity) || 0.00001,
            max_quantity: Number(d.max_quantity) || 10000,
            min_price: Number(d.min_price) || 0.01,
            step: Number(d.min_quantity_step) || 0.00001,
            order_types: d.order_types || ["market", "limit"],
            created_at: new Date().toISOString()
          }));
      }
    }

    // Fallback if details API is empty or failed
    if (coins.length === 0) {
      const tickerRes = await fetch("https://api.coindcx.com/exchange/ticker");
      if (!tickerRes.ok) throw new Error("Failed to fetch CoinDCX exchange ticker");
      const tickers = await tickerRes.json();
      if (Array.isArray(tickers)) {
        coins = tickers
          .filter((t: any) => t.market.endsWith("INR"))
          .map((t: any) => {
            const market = t.market;
            const base = market.substring(0, market.length - 3);
            return {
              symbol: market,
              base_currency: base,
              quote_currency: "INR",
              min_quantity: 0.00001,
              max_quantity: 100000,
              min_price: 0.01,
              step: 0.00001,
              order_types: ["market", "limit"],
              created_at: new Date().toISOString()
            };
          });
      }
    }

    if (coins.length > 0) {
      console.log(`Syncing ${coins.length} CoinDCX crypto coins...`);
      // Upsert to DB in chunks of 500
      const batchSize = 500;
      for (let i = 0; i < coins.length; i += batchSize) {
        const batch = coins.slice(i, i + batchSize);
        const { error } = await supabase.from("crypto_coins").upsert(batch);
        if (error) throw error;
      }
    }

    return new Response(JSON.stringify({ success: true, count: coins.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
