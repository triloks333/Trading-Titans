import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { getStatus, getAuthorizeUrl, handleCallback } from "../_shared/zerodha.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const path = url.pathname.split("/").pop() ?? "";

    // GET /zerodha-auth/status
    if (path === "status" || req.method === "GET" && url.searchParams.has("status")) {
      const status = await getStatus();
      return new Response(JSON.stringify(status), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // GET /zerodha-auth/authorize-url
    if (path === "authorize-url" || path === "auth-url") {
      const result = await getAuthorizeUrl();
      return new Response(JSON.stringify(result), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // GET /zerodha-auth/callback?request_token=...&state=...
    // Note: Zerodha appends ?request_token=... (Fyers/Upstox append ?code=...)
    if (path === "callback" || url.searchParams.has("request_token") || url.searchParams.has("code")) {
      const requestToken = url.searchParams.get("request_token") ?? url.searchParams.get("code") ?? "";
      const state = url.searchParams.get("state") ?? "";
      if (!requestToken || !state) {
        return new Response(JSON.stringify({ error: "request_token and state required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const result = await handleCallback(requestToken, state);
      return new Response(JSON.stringify(result), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Default: return status
    const status = await getStatus();
    return new Response(JSON.stringify(status), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
