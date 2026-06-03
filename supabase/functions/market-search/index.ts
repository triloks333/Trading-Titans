import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { searchStocks } from "../_shared/yahoo.ts";
import { searchCrypto } from "../_shared/coingecko.ts";

const CURATED_STOCKS = [
  { symbol: "RELIANCE", name: "Reliance Industries", market: "stock" },
  { symbol: "TCS", name: "Tata Consultancy Services", market: "stock" },
  { symbol: "HDFCBANK", name: "HDFC Bank", market: "stock" },
  { symbol: "INFY", name: "Infosys", market: "stock" },
  { symbol: "ICICIBANK", name: "ICICI Bank", market: "stock" },
  { symbol: "HINDUNILVR", name: "Hindustan Unilever", market: "stock" },
  { symbol: "ITC", name: "ITC Limited", market: "stock" },
  { symbol: "SBIN", name: "State Bank of India", market: "stock" },
  { symbol: "BHARTIARTL", name: "Bharti Airtel", market: "stock" },
  { symbol: "KOTAKBANK", name: "Kotak Mahindra Bank", market: "stock" },
  { symbol: "LT", name: "Larsen & Toubro", market: "stock" },
  { symbol: "AXISBANK", name: "Axis Bank", market: "stock" },
  { symbol: "ASIANPAINT", name: "Asian Paints", market: "stock" },
  { symbol: "MARUTI", name: "Maruti Suzuki", market: "stock" },
  { symbol: "BAJFINANCE", name: "Bajaj Finance", market: "stock" },
  { symbol: "WIPRO", name: "Wipro", market: "stock" },
  { symbol: "HCLTECH", name: "HCL Technologies", market: "stock" },
  { symbol: "ULTRACEMCO", name: "UltraTech Cement", market: "stock" },
  { symbol: "TITAN", name: "Titan Company", market: "stock" },
  { symbol: "SUNPHARMA", name: "Sun Pharmaceutical", market: "stock" },
  { symbol: "TMCV", name: "Tata Motors - Commercial", market: "stock" },
  { symbol: "TMPV", name: "Tata Motors - Passenger", market: "stock" },
  { symbol: "ADANIENT", name: "Adani Enterprises", market: "stock" },
  { symbol: "NTPC", name: "NTPC", market: "stock" },
  { symbol: "ZOMATO", name: "Zomato", market: "stock" },
  { symbol: "PAYTM", name: "One97 Communications (Paytm)", market: "stock" },
];

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
      // Search curated list first
      results = CURATED_STOCKS.filter(
        (s) => s.symbol.toLowerCase().includes(q) || s.name.toLowerCase().includes(q)
      ).slice(0, 25);

      // If few results, also search Yahoo Finance
      if (results.length < 5 && q.length >= 1) {
        try {
          const yfResults = await searchStocks(query);
          for (const yf of yfResults) {
            if (!results.some((r) => r.symbol === yf.symbol)) {
              results.push(yf);
            }
          }
        } catch {
          // fallback to curated only
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
