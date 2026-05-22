import { createClient } from "jsr:@supabase/supabase-js@2";

const UPSTOX_BASE = "https://api.upstox.com/v2";

interface UpstoxConfig {
  apiKey: string;
  apiSecret: string;
  redirectUri: string;
}

function getConfig(): UpstoxConfig {
  return {
    apiKey: Deno.env.get("UPSTOX_API_KEY") ?? "",
    apiSecret: Deno.env.get("UPSTOX_API_SECRET") ?? "",
    redirectUri: Deno.env.get("UPSTOX_REDIRECT_URI") ?? "",
  };
}

function getServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, serviceKey);
}

export async function getStatus(): Promise<Record<string, unknown>> {
  const cfg = getConfig();
  if (!cfg.apiKey || !cfg.apiSecret) {
    return { configured: false, authorized: false, reason: "not_configured" };
  }

  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("upstox_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc) {
    return { configured: true, authorized: false, reason: "not_logged_in" };
  }

  const expiresAt = doc.expires_at ? new Date(doc.expires_at + "Z").getTime() : 0;
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
    throw new Error("Upstox not configured");
  }

  const state = crypto.randomUUID();
  const supabase = getServiceClient();
  await supabase.from("upstox_states").insert({ id: state, created_at: new Date().toISOString() });

  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.apiKey,
    redirect_uri: cfg.redirectUri,
    state,
  });

  return {
    auth_url: `https://api.upstox.com/v2/login/authorization/dialog?${params}`,
    state,
  };
}

export async function handleCallback(code: string, state: string): Promise<Record<string, unknown>> {
  const supabase = getServiceClient();
  const { data: validState } = await supabase
    .from("upstox_states")
    .select("*")
    .eq("id", state)
    .maybeSingle();

  if (!validState) throw new Error("Invalid state");
  await supabase.from("upstox_states").delete().eq("id", state);

  const cfg = getConfig();
  const body = new URLSearchParams({
    code,
    client_id: cfg.apiKey,
    client_secret: cfg.apiSecret,
    redirect_uri: cfg.redirectUri,
    grant_type: "authorization_code",
  });

  const res = await fetch(`${UPSTOX_BASE}/login/authorization/token`, {
    method: "POST",
    headers: {
      accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Upstox token exchange failed: ${text.slice(0, 200)}`);
  }

  const payload = await res.json();
  const accessToken = payload.access_token;
  if (!accessToken) throw new Error("No access_token returned");

  // Upstox tokens expire at 3:30 AM IST next day
  const now = new Date();
  const istOffset = 5.5 * 60 * 60 * 1000;
  const nowIst = new Date(now.getTime() + istOffset);
  const cutoff = new Date(nowIst);
  cutoff.setHours(3, 30, 0, 0);
  if (nowIst >= cutoff) cutoff.setDate(cutoff.getDate() + 1);
  const expiresAt = new Date(cutoff.getTime() - istOffset).toISOString();

  await supabase.from("upstox_tokens").upsert({
    id: "main",
    access_token: accessToken,
    expires_at: expiresAt,
    created_at: new Date().toISOString(),
  });

  return {
    ok: true,
    expires_at: expiresAt,
    message: "Upstox connected. Real-time NSE data is now active.",
  };
}

export async function fetchQuote(symbol: string): Promise<Record<string, unknown> | null> {
  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("upstox_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc?.access_token) return null;

  const expiresAt = doc.expires_at ? new Date(doc.expires_at + "Z").getTime() : 0;
  if (expiresAt && expiresAt <= Date.now()) return null;

  const token = doc.access_token as string;
  const key = `NSE_EQ|${symbol.toUpperCase().trim()}`;

  const res = await fetch(
    `${UPSTOX_BASE}/market-quote/quotes?instrument_key=${encodeURIComponent(key)}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    }
  );

  if (!res.ok) return null;

  const json = await res.json();
  const data = json?.data ?? {};
  const first = Object.values(data as Record<string, any>)[0] as Record<string, any> | undefined;
  if (!first) return null;

  const price = Number(first.last_price) || 0;
  const prev = Number(first.ohlc?.close) || Number(first.close_price) || price;
  const change = price - prev;
  const changePct = prev ? (change / prev) * 100 : 0;

  return {
    symbol: symbol.toUpperCase(),
    yf_symbol: key,
    name: first.symbol ?? symbol.toUpperCase(),
    price: round(price, 2),
    previous_close: round(prev, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "stock",
    source: "upstox",
  };
}

function round(n: number, decimals: number): number {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}
