import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get the stored refresh token
    const { data: tokenData, error: fetchError } = await supabase
      .from("fyers_tokens")
      .select("*")
      .eq("id", "main")
      .maybeSingle();

    if (fetchError || !tokenData || !tokenData.refresh_token) {
      throw new Error("No stored refresh token found: " + (fetchError?.message ?? ""));
    }

    const appId = Deno.env.get("FYERS_APP_ID") ?? "";
    const secretKey = Deno.env.get("FYERS_SECRET_KEY") ?? "";
    
    // Generate appIdHash: SHA256 of (app_id + ":" + secret_key)
    const encoder = new TextEncoder();
    const data = encoder.encode(`${appId}:${secretKey}`);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const appIdHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    // Call Fyers refresh token API
    const res = await fetch("https://api-t1.fyers.in/api/v3/validate-refresh-token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        grant_type: "refresh_token",
        appIdHash: appIdHash,
        refresh_token: tokenData.refresh_token
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Fyers token refresh API failed: ${res.statusText} - ${errText}`);
    }

    const result = await res.json();
    if (result.s !== "ok" || !result.access_token) {
      throw new Error(`Fyers token refresh returned error status: ${JSON.stringify(result)}`);
    }

    // Fyers access tokens expire in 24 hours
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    const { error: updateError } = await supabase
      .from("fyers_tokens")
      .update({
        access_token: result.access_token,
        expires_at: expiresAt,
        created_at: new Date().toISOString()
      })
      .eq("id", "main");

    if (updateError) throw updateError;

    return new Response(JSON.stringify({ success: true, expiresAt: expiresAt }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
