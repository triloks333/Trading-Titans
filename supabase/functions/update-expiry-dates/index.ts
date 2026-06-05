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

    const indices = ["NIFTY", "BANKNIFTY", "FINNIFTY"];
    const results = [];

    for (const indexSymbol of indices) {
      // Fetch distinct option expiry dates sorted ascending
      const { data, error } = await supabase
        .from("instruments")
        .select("expiry_date")
        .eq("name", indexSymbol)
        .eq("instrument_type", "OPTION")
        .gte("expiry_date", new Date().toISOString().split("T")[0])
        .order("expiry_date", { ascending: true });

      if (error) throw error;

      if (data && data.length > 0) {
        // Extract distinct sorted expiry dates
        const expiries = Array.from(new Set(data.map(d => d.expiry_date))).filter(Boolean) as string[];
        
        if (expiries.length > 0) {
          const weekly = expiries[0];
          // Find the monthly expiry: usually the last Thursday of the month.
          // We can approximate it by finding the last expiry date that belongs to the same month as 'weekly',
          // or if weekly is already the monthly, look for the next month's monthly.
          const weeklyMonth = new Date(weekly).getMonth();
          
          let monthly = weekly;
          for (const exp of expiries) {
            const expDate = new Date(exp);
            if (expDate.getMonth() === weeklyMonth) {
              monthly = exp; // Pick the latest expiry in the same month
            } else {
              break; // Next month started
            }
          }

          // Update config in the database
          const { error: upsertError } = await supabase
            .from("fo_expiry_config")
            .upsert({
              symbol: indexSymbol,
              weekly_expiry: weekly,
              monthly_expiry: monthly,
              updated_at: new Date().toISOString()
            });

          if (upsertError) throw upsertError;

          results.push({ symbol: indexSymbol, weekly, monthly });
        }
      }
    }

    return new Response(JSON.stringify({ success: true, updated: results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
