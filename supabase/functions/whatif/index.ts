import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { whatIfStock } from "../_shared/yahoo.ts";
import { whatIfCrypto } from "../_shared/coingecko.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "POST required" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const symbol = body.symbol as string ?? "";
    const market = body.market as string ?? "stock";
    const amount = Number(body.amount) || 0;
    const yearsAgo = Number(body.years_ago) || 1;

    if (!symbol || amount <= 0) {
      return new Response(JSON.stringify({ error: "symbol and amount required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = market === "crypto"
      ? await whatIfCrypto(symbol, amount, yearsAgo)
      : await whatIfStock(symbol, amount, yearsAgo);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
