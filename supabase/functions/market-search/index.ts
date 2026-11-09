import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { searchUsStocks, searchPakistanStocks, searchItalyStocks } from "../_shared/yahoo.ts";
import { COMMODITIES, COMMODITY_MARKET } from "../_shared/us_market.ts";

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
  const __start = Date.now();
  let __status = 200;
  try {
    const __res = await handleRequest(req);
    __status = __res.status;
    return __res;
  } finally {
    console.log(`[market-search] ${req.method} ${Date.now() - __start}ms status=${__status}`);
  }
});

async function handleRequest(req: Request): Promise<Response> {
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
        const COLUMNS =
          "symbol, name, market, instrument_type, expiry_date, strike_price, option_type, lot_size";

        /*
         * Two queries, then rank.
         *
         * One `%q%` query ordered alphabetically was not good enough, in a way
         * that showed: searching "RELI" listed RELCHEMQ and RELIABLE above
         * RELIANCE, and "NIFTY" filled all 40 slots with Aditya Birla and Kotak
         * ETFs before reaching the index itself. Ordering happens in the database
         * BEFORE the limit, so the best match was not merely ranked low — for a
         * common substring it was cut off entirely and could not be found at all.
         *
         * The exact-match pass is therefore separate and unconditional: whatever
         * else happens, typing a ticker in full finds that ticker. The stored form
         * varies (`RELIANCE`, `NSE:RELIANCE`, `RELIANCE-EQ`, `NSE:RELIANCE-EQ`),
         * so all four are tried.
         */
        const upper = q.toUpperCase();
        const exactPass = await supabase
          .from("instruments")
          .select(COLUMNS)
          .eq("tradeable", true)
          .or(
            [
              `symbol.eq.${upper}`,
              `symbol.eq.NSE:${upper}`,
              `symbol.eq.${upper}-EQ`,
              `symbol.eq.NSE:${upper}-EQ`,
            ].join(","),
          )
          .limit(6);

        /*
         * A dedicated prefix pass, because the fuzzy pass below cannot be relied
         * on to contain one. It orders by instrument_type, and EQUITY sorts first,
         * so for a substring shared by many cash listings its whole window is
         * consumed by equities: "NIFTY" filled all 120 rows with NIFTY-branded
         * ETFs, and no NIFTY future or option ever reached the ranking stage.
         * Asking for prefix matches separately guarantees the derivatives on a
         * ticker are reachable by typing that ticker.
         */
        const prefixPass = await supabase
          .from("instruments")
          .select(COLUMNS)
          .eq("tradeable", true)
          .or(`symbol.ilike.${q}%,symbol.ilike.NSE:${q}%`)
          .order("symbol")
          .limit(40);

        const fuzzyPass = await supabase
          .from("instruments")
          .select(COLUMNS)
          .eq("tradeable", true)
          .or(`symbol.ilike.%${q}%,name.ilike.%${q}%`)
          .order("instrument_type", { ascending: true })
          .order("symbol")
          .limit(120);

        const error = exactPass.error ?? prefixPass.error ?? fuzzyPass.error;
        const merged = [
          ...(exactPass.data ?? []),
          ...(prefixPass.data ?? []),
          ...(fuzzyPass.data ?? []),
        ];

        // De-duplicate on the stored symbol; the exact pass wins ties by arriving
        // first.
        const seen = new Set<string>();
        const unique = merged.filter((r) => {
          const k = String((r as { symbol: string }).symbol).toUpperCase();
          if (seen.has(k)) return false;
          seen.add(k);
          return true;
        });

        /**
         * Relevance, lowest score first.
         *
         * Deliberately ranks an exact symbol above a prefix, a prefix above a
         * substring, and any symbol hit above a name-only hit — so "TCS" cannot be
         * outranked by a company whose *name* happens to contain "tcs". Cash
         * equity sorts ahead of derivatives on the same underlying because that is
         * what someone typing a bare ticker almost always wants; the shorter
         * symbol wins the final tie, which keeps RELIANCE above RELIANCEPP.
         */
        const score = (r: Record<string, unknown>): number => {
          let sym = String(r.symbol ?? "").toUpperCase();
          if (sym.startsWith("NSE:") || sym.startsWith("BSE:")) sym = sym.slice(4);
          if (sym.endsWith("-EQ")) sym = sym.slice(0, -3);
          const name = String(r.name ?? "").toUpperCase();
          const type = String(r.instrument_type ?? "");

          let base: number;
          if (sym === upper) base = 0;
          else if (sym.startsWith(upper)) base = 100;
          else if (sym.includes(upper)) base = 200;
          else if (name.startsWith(upper)) base = 300;
          else if (name.includes(upper)) base = 400;
          else base = 500;

          const typeRank = type === "EQUITY" ? 0 : type === "FUTURE" ? 10 : 20;
          return base + typeRank + Math.min(sym.length, 40) / 100;
        };

        const data = error
          ? null
          : unique.sort((a, b) => score(a) - score(b)).slice(0, 40);

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

            // Extract clean symbol (remove NSE:/BSE: prefix and -EQ suffix)
            // e.g., "NSE:TATACHEM-EQ" → "TATACHEM"
            let displaySymbol = finalSymbol;
            if (displaySymbol.startsWith("NSE:") || displaySymbol.startsWith("BSE:")) {
              displaySymbol = displaySymbol.substring(4);
            }
            if (displaySymbol.endsWith("-EQ")) {
              displaySymbol = displaySymbol.substring(0, displaySymbol.length - 3);
            }

            return {
              symbol: displaySymbol,
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
    } else if (market === "us_stock") {
      // No local instrument table for US equities, so search Yahoo directly.
      // Avoids a symbol-sync cron and a mirror of the whole US listing.
      if (q.length > 0) {
        const hits = await searchUsStocks(query);
        results = hits.map((h) => ({
          symbol: h.symbol,
          display_symbol: h.symbol,
          name: h.name,
          market: "us_stock",
          instrument_type: "EQUITY",
        }));
      }
    } else if (market === COMMODITY_MARKET) {
      // Five fixed instruments: filter locally, no provider call.
      results = COMMODITIES
        .filter((c) => (c.name + " " + c.symbol).toLowerCase().includes(q))
        .map((c) => ({ symbol: c.symbol, display_symbol: c.name, name: c.name, market: COMMODITY_MARKET, instrument_type: "EQUITY" }));
    } else if (market === "pakistan_stock") {
      if (q.length > 0) {
        const hits = await searchPakistanStocks(query);
        results = hits.map((h) => {
          const disp = h.symbol.endsWith(".KA") ? h.symbol.slice(0, -3) : h.symbol;
          return {
            symbol: h.symbol,
            display_symbol: disp,
            name: h.name,
            market: "pakistan_stock",
            instrument_type: "EQUITY",
          };
        });
      }
    } else if (market === "italy_stock") {
      if (q.length > 0) {
        const hits = await searchItalyStocks(query);
        results = hits.map((h) => {
          const disp = h.symbol.endsWith(".MI") ? h.symbol.slice(0, -3) : h.symbol;
          return {
            symbol: h.symbol,
            display_symbol: disp,
            name: h.name,
            market: "italy_stock",
            instrument_type: "EQUITY",
          };
        });
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
}
