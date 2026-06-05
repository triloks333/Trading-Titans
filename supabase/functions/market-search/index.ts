import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Inline CORS helpers
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

// Inline Crypto Search (Coingecko)
const CG_BASE = "https://api.coingecko.com/api/v3";
let _cgList: { id: string; symbol: string; name: string }[] = [];
let _cgListTime = 0;

async function getCgList(): Promise<{ id: string; symbol: string; name: string }[]> {
  const now = Date.now();
  if (_cgList.length > 0 && now - _cgListTime < 3600000) return _cgList;
  try {
    const res = await fetch(`${CG_BASE}/coins/list`, { headers: { Accept: "application/json" } });
    if (res.ok) {
      _cgList = await res.json();
      _cgListTime = now;
    }
  } catch {
    // fallback or ignore
  }
  return _cgList;
}

async function searchCrypto(
  query: string
): Promise<{ symbol: string; name: string; market: string; id: string }[]> {
  const q = query.toLowerCase();
  const list = await getCgList();
  const results: { symbol: string; name: string; market: string; id: string }[] = [];

  for (const c of list) {
    if (
      c.symbol.toLowerCase() === q ||
      c.name.toLowerCase().includes(q) ||
      c.id.toLowerCase().includes(q)
    ) {
      results.push({ symbol: c.symbol.toUpperCase(), name: c.name, market: "crypto", id: c.id });
      if (results.length >= 25) break;
    }
  }
  return results;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const url = new URL(req.url);
    const query = url.searchParams.get("q") ?? "";
    const market = url.searchParams.get("market") ?? "stock";
    const q = query.toLowerCase().trim();

    let results: Record<string, unknown>[] = [];

    if (market === "stock") {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
      const supabase = createClient(supabaseUrl, supabaseAnonKey);

      if (q.length > 0) {
        // Query instruments table — ONLY tradeable instruments
        // This filters out bonds (-NE, -ND), indexes (-INDEX), SGB (-SG),
        // government securities (-GS, -GB, -ST, -TB), and mutual funds (-MF)
        const { data, error } = await supabase
          .from("instruments")
          .select("symbol, name, market, instrument_type, expiry_date, strike_price, option_type, lot_size")
          .eq("tradeable", true)
          .or(`symbol.ilike.%${q}%,name.ilike.%${q}%`)
          .order("instrument_type", { ascending: true })  // EQUITY first, then FUTURE, OPTION
          .order("symbol")
          .limit(40);

        if (error) {
          console.error("Database search error:", error);
        } else if (data) {
          results = data.map((item) => {
            // Check for design guideline mapping (ZOMATO -> ETERNAL)
            const sym = item.symbol.toUpperCase();
            let finalSymbol = item.symbol;
            let finalName = item.name;
            if (sym.includes("ZOMATO")) {
              finalSymbol = item.symbol.replace("ZOMATO", "ETERNAL");
              finalName = item.name.replace("Zomato", "Eternal");
            }

            // Extract clean symbol for display (remove NSE: prefix and -EQ suffix)
            // e.g., "NSE:TATACHEM-EQ" → "TATACHEM"
            let displaySymbol = finalSymbol;
            if (displaySymbol.startsWith("NSE:") || displaySymbol.startsWith("BSE:")) {
              displaySymbol = displaySymbol.substring(4);
            }

            return {
              symbol: finalSymbol,
              display_symbol: displaySymbol,
              name: finalName,
              market: item.market,
              instrument_type: item.instrument_type,
              expiry_date: item.expiry_date,
              strike_price: item.strike_price,
              option_type: item.option_type,
              lot_size: item.lot_size,
            };
          });
        }
      }
    } else {
      results = await searchCrypto(query);
    }

    return new Response(JSON.stringify(results), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
