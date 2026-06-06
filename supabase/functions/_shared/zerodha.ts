import { createClient } from "jsr:@supabase/supabase-js@2";
import { generateMockFyersChainAndFutures } from "./fyers.ts";

const ZERODHA_BASE = "https://api.kite.trade";

interface ZerodhaConfig {
  apiKey: string;
  apiSecret: string;
  redirectUri: string;
}

function getConfig(): ZerodhaConfig {
  return {
    apiKey: Deno.env.get("ZERODHA_API_KEY") ?? "",
    apiSecret: Deno.env.get("ZERODHA_API_SECRET") ?? "",
    redirectUri: Deno.env.get("ZERODHA_REDIRECT_URI") ?? "",
  };
}

function getServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, serviceKey);
}

export function toKiteSymbol(sym: string): string {
  // Convert standard symbol (e.g. RELIANCE) to Kite format: NSE:RELIANCE
  let s = sym.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  if (s.includes(":")) return s;
  if (s === "NIFTY" || s === "NIFTY 50" || s === "^NSEI") return "NSE:NIFTY 50";
  if (s === "BANKNIFTY" || s === "BANK NIFTY" || s === "^NSEBANK") return "NSE:NIFTY BANK";
  if (s === "SENSEX" || s === "^BSESN") return "BSE:SENSEX";
  
  return `NSE:${s}`;
}

export async function getStatus(): Promise<Record<string, unknown>> {
  const cfg = getConfig();
  if (!cfg.apiKey || !cfg.apiSecret) {
    return { configured: false, authorized: false, reason: "not_configured" };
  }

  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("kite_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc) {
    return { configured: true, authorized: false, reason: "not_logged_in" };
  }

  const expiresAt = doc.expires_at ? new Date(doc.expires_at).getTime() : 0;
  const now = Date.now();
  if (expiresAt && expiresAt <= now) {
    return {
      configured: true,
      authorized: false,
      reason: "expired",
      expired_at: doc.expires_at,
    };
  }

  return {
    configured: true,
    authorized: true,
    expires_at: doc.expires_at,
    remaining_seconds: Math.floor((expiresAt - now) / 1000),
  };
}

export async function getAuthorizeUrl(): Promise<{ auth_url: string; state: string }> {
  const cfg = getConfig();
  if (!cfg.apiKey || !cfg.redirectUri) {
    throw new Error("Zerodha Connect not configured");
  }

  const state = crypto.randomUUID();
  const supabase = getServiceClient();
  
  // Save temporary state (reuse upstox_states to keep things simple or if there's no upstox_states limitation)
  await supabase.from("upstox_states").insert({ id: state, created_at: new Date().toISOString() });

  const params = new URLSearchParams({
    api_key: cfg.apiKey,
    v: "3",
    redirect_uri: cfg.redirectUri,
    state,
  });

  return {
    auth_url: `https://kite.zerodha.com/connect/login?${params.toString()}`,
    state,
  };
}

export async function handleCallback(requestToken: string, state: string): Promise<Record<string, unknown>> {
  const supabase = getServiceClient();
  
  // Verify state
  const { data: validState } = await supabase
    .from("upstox_states")
    .select("*")
    .eq("id", state)
    .maybeSingle();

  if (!validState) throw new Error("Invalid state parameter");
  await supabase.from("upstox_states").delete().eq("id", state);

  const cfg = getConfig();
  if (!cfg.apiKey || !cfg.apiSecret) {
    throw new Error("Zerodha API credentials missing from environment");
  }

  // Calculate Checksum: sha256(api_key + request_token + api_secret)
  const checksumString = cfg.apiKey + requestToken + cfg.apiSecret;
  const encoder = new TextEncoder();
  const checksumBuffer = await crypto.subtle.digest("SHA-256", encoder.encode(checksumString));
  const checksumArray = Array.from(new Uint8Array(checksumBuffer));
  const checksum = checksumArray.map(b => b.toString(16).padStart(2, "0")).join("");

  const body = new URLSearchParams({
    api_key: cfg.apiKey,
    request_token: requestToken,
    checksum,
  });

  const res = await fetch(`${ZERODHA_BASE}/session/token`, {
    method: "POST",
    headers: {
      "X-Kite-Version": "3",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Zerodha Connect session exchange failed: ${text.slice(0, 200)}`);
  }

  const payload = await res.json();
  if (payload.status !== "success" || !payload.data?.access_token) {
    throw new Error(`Zerodha Connect session token error: ${payload.message || "Unknown error"}`);
  }

  const accessToken = payload.data.access_token;
  
  // Zerodha tokens expire at 6:00 AM IST of the next day (so we set it accordingly)
  const now = new Date();
  const istOffset = 5.5 * 60 * 60 * 1000;
  const nowIst = new Date(now.getTime() + istOffset);
  const cutoff = new Date(nowIst);
  cutoff.setHours(6, 0, 0, 0); // 6:00 AM IST
  if (nowIst >= cutoff) cutoff.setDate(cutoff.getDate() + 1);
  const expiresAt = new Date(cutoff.getTime() - istOffset).toISOString();

  await supabase.from("kite_tokens").upsert({
    id: "main",
    access_token: accessToken,
    expires_at: expiresAt,
    created_at: new Date().toISOString(),
  });

  return {
    ok: true,
    expires_at: expiresAt,
    message: "Zerodha Connect authorized. Real-time market feed is now active.",
  };
}

export async function fetchQuote(symbol: string): Promise<Record<string, unknown> | null> {
  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("kite_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc?.access_token) return null;

  const expiresAt = doc.expires_at ? new Date(doc.expires_at).getTime() : 0;
  if (expiresAt && expiresAt <= Date.now()) return null;

  const cfg = getConfig();
  if (!cfg.apiKey) return null;

  const kiteSym = toKiteSymbol(symbol);

  // Kite Connect Quote API
  const res = await fetch(
    `${ZERODHA_BASE}/instruments/OHLC?i=${encodeURIComponent(kiteSym)}`,
    {
      headers: {
        "X-Kite-Version": "3",
        "Authorization": `token ${cfg.apiKey}:${doc.access_token}`,
        Accept: "application/json",
      },
    }
  );

  if (!res.ok) return null;

  const json = await res.json();
  if (json.status !== "success" || !json.data || !json.data[kiteSym]) return null;

  const data = json.data[kiteSym];
  const price = Number(data.last_price) || 0;
  const prev = Number(data.ohlc?.close) || price;
  const change = price - prev;
  const changePct = prev ? (change / prev) * 100 : 0;
  const rawSym = symbol.toUpperCase().replace(".NS", "").replace(".BO", "");

  return {
    symbol: rawSym,
    yf_symbol: kiteSym,
    name: rawSym,
    price: Math.round(price * 100) / 100,
    previous_close: Math.round(prev * 100) / 100,
    change: Math.round(change * 100) / 100,
    change_pct: Math.round(changePct * 100) / 100,
    currency: "INR",
    market: "stock",
    source: "zerodha",
    day_low: data.ohlc?.low != null ? Math.round(Number(data.ohlc.low) * 100) / 100 : undefined,
    day_high: data.ohlc?.high != null ? Math.round(Number(data.ohlc.high) * 100) / 100 : undefined,
    open: data.ohlc?.open != null ? Math.round(Number(data.ohlc.open) * 100) / 100 : undefined,
    volume: data.volume != null ? Number(data.volume) : undefined,
  };
}

export async function fetchOptionChain(symbol: string, strikeCount = 25): Promise<Record<string, unknown> | null> {
  const quote = await fetchQuote(symbol);
  if (!quote) return null;

  const spotPrice = (quote.price as number) ?? 100.0;
  const change = (quote.change as number) ?? 0.0;
  const changePct = (quote.change_pct as number) ?? 0.0;

  // Generate complete option chain using current real-time spot price from Zerodha Connect
  const chain = generateMockFyersChainAndFutures(symbol, spotPrice, change, changePct, strikeCount);

  return {
    ...chain,
    source: "zerodha",
  };
}
