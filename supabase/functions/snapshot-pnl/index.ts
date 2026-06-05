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

    const body = await req.json().catch(() => ({}));
    const market = body.market === "crypto" ? "crypto" : "equity";

    if (market === "equity") {
      // 1. Fetch all equity holdings
      const { data: holdings, error: holdingsError } = await supabase
        .from("holdings")
        .select("user_id, symbol, quantity, avg_price");

      if (holdingsError) throw holdingsError;

      if (holdings && holdings.length > 0) {
        // Get unique symbols to fetch current prices
        const symbols = Array.from(new Set(holdings.map(h => h.symbol)));
        
        // Fetch latest tick prices
        const { data: ticks, error: ticksError } = await supabase
          .rpc("get_latest_ticks", { symbols_arr: symbols }); 
          // Note: If rpc doesn't exist, we can fetch latest from tick_data table directly.
          // Let's query from tick_data directly to be safe.
        
        let tickPrices: Record<string, number> = {};
        
        // Direct table query for simplicity and reliability
        const { data: tickData, error: tickDataError } = await supabase
          .from("tick_data")
          .select("symbol, price, created_at")
          .in("symbol", symbols)
          .order("created_at", { ascending: false });

        if (!tickDataError && tickData) {
          // Keep only the latest tick per symbol
          for (const tick of tickData) {
            if (!tickPrices[tick.symbol]) {
              tickPrices[tick.symbol] = Number(tick.price);
            }
          }
        }

        // Group holdings by user
        const userPnL: Record<string, number> = {};
        for (const h of holdings) {
          const currentPrice = tickPrices[h.symbol] ?? Number(h.avg_price);
          const pnl = Number(h.quantity) * (currentPrice - Number(h.avg_price));
          userPnL[h.user_id] = (userPnL[h.user_id] ?? 0) + pnl;
        }

        // Write P&L snapshots to history
        const snapshots = Object.entries(userPnL).map(([userId, totalPnl]) => ({
          user_id: userId,
          market: "equity",
          total_pnl: totalPnl,
          created_at: new Date().toISOString()
        }));

        if (snapshots.length > 0) {
          const { error: insertError } = await supabase
            .from("pnl_history")
            .insert(snapshots);
          if (insertError) throw insertError;
        }
      }
    } else {
      // 2. Fetch all crypto holdings
      const { data: cryptoHoldings, error: cryptoError } = await supabase
        .from("crypto_holdings")
        .select("user_id, symbol, quantity, avg_price");

      if (cryptoError) throw cryptoError;

      if (cryptoHoldings && cryptoHoldings.length > 0) {
        const symbols = Array.from(new Set(cryptoHoldings.map(h => h.symbol)));
        
        // Fetch latest crypto prices
        let cryptoPrices: Record<string, number> = {};
        const { data: priceData, error: priceDataError } = await supabase
          .from("crypto_prices")
          .select("symbol, price")
          .in("symbol", symbols)
          .order("created_at", { ascending: false });

        if (!priceDataError && priceData) {
          for (const p of priceData) {
            if (!cryptoPrices[p.symbol]) {
              cryptoPrices[p.symbol] = Number(p.price);
            }
          }
        }

        // Group holdings by user
        const userPnL: Record<string, number> = {};
        for (const h of cryptoHoldings) {
          const currentPrice = cryptoPrices[h.symbol] ?? Number(h.avg_price);
          const pnl = Number(h.quantity) * (currentPrice - Number(h.avg_price));
          userPnL[h.user_id] = (userPnL[h.user_id] ?? 0) + pnl;
        }

        // Write P&L snapshots to history
        const snapshots = Object.entries(userPnL).map(([userId, totalPnl]) => ({
          user_id: userId,
          market: "crypto",
          total_pnl: totalPnl,
          created_at: new Date().toISOString()
        }));

        if (snapshots.length > 0) {
          const { error: insertError } = await supabase
            .from("pnl_history")
            .insert(snapshots);
          if (insertError) throw insertError;
        }
      }
    }

    return new Response(JSON.stringify({ success: true, market }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
