import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { isUsDst, isUsMarketOpen } from "../_shared/us_market.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400",
};

serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Determine current time in IST (UTC + 5.5 hours)
    const utcTime = Date.now();
    const istOffset = 5.5 * 60 * 60 * 1000;
    const istTime = new Date(utcTime + istOffset);

    const day = istTime.getUTCDay(); // 0 is Sunday, 6 is Saturday
    const hours = istTime.getUTCHours();
    const minutes = istTime.getUTCMinutes();
    const timeAsMinutes = hours * 60 + minutes;

    // Indian Stock Market hours: 9:15 AM (555 mins) to 3:30 PM (930 mins), Monday to Friday (1 to 5)
    const isWeekDay = day >= 1 && day <= 5;
    const isMarketHours = timeAsMinutes >= 555 && timeAsMinutes <= 930;
    const nseOpen = isWeekDay && isMarketHours;

    return new Response(
      JSON.stringify({
        success: true,
        nse: {
          open: nseOpen,
          hours: "9:15 AM - 3:30 PM IST",
          timezone: "Asia/Kolkata",
          current_time: istTime.toISOString()
        },
        crypto: {
          open: true,
          hours: "24/7"
        },
        us_stock: {
          open: isUsMarketOpen(),
          hours: "9:30 AM - 4:00 PM ET",
          timezone: "America/New_York",
          dst: isUsDst(),
          // The session lands overnight in India, and the IST clock time shifts
          // by an hour when US daylight saving flips.
          ist_hours: isUsDst() ? "7:00 PM - 1:30 AM IST" : "8:00 PM - 2:30 AM IST"
        }
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
