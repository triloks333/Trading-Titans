import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

/**
 * reset-daily-pnl
 * 
 * Called at 3:30 PM IST (market close) Mon-Fri via pg_cron.
 * Responsibilities:
 *   1. Settle all MIS (intraday) positions by auto-squaring them off.
 *   2. Record a final end-of-day PnL snapshot to pnl_history.
 *   3. Reset daily_pnl fields on profiles to 0 for the next trading day.
 */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const settled: string[] = [];
    const errors: string[] = [];

    // 1. Auto-square-off MIS (intraday) equity positions
    const { data: misHoldings, error: misError } = await supabase
      .from("holdings")
      .select("*")
      .eq("product_type", "MIS");

    if (misError) throw misError;

    if (misHoldings && misHoldings.length > 0) {
      for (const holding of misHoldings) {
        try {
          // Record a SELL order for auto-square-off
          const { error: orderError } = await supabase
            .from("orders")
            .insert({
              user_id: holding.user_id,
              symbol: holding.symbol,
              quantity: holding.quantity,
              price: holding.avg_price, // Use avg_price as close price (market close)
              action: "SELL",
              status: "COMPLETED",
              order_type: "MARKET",
              product_type: "MIS",
              instrument_type: holding.instrument_type ?? "EQUITY",
              notes: "Auto square-off at market close (MIS)",
              created_at: new Date().toISOString(),
            });

          if (orderError) {
            errors.push(`Order insert failed for ${holding.symbol}: ${orderError.message}`);
            continue;
          }

          // Delete the holding
          const { error: deleteError } = await supabase
            .from("holdings")
            .delete()
            .eq("id", holding.id);

          if (deleteError) {
            errors.push(`Holding delete failed for ${holding.symbol}: ${deleteError.message}`);
          } else {
            settled.push(holding.symbol);
          }
        } catch (e) {
          errors.push(`MIS settle error for ${holding.symbol}: ${e.message}`);
        }
      }
    }

    // 2. Take final PnL snapshot for all users with equity holdings
    const { data: allHoldings, error: holdingsError } = await supabase
      .from("holdings")
      .select("user_id, symbol, quantity, avg_price");

    if (!holdingsError && allHoldings && allHoldings.length > 0) {
      // Get latest tick prices
      const symbols = Array.from(new Set(allHoldings.map(h => h.symbol)));
      const tickPrices: Record<string, number> = {};

      const { data: tickData } = await supabase
        .from("tick_data")
        .select("symbol, price")
        .in("symbol", symbols)
        .order("created_at", { ascending: false });

      if (tickData) {
        for (const tick of tickData) {
          if (!tickPrices[tick.symbol]) {
            tickPrices[tick.symbol] = Number(tick.price);
          }
        }
      }

      // Calculate per-user PnL
      const userPnL: Record<string, number> = {};
      for (const h of allHoldings) {
        const currentPrice = tickPrices[h.symbol] ?? Number(h.avg_price);
        const pnl = Number(h.quantity) * (currentPrice - Number(h.avg_price));
        userPnL[h.user_id] = (userPnL[h.user_id] ?? 0) + pnl;
      }

      // Insert end-of-day snapshots
      const snapshots = Object.entries(userPnL).map(([userId, totalPnl]) => ({
        user_id: userId,
        market: "equity",
        total_pnl: totalPnl,
        snapshot_type: "eod",
        created_at: new Date().toISOString(),
      }));

      if (snapshots.length > 0) {
        const { error: insertError } = await supabase
          .from("pnl_history")
          .insert(snapshots);
        if (insertError) {
          errors.push(`PnL snapshot insert error: ${insertError.message}`);
        }
      }
    }

    // 3. Reset daily_pnl on all profiles to 0
    const { error: resetError } = await supabase
      .from("profiles")
      .update({ daily_pnl: 0 })
      .neq("daily_pnl", 0); // Only update non-zero to reduce writes

    if (resetError) {
      errors.push(`Daily PnL reset error: ${resetError.message}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        mis_settled: settled,
        mis_settled_count: settled.length,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
