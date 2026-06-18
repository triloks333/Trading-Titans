import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
};

const HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9"
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const url = new URL(req.url);
    let dateStr = url.searchParams.get("date");
    
    // Calculate current date in IST if not provided
    if (!dateStr) {
      const now = new Date();
      const istTime = new Date(now.getTime() + (5.5 * 60 * 60 * 1000));
      const dd = String(istTime.getDate()).padStart(2, "0");
      const mm = String(istTime.getMonth() + 1).padStart(2, "0");
      const yyyy = String(istTime.getFullYear());
      dateStr = `${dd}${mm}${yyyy}`;
    }

    const fileUrl = `https://nsearchives.nseindia.com/content/fo/NSE_FO_contract_${dateStr}.csv.gz`;
    console.log(`Attempting to download NSE Contract file: ${fileUrl}`);

    let response = null;
    let retries = 3;
    let delay = 2000;

    while (retries > 0) {
      try {
        response = await fetch(fileUrl, { headers: HEADERS });
        if (response.ok) {
          break;
        } else if (response.status === 404) {
          console.log(`File not found (404) for date ${dateStr}. Exchange might be closed or data is delayed.`);
          retries--;
          if (retries > 0) {
            console.log(`Retrying in ${delay}ms...`);
            await new Promise((resolve) => setTimeout(resolve, delay));
            delay *= 2;
          }
        } else {
          throw new Error(`HTTP Error ${response.status}`);
        }
      } catch (e) {
        console.error(`Fetch attempt failed: ${e}`);
        retries--;
        if (retries > 0) {
          await new Promise((resolve) => setTimeout(resolve, delay));
          delay *= 2;
        }
      }
    }

    if (!response || !response.ok) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: `Failed to download file after retries. Status: ${response?.status}` 
        }), 
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const decompressedStream = response.body!.pipeThrough(new DecompressionStream("gzip"));
    const reader = decompressedStream.pipeThrough(new TextDecoderStream()).getReader();

    const lotMap = new Map<string, number>();
    let buffer = "";
    let isFirstLine = true;
    let stockNmIdx = 18;
    let newBrdLotQtyIdx = 9;
    let minLotIdx = 8;

    console.log("Streaming and parsing contract file line-by-line...");

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += value;
      
      let newlineIdx;
      while ((newlineIdx = buffer.indexOf("\n")) !== -1) {
        const line = buffer.substring(0, newlineIdx).trim();
        buffer = buffer.substring(newlineIdx + 1);
        
        if (!line) continue;
        
        const parts = line.split(",");
        if (isFirstLine) {
          isFirstLine = false;
          const headers = parts.map(h => h.trim());
          const sIdx = headers.indexOf("StockNm");
          const lIdx = headers.indexOf("NewBrdLotQty");
          const mIdx = headers.indexOf("MinLot");
          if (sIdx !== -1) stockNmIdx = sIdx;
          if (lIdx !== -1) newBrdLotQtyIdx = lIdx;
          if (mIdx !== -1) minLotIdx = mIdx;
          console.log(`Column indices - StockNm: ${stockNmIdx}, NewBrdLotQty: ${newBrdLotQtyIdx}, MinLot: ${minLotIdx}`);
          continue;
        }
        
        const symbol = parts[stockNmIdx];
        const lotVal = parts[newBrdLotQtyIdx] || parts[minLotIdx];
        if (symbol) {
          const lot = parseInt(lotVal) || 0;
          if (lot > 0) {
            lotMap.set(symbol.toUpperCase().trim(), lot);
          }
        }
      }
    }
    
    // Process remaining buffer
    if (buffer.trim()) {
      const parts = buffer.split(",");
      const symbol = parts[stockNmIdx];
      const lotVal = parts[newBrdLotQtyIdx] || parts[minLotIdx];
      if (symbol) {
        const lot = parseInt(lotVal) || 0;
        if (lot > 0) {
          lotMap.set(symbol.toUpperCase().trim(), lot);
        }
      }
    }

    console.log(`Extracted ${lotMap.size} unique symbols with lot sizes.`);

    if (lotMap.size === 0) {
      return new Response(
        JSON.stringify({ success: true, count: 0, message: "No valid lot sizes found in file." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Convert map to list of records
    const lotsList = Array.from(lotMap.entries()).map(([symbol, lot_size]) => ({
      trading_symbol: symbol,
      lot_size,
    }));

    // Perform bulk update in Supabase staging table in batches of 2000
    console.log(`Uploading ${lotsList.length} lot sizes to nse_instrument_lots...`);
    const batchSize = 2000;
    for (let i = 0; i < lotsList.length; i += batchSize) {
      const chunk = lotsList.slice(i, i + batchSize);
      const { error: upsertError } = await supabase
        .from("nse_instrument_lots")
        .upsert(chunk, { onConflict: "trading_symbol" });
      
      if (upsertError) {
        console.error(`Staging upsert failed at batch ${i}:`, upsertError);
        throw upsertError;
      }
    }

    // Now call RPC function to update instruments and fo_instruments from nse_instrument_lots
    const { error: rpcError } = await supabase.rpc("sync_lots_from_staging");
    if (rpcError) {
      console.error("Staging staging sync RPC failed:", rpcError);
      throw rpcError;
    }

    return new Response(
      JSON.stringify({ success: true, count: lotsList.length, date: dateStr }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("sync-nse-contract fatal error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
