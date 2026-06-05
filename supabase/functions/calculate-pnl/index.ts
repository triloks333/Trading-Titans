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

    // Get user from auth header if present
    const authHeader = req.headers.get("Authorization");
    let userId = "";
    
    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const { data: { user }, error: authError } = await supabase.auth.getUser(token);
      if (!authError && user) {
        userId = user.id;
      }
    }

    // Check query params / body for user_id if calling with service role
    if (!userId) {
      const body = await req.json().catch(() => ({}));
      userId = body.user_id ?? "";
    }

    if (!userId) {
      return new Response(JSON.stringify({ error: "Missing user identification" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Fetch Equity holdings
    const { data: holdings, error: holdingsError } = await supabase
      .from("holdings")
      .select("*")
      .eq("user_id", userId);

    if (holdingsError) throw holdingsError;

    // Fetch Crypto holdings
    const { data: cryptoHoldings, error: cryptoError } = await supabase
      .from("crypto_holdings")
      .select("*")
      .eq("user_id", userId);

    if (cryptoError) throw cryptoError;

    const equitySymbols = holdings ? holdings.map(h => h.symbol) : [];
    const cryptoSymbols = cryptoHoldings ? cryptoHoldings.map(h => h.symbol) : [];

    // Fetch latest equity ticks
    let tickPrices: Record<string, number> = {};
    if (equitySymbols.length > 0) {
      const { data: tickData } = await supabase
        .from("tick_data")
        .select("symbol, price")
        .in("symbol", equitySymbols)
        .order("created_at", { ascending: false });

      if (tickData) {
        for (const tick of tickData) {
          if (!tickPrices[tick.symbol]) {
            tickPrices[tick.symbol] = Number(tick.price);
          }
        }
      }
    }

    // Fetch latest crypto prices
    let cryptoPrices: Record<string, number> = {};
    if (cryptoSymbols.length > 0) {
      const { data: priceData } = await supabase
        .from("crypto_prices")
        .select("symbol, price")
        .in("symbol", cryptoSymbols)
        .order("created_at", { ascending: false });

      if (priceData) {
        for (const p of priceData) {
          if (!cryptoPrices[p.symbol]) {
            cryptoPrices[p.symbol] = Number(p.price);
          }
        }
      }
    }

    // Format results
    const holdingsResults = (holdings ?? []).map(h => {
      const ltp = tickPrices[h.symbol] ?? Number(h.avg_price);
      const pnl = Number(h.quantity) * (ltp - Number(h.avg_price));
      return { ...h, ltp, pnl };
    });

    const cryptoResults = (cryptoHoldings ?? []).map(h => {
      const ltp = cryptoPrices[h.symbol] ?? Number(h.avg_price);
      const pnl = Number(h.quantity) * (ltp - Number(h.avg_price));
      return { ...h, ltp, pnl };
    });

    const totalEquityPnl = holdingsResults.reduce((acc, h) => acc + h.pnl, 0);
    const totalCryptoPnl = cryptoResults.reduce((acc, c) => acc + c.pnl, 0);

    return new Response(
      JSON.stringify({
        success: true,
        user_id: userId,
        equity: { holdings: holdingsResults, total_pnl: totalEquityPnl },
        crypto: { holdings: cryptoResults, total_pnl: totalCryptoPnl },
        total_unrealized_pnl: totalEquityPnl + totalCryptoPnl
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
