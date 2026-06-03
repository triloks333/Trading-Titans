import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // Authenticated user client (respects RLS)
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service client for write fallback or elevated reads if needed (e.g. inserting autopsies securely)
    const serviceClient = createClient(supabaseUrl, supabaseServiceKey);

    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Fetch user's wallet balance
    const { data: profile, error: profileError } = await serviceClient
      .from("profiles")
      .select("wallet_balance")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const walletBalance = Number(profile.wallet_balance) || 11000.0;

    // 2. Fetch recent executed orders
    const { data: ordersData, error: ordersError } = await serviceClient
      .from("orders")
      .select("id, symbol, name, market, side, quantity, price, total, realized_pnl, created_at, instrument_type, order_type")
      .eq("user_id", user.id)
      .eq("status", "executed")
      .order("created_at", { ascending: false });

    if (ordersError || !ordersData) {
      return new Response(JSON.stringify({ error: "Failed to fetch orders" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const realizedTrades = ordersData.filter(
      (o) => o.realized_pnl && Number(o.realized_pnl) !== 0
    );

    if (realizedTrades.length === 0) {
      return new Response(
        JSON.stringify({
          summary: "No realized trades yet. Start trading to see autopsy lessons.",
          insights: [],
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Fetch existing autopsies for these orders
    const orderIds = realizedTrades.map((t) => t.id);
    const { data: cachedAutopsies, error: cacheError } = await serviceClient
      .from("trade_autopsies")
      .select("*")
      .in("order_id", orderIds);

    if (cacheError) {
      return new Response(JSON.stringify({ error: "Failed to fetch autopsy cache" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const autopsyMap = new Map(cachedAutopsies?.map((a) => [a.order_id, a]));
    const finalInsights = [];
    const newAutopsiesToInsert = [];

    // 4. Generate/resolve autopsy for each trade
    for (const trade of realizedTrades.slice(0, 15)) {
      const cached = autopsyMap.get(trade.id);
      if (cached) {
        finalInsights.push({
          symbol: trade.symbol,
          name: trade.name ?? trade.symbol,
          market: trade.market,
          pnl: Number(trade.realized_pnl),
          loss: Math.abs(Number(trade.realized_pnl)),
          loss_pct: (Math.abs(Number(trade.realized_pnl)) / (Number(trade.total) || 1)) * 100,
          type: Number(trade.realized_pnl) > 0 ? "profit" : "loss",
          reason: cached.reason,
          advice: cached.advice,
        });
        continue;
      }

      // Perform Parameterized Heuristic Analysis (Option A)
      const pnl = Number(trade.realized_pnl);
      const total = Number(trade.total) || 1.0;
      const pnlPct = (Math.abs(pnl) / total) * 100;
      const isProfit = pnl > 0;
      const isOption = trade.instrument_type === "OPTION";
      const symbol = trade.symbol;
      const qty = Number(trade.quantity) || 0;
      const price = Number(trade.price) || 0;
      const orderType = trade.order_type || "market";

      // Context parameter 1: Position sizing check
      const allocationPct = (total / walletBalance) * 100;
      let sizeAdvice = "";
      let isOverSized = false;
      if (allocationPct > 35) {
        isOverSized = true;
        sizeAdvice = `Warning: Position sizing was extremely aggressive, consuming ${allocationPct.toFixed(1)}% of your total capital (₹${walletBalance.toFixed(2)}). Concentrating too much risk in a single asset can lead to severe drawdowns.`;
      } else if (allocationPct > 15) {
        sizeAdvice = `Note: Sized at ${allocationPct.toFixed(1)}% of your capital. While manageable, keep standard risk guidelines to under 10% per trade for optimal survival.`;
      } else {
        sizeAdvice = `Discipline: Great risk control. Sizing at ${allocationPct.toFixed(1)}% of capital ensures a single bad trade cannot wipe out your account.`;
      }

      // Context parameter 2: Churning / Over-trading check
      const tradeTime = new Date(trade.created_at).getTime();
      const sameSymbolTrades24h = ordersData.filter((o) => {
        if (o.symbol !== symbol || o.id === trade.id) return false;
        const oTime = new Date(o.created_at).getTime();
        return Math.abs(tradeTime - oTime) <= 24 * 60 * 60 * 1000;
      });
      const churnCount = sameSymbolTrades24h.length;
      let churnAdvice = "";
      if (churnCount > 3) {
        churnAdvice = ` Churn Alert: You entered/exited ${symbol} ${churnCount} times in 24 hours. This high activity suggests emotional over-trading and chasing momentum, leading to high transaction drag.`;
      }

      // Context parameter 3: Time-of-day check
      const dateObj = new Date(trade.created_at);
      // Convert to Indian Standard Time (IST = UTC + 5:30)
      const istTime = new Date(dateObj.getTime() + 5.5 * 60 * 60 * 1000);
      const hours = istTime.getUTCHours();
      const minutes = istTime.getUTCMinutes();
      const timeInMinutes = hours * 60 + minutes;
      
      let timingAdvice = "";
      // Market open: 9:15 AM = 555 mins. 10:00 AM = 600 mins.
      // Market close: 3:00 PM = 900 mins. 3:30 PM = 930 mins.
      if (timeInMinutes >= 555 && timeInMinutes <= 600) {
        timingAdvice = " Timing: Executed during the volatile morning open session. Early liquidity is high but trends are unstable.";
      } else if (timeInMinutes >= 900 && timeInMinutes <= 930) {
        timingAdvice = " Timing: Executed during the market close hour. Institutional positioning shifts direction rapidly here.";
      }

      // Assemble dynamic reason and advice
      let reason = "";
      let advice = "";

      if (isProfit) {
        if (isOption) {
          reason = `Captured ₹${pnl.toFixed(2)} gain on leveraged ${trade.name ?? symbol} option position (${qty} contracts at ₹${price.toFixed(2)}).`;
          advice = `Successful Option Trade! leveraged returns are sweet, but decay works against you. ${sizeAdvice}${churnAdvice}${timingAdvice}`;
        } else {
          reason = `Realized profit of ₹${pnl.toFixed(2)} (+${pnlPct.toFixed(1)}%) trading ${qty} shares of ${symbol} via ${orderType} order.`;
          advice = `Solid equity win! Keep executing clean setups. Remember to compound gains instead of scaling size prematurely. ${sizeAdvice}${churnAdvice}${timingAdvice}`;
        }
      } else {
        if (isOption) {
          reason = `Option position hit for ₹${Math.abs(pnl).toFixed(2)} (-${pnlPct.toFixed(1)}%) on ${trade.name ?? symbol} contracts.`;
          advice = `Loss on Options. Option premiums decay exponentially. Did you hold too close to expiration or hold through an IV crush? Strictly enforce a 15% stop-loss. ${sizeAdvice}${churnAdvice}${timingAdvice}`;
        } else {
          reason = `Lost ₹${Math.abs(pnl).toFixed(2)} (-${pnlPct.toFixed(1)}%) on ${qty} shares of ${symbol} entered at ₹${price.toFixed(2)}.`;
          if (pnlPct < 5.0) {
            advice = `Small loss of -${pnlPct.toFixed(1)}% is normal cost of business. Cutting early shows stop-loss discipline. Keep risk parameters tight. ${sizeAdvice}${churnAdvice}${timingAdvice}`;
          } else {
            advice = `Significant drawdown of -${pnlPct.toFixed(1)}% on ${symbol}. Avoid averaging down on losing stock positions. Ensure you follow structural trend lines. ${sizeAdvice}${churnAdvice}${timingAdvice}`;
          }
        }
      }

      // Add to insert queue
      newAutopsiesToInsert.push({
        order_id: trade.id,
        user_id: user.id,
        symbol: symbol,
        market: trade.market,
        pnl: pnl,
        reason: reason,
        advice: advice,
      });

      finalInsights.push({
        symbol: symbol,
        name: trade.name ?? symbol,
        market: trade.market,
        pnl: pnl,
        loss: Math.abs(pnl),
        loss_pct: pnlPct,
        type: isProfit ? "profit" : "loss",
        reason: reason,
        advice: advice,
      });
    }

    // 5. Bulk insert newly generated autopsies in background
    if (newAutopsiesToInsert.length > 0) {
      const { error: insertError } = await serviceClient
        .from("trade_autopsies")
        .insert(newAutopsiesToInsert);
      
      if (insertError) {
        console.error("Autopsy background caching failed:", insertError);
      }
    }

    const winCount = realizedTrades.filter((o) => Number(o.realized_pnl) > 0).length;
    const lossCount = realizedTrades.filter((o) => Number(o.realized_pnl) < 0).length;

    return new Response(
      JSON.stringify({
        summary: `Analyzed your recent trades: ${winCount} wins and ${lossCount} losses. Review these lessons to refine your edge.`,
        insights: finalInsights,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
