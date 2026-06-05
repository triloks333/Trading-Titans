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
    const { user_id, symbol, quantity, price, action, market_type } = body; 
    // action: 'BUY' | 'SELL'
    // market_type: 'equity' | 'crypto' | 'options'

    if (!user_id || !symbol || !quantity || !price || !action) {
      return new Response(JSON.stringify({ valid: false, error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const qty = Number(quantity);
    const prc = Number(price);
    const orderValue = qty * prc;

    // Fetch user profile wallet balance
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("wallet_balance")
      .eq("id", user_id)
      .maybeSingle();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ valid: false, error: "User profile not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const balance = Number(profile.wallet_balance);

    if (action === "BUY") {
      if (balance < orderValue) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: `Insufficient balance. Required: ₹${orderValue.toFixed(2)}, Available: ₹${balance.toFixed(2)}`
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } else if (action === "SELL") {
      // Validate that user has enough holdings to sell
      if (market_type === "crypto") {
        const { data: holding } = await supabase
          .from("crypto_holdings")
          .select("quantity")
          .eq("user_id", user_id)
          .eq("symbol", symbol)
          .maybeSingle();

        const holdQty = Number(holding?.quantity ?? 0);
        if (holdQty < qty) {
          return new Response(
            JSON.stringify({
              valid: false,
              error: `Insufficient holdings. Trying to sell: ${qty}, Owned: ${holdQty}`
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } else {
        // Equity or Options
        const { data: holding } = await supabase
          .from("holdings")
          .select("quantity")
          .eq("user_id", user_id)
          .eq("symbol", symbol)
          .maybeSingle();

        const holdQty = Number(holding?.quantity ?? 0);
        // Standard paper trading allows short-selling intraday (MIS) options/stocks.
        // If NRML, check holding availability
        const productType = body.product_type ?? "NRML";
        if (productType === "NRML" && holdQty < qty) {
          return new Response(
            JSON.stringify({
              valid: false,
              error: `Insufficient holdings for NRML delivery. Owned: ${holdQty}, Requested: ${qty}`
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    }

    return new Response(JSON.stringify({ valid: true, order_value: orderValue, current_balance: balance }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
