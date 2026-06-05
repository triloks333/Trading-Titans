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

    // Fetch the equity WebSocket health status
    const { data, error } = await supabase
      .from("ws_health")
      .select("*")
      .eq("id", "equity")
      .maybeSingle();

    if (error) throw error;

    let status = "HEALTHY";
    let reconnectRequired = false;

    if (data) {
      const lastTick = new Date(data.last_tick_at).getTime();
      const now = Date.now();
      const diffMinutes = (now - lastTick) / (1000 * 60);

      // If last tick is older than 3 minutes, flag reconnect required
      if (diffMinutes > 3) {
        reconnectRequired = true;
        status = "TIMEOUT";
        
        // Update state in database
        const { error: updateError } = await supabase
          .from("ws_health")
          .update({
            reconnect_required: true,
            updated_at: new Date().toISOString()
          })
          .eq("id", "equity");

        if (updateError) throw updateError;
      }
    } else {
      // Initialize if row is missing
      const { error: insertError } = await supabase
        .from("ws_health")
        .insert({
          id: "equity",
          last_tick_at: new Date().toISOString(),
          reconnect_required: false,
          updated_at: new Date().toISOString()
        });

      if (insertError) throw insertError;
    }

    return new Response(JSON.stringify({ success: true, status, reconnectRequired }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
