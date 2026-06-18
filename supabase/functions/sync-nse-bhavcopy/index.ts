import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { unzipSync } from "https://esm.sh/fflate@0.8.2";

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
    let dateStr = url.searchParams.get("date"); // Format: YYYYMMDD
    
    // Calculate current date in IST if not provided
    if (!dateStr) {
      const now = new Date();
      const istTime = new Date(now.getTime() + (5.5 * 60 * 60 * 1000));
      const dd = String(istTime.getDate()).padStart(2, "0");
      const mm = String(istTime.getMonth() + 1).padStart(2, "0");
      const yyyy = String(istTime.getFullYear());
      dateStr = `${yyyy}${mm}${dd}`;
    }

    const fileUrl = `https://nsearchives.nseindia.com/content/fo/BhavCopy_NSE_FO_0_0_0_${dateStr}_F_0000.csv.zip`;
    console.log(`Attempting to download NSE F&O Bhavcopy file: ${fileUrl}`);

    let response = null;
    let retries = 3;
    let delay = 2000;

    while (retries > 0) {
      try {
        response = await fetch(fileUrl, { headers: HEADERS });
        if (response.ok) {
          break;
        } else if (response.status === 404) {
          console.log(`Bhavcopy not found (404) for date ${dateStr}. Exchange might be closed or data is delayed.`);
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

    const zipBytes = await response.arrayBuffer();
    console.log(`Extracting zip data of size ${zipBytes.byteLength} bytes...`);

    const decompressed = unzipSync(new Uint8Array(zipBytes));
    const csvFilename = Object.keys(decompressed).find(name => name.endsWith('.csv'));
    
    if (!csvFilename) {
      throw new Error("No CSV file found inside the zip archive.");
    }

    const csvText = new TextDecoder().decode(decompressed[csvFilename]);
    
    let newlineIndex = csvText.indexOf("\n");
    if (newlineIndex === -1) {
      throw new Error("Invalid CSV: No newline found.");
    }
    const headerLine = csvText.substring(0, newlineIndex).trim();

    console.log("Parsing CSV text and sending in chunks to Postgres RPC...");
    
    let chunkStart = 0;
    let lineCount = 0;
    let searchIndex = 0;
    let totalUploaded = 0;
    let chunkCount = 0;

    while (true) {
      const nextNewline = csvText.indexOf("\n", searchIndex);
      if (nextNewline === -1) {
        const lastChunk = csvText.substring(chunkStart);
        if (lastChunk.trim()) {
          chunkCount++;
          console.log(`Sending final chunk ${chunkCount} to Postgres...`);
          const payload = (chunkStart === 0) ? lastChunk : (headerLine + "\n" + lastChunk);
          const { error } = await supabase.rpc("import_fo_bhavcopy_csv", { csv_text: payload });
          if (error) {
            console.error(`RPC error for final chunk:`, error);
            throw error;
          }
        }
        break;
      }
      lineCount++;
      searchIndex = nextNewline + 1;
      if (lineCount >= 15000) {
        chunkCount++;
        console.log(`Sending chunk ${chunkCount} to Postgres...`);
        const chunk = csvText.substring(chunkStart, nextNewline);
        const payload = (chunkStart === 0) ? chunk : (headerLine + "\n" + chunk);
        const { error } = await supabase.rpc("import_fo_bhavcopy_csv", { csv_text: payload });
        if (error) {
          console.error(`RPC error for chunk ${chunkCount}:`, error);
          throw error;
        }
        totalUploaded += lineCount;
        chunkStart = nextNewline + 1;
        lineCount = 0;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
    }

    console.log(`Finished uploading CSV in ${chunkCount} chunks.`);

    // Call staging sync to cascade values to instruments/fo_instruments directly from nse_fo_bhavcopy
    const { error: rpcError } = await supabase.rpc("sync_lots_from_staging");
    if (rpcError) {
      console.error("Sync RPC failed:", rpcError);
      throw rpcError;
    }

    return new Response(
      JSON.stringify({ success: true, message: "Successfully synced F&O bhavcopy and updated instruments.", date: dateStr }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("sync-nse-bhavcopy fatal error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
