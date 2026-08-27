import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Fetch Equity symbols
    console.log("Fetching Equity CSV...");
    const equityRes = await fetch("https://public.fyers.in/sym_details/NSE_CM.csv");
    if (!equityRes.ok) throw new Error("Failed to fetch Equity CSV");
    const equityText = await equityRes.text();
    const equityLines = equityText.split("\n");
    console.log(`Parsed ${equityLines.length} lines from Equity CSV.`);

    const instruments = [];

    for (const line of equityLines) {
      if (!line.trim()) continue;
      const r = line.split(",");
      if (r.length < 10) continue;

      // Equity format: 
      // 0: token, 1: name, 2: inst_type, 3: lot, 4: tick, 9: symbol
      const sym = r[9].trim();
      // Only -EQ and -SM suffixed stocks are tradeable equities
      const isTradeable = sym.endsWith("-EQ") || sym.endsWith("-SM");
      instruments.push({
        fyers_token: r[0].trim(),
        symbol: sym,
        name: r[1].trim(),
        market: "stock",
        instrument_type: "EQUITY",
        expiry_date: null,
        strike_price: null,
        option_type: null,
        lot_size: Number(r[3]) || 1,
        tradeable: isTradeable
      });
    }

    // 2. Fetch FO symbols
    console.log("Fetching FO CSV...");
    const foRes = await fetch("https://public.fyers.in/sym_details/NSE_FO.csv");
    if (!foRes.ok) throw new Error("Failed to fetch FO CSV");
    const foText = await foRes.text();
    const foLines = foText.split("\n");
    console.log(`Parsed ${foLines.length} lines from FO CSV.`);

    for (const line of foLines) {
      if (!line.trim()) continue;
      const r = line.split(",");
      if (r.length < 10) continue;

      // FO Format: 
      // 0: token, 1: name, 2: inst_type, 3: lot, 8: expiry_epoch, 9: symbol, 15: strike, 16: opt_type
      const symbol = r[9].trim();
      const name = r[1].trim();

      // Index families the app does not offer, and which actively break the
      // lot-size lookup for the index it DOES offer.
      //
      // Lot size is resolved with `LIKE 'NSE:<underlying>%'`, a prefix match, so
      // `NSE:NIFTY%` returns NIFTYNXT50 (lot 25) and NIFTYFPI (lot 1100)
      // alongside NIFTY (lot 65). NIFTYNXT50 lists only monthly expiries and
      // outnumbers NIFTY on those dates, so NIFTY monthlies were resolving to 25
      // and users saw the wrong lot size on the order screen.
      //
      // The engine-side resolver now filters on an exact underlying boundary
      // (see _shared/lot_size.ts), but the Flutter client carries its own copy of
      // the prefix query at fo_instruments_service.dart and cannot be fixed
      // without an app release. Keeping these two families out of `instruments`
      // removes the ambiguity at the source, so the shipped client resolves NIFTY
      // correctly with no update. Neither index has ever been traded (zero orders,
      // zero positions) and neither is reachable in the UI, which only maps
      // NIFTY, BANKNIFTY, FINNIFTY, MIDCPNIFTY and SENSEX.
      //
      // ponytail: an exclusion list, not a general rule. The ceiling is that a
      // future NSE index prefixing an offered one has to be added here by hand;
      // the query in docs that enumerates prefix collisions is the early warning.
      // Remove these lines once the client resolver is fixed and shipped.
      if (/^(NIFTYNXT50|NIFTYFPI)\d/.test(symbol.toUpperCase())) continue;
      const optType = r.length > 16 ? r[16].trim() : "XX";
      
      let instType = "FUTURE";
      let finalOptType = null;
      if (optType === "CE" || optType === "PE") {
        instType = "OPTION";
        finalOptType = optType;
      }

      let expiryDate = null;
      try {
        const epoch = Number(r[8].trim());
        if (epoch > 0) {
          expiryDate = new Date(epoch * 1000).toISOString().split("T")[0];
        }
      } catch (_) {}

      let strike = null;
      if (instType === "OPTION") {
        try {
          strike = Number(r[15].trim());
        } catch (_) {}
      }

      instruments.push({
        fyers_token: r[0].trim(),
        symbol: symbol,
        name: name,
        market: "stock",
        instrument_type: instType,
        expiry_date: expiryDate,
        strike_price: strike,
        option_type: finalOptType,
        lot_size: Number(r[3]) || 1,
        tradeable: true  // All F&O instruments are tradeable
      });
    }

    console.log(`Starting upsert of ${instruments.length} total instruments...`);

    // Batch upsert to database in chunks of 2000
    const batchSize = 2000;
    for (let i = 0; i < instruments.length; i += batchSize) {
      const batch = instruments.slice(i, i + batchSize);
      const { error } = await supabase.from("instruments").upsert(batch);
      if (error) {
        console.error(`Error uploading batch at index ${i}:`, error);
        throw error;
      }
    }

    return new Response(JSON.stringify({ success: true, count: instruments.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
