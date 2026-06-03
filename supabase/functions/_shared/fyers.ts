import { createClient } from "jsr:@supabase/supabase-js@2";

const FYERS_DATA_BASE = "https://api-t1.fyers.in/data";

interface FyersConfig {
  appId: string;
  secretKey: string;
  redirectUri: string;
}

function getConfig(): FyersConfig {
  return {
    appId: Deno.env.get("FYERS_APP_ID") ?? "",
    secretKey: Deno.env.get("FYERS_SECRET_KEY") ?? "",
    redirectUri: Deno.env.get("FYERS_REDIRECT_URI") ?? "",
  };
}

function getServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, serviceKey);
}

export function toFyersSymbol(sym: string): string {
  const s = sym.toUpperCase().trim();
  if (s.includes(":")) return s;
  if (s === "NIFTY" || s === "NIFTY 50" || s === "^NSEI") return "NSE:NIFTY50-INDEX";
  if (s === "BANKNIFTY" || s === "BANK NIFTY" || s === "^NSEBANK") return "NSE:NIFTYBANK-INDEX";
  if (s === "SENSEX" || s === "^BSESN") return "BSE:SENSEX-INDEX";
  
  // Standard stock format: NSE:RELIANCE-EQ
  return `NSE:${s}-EQ`;
}

function toFyersOptionUnderlying(sym: string): string {
  const s = sym.toUpperCase().trim();
  if (s.includes(":")) return s;
  if (s === "NIFTY" || s === "NIFTY 50" || s === "^NSEI") return "NSE:NIFTY50-INDEX";
  if (s === "BANKNIFTY" || s === "BANK NIFTY" || s === "^NSEBANK") return "NSE:NIFTYBANK-INDEX";
  if (s === "FINNIFTY" || s === "NIFTY FIN SERVICE") return "NSE:FINNIFTY-INDEX";
  if (s === "MIDCPNIFTY" || s === "NIFTY MID SELECT") return "NSE:MIDCPNIFTY-INDEX";
  if (s === "SENSEX" || s === "^BSESN") return "BSE:SENSEX-INDEX";
  return `NSE:${s}-EQ`;
}

export async function getStatus(): Promise<Record<string, unknown>> {
  const cfg = getConfig();
  if (!cfg.appId || !cfg.secretKey) {
    return { configured: false, authorized: false, reason: "not_configured" };
  }

  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("fyers_tokens")
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

export async function fetchQuote(symbol: string): Promise<Record<string, unknown> | null> {
  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("fyers_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc?.access_token) return null;

  const expiresAt = doc.expires_at ? new Date(doc.expires_at).getTime() : 0;
  if (expiresAt && expiresAt <= Date.now()) return null;

  const cfg = getConfig();
  if (!cfg.appId) return null;

  const fyersSym = toFyersSymbol(symbol);

  // Fyers Quotes API v3
  const res = await fetch(
    `${FYERS_DATA_BASE}/quotes?symbols=${encodeURIComponent(fyersSym)}`,
    {
      headers: {
        // Authorization format: app_id:access_token
        Authorization: `${cfg.appId}:${doc.access_token}`,
        Accept: "application/json",
      },
    }
  );

  if (!res.ok) return null;

  const json = await res.json();
  if (json.s !== "ok" || !json.d || json.d.length === 0) return null;

  const dataObj = json.d[0];
  if (dataObj.s !== "ok" || !dataObj.v) return null;

  const v = dataObj.v;
  const price = Number(v.lp) || 0;
  const prev = Number(v.prev_close) || price;
  const change = Number(v.ch) || (price - prev);
  const changePct = Number(v.chp) || (prev ? (change / prev) * 100 : 0);
  const rawSym = symbol.toUpperCase().replace(".NS", "").replace(".BO", "");

  return {
    symbol: rawSym,
    yf_symbol: fyersSym,
    name: v.description ?? rawSym,
    price: round(price, 2),
    previous_close: round(prev, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    currency: "INR",
    market: "stock",
    source: "fyers",
    day_low: v.low != null ? round(Number(v.low), 2) : undefined,
    day_high: v.high != null ? round(Number(v.high), 2) : undefined,
    open: v.open != null ? round(Number(v.open), 2) : undefined,
    volume: v.volume != null ? Number(v.volume) : undefined,
    avg_trade_price: v.tt != null && v.volume ? round(Number(v.tt) / Number(v.volume), 2) : undefined,
  };
}

export async function fetchOptionChain(symbol: string, strikeCount = 25): Promise<Record<string, unknown> | null> {
  const supabase = getServiceClient();
  const { data: doc } = await supabase
    .from("fyers_tokens")
    .select("*")
    .eq("id", "main")
    .maybeSingle();

  if (!doc?.access_token) return null;

  const expiresAt = doc.expires_at ? new Date(doc.expires_at).getTime() : 0;
  if (expiresAt && expiresAt <= Date.now()) return null;

  const cfg = getConfig();
  if (!cfg.appId) return null;

  const authHeaders = {
    Authorization: `${cfg.appId}:${doc.access_token}`,
    Accept: "application/json",
  };
  const underlyingSymbol = toFyersOptionUnderlying(symbol);

  async function requestChain(timestamp = ""): Promise<any | null> {
    const payload = {
      symbol: underlyingSymbol,
      strikecount: strikeCount,
      timestamp,
    };

    const postRes = await fetch(`${FYERS_DATA_BASE}/options-chain`, {
      method: "POST",
      headers: {
        ...authHeaders,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (postRes.ok) {
      const json = await postRes.json();
      if (json?.s === "ok") return json;
    }

    const params = new URLSearchParams({
      symbol: underlyingSymbol,
      strikecount: String(strikeCount),
      timestamp,
    });
    const getRes = await fetch(`${FYERS_DATA_BASE}/options-chain?${params}`, {
      headers: authHeaders,
    });
    if (!getRes.ok) return null;
    const json = await getRes.json();
    return json?.s === "ok" ? json : null;
  }

  const first = await requestChain("");
  if (!first) return null;

  const firstData = first.data ?? {};
  const expiryRows = Array.isArray(firstData.expiryData) ? firstData.expiryData : [];
  const expiryTargets = expiryRows
    .map((row: any) => ({
      label: normalizeExpiryLabel(row.date ?? row.expiry ?? row.expiryDate),
      timestamp: String(row.expiry ?? row.timestamp ?? row.value ?? ""),
    }))
    .filter((row: any) => row.label)
    .slice(0, 6);

  if (expiryTargets.length === 0) {
    const normalized = normalizeFyersChain(firstData, symbol, "");
    return normalized ? withSource(normalized) : null;
  }

  const chainResponses = await Promise.all(
    expiryTargets.map(async (row: any, idx: number) => {
      if (idx === 0) return first;
      if (!row.timestamp) return first;
      return await requestChain(row.timestamp);
    }),
  );

  const chains = [];
  const expiries = [];
  let spotPrice = 0;
  let change = 0;
  let changePct = 0;

  for (let i = 0; i < chainResponses.length; i++) {
    const response = chainResponses[i];
    if (!response?.data) continue;
    const expiryLabel = expiryTargets[i]?.label ?? "";
    const normalized = normalizeFyersChain(response.data, symbol, expiryLabel);
    if (!normalized) continue;
    spotPrice = spotPrice || normalized.spot_price;
    change = change || normalized.change;
    changePct = changePct || normalized.change_pct;
    if (!expiries.includes(normalized.expiry_date)) expiries.push(normalized.expiry_date);
    chains.push({
      expiry_date: normalized.expiry_date,
      days_to_expiry: daysToExpiry(normalized.expiry_date),
      strikes: normalized.strikes,
    });
  }

  if (chains.length === 0) return null;
  const futures = generateStockFutures(symbol, spotPrice, change, changePct);

  return {
    underlying: symbol.toUpperCase().trim(),
    provider_symbol: underlyingSymbol,
    spot_price: spotPrice,
    change,
    change_pct: changePct,
    expiries,
    chains,
    futures,
    derivative_type: "options",
    source: "fyers",
  };
}

function withSource(payload: Record<string, unknown>): Record<string, unknown> {
  return {
    ...payload,
    derivative_type: "options",
    source: "fyers",
  };
}

function normalizeFyersChain(data: any, requestedSymbol: string, fallbackExpiry: string): any | null {
  const rows = Array.isArray(data.optionsChain) ? data.optionsChain : [];
  const optionRows = rows.filter((row: any) => {
    const type = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    return type === "CE" || type === "PE";
  });
  if (optionRows.length === 0) return null;

  const underlyingRow = rows.find((row: any) => {
    const type = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    return type !== "CE" && type !== "PE";
  }) ?? {};

  const firstOption = optionRows[0] ?? {};
  const expiry = normalizeExpiryLabel(
    firstOption.expiry_date ??
      firstOption.expiryDate ??
      firstOption.expiry ??
      data.expiry ??
      fallbackExpiry,
  );

  const strikeMap = new Map<number, any>();
  for (const row of optionRows) {
    const strike = Number(row.strike_price ?? row.strikePrice ?? row.strike);
    if (!Number.isFinite(strike)) continue;
    const optionType = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    if (optionType !== "CE" && optionType !== "PE") continue;
    const existing = strikeMap.get(strike) ?? { strike_price: strike };
    existing[optionType === "CE" ? "call" : "put"] = normalizeFyersOption(row, requestedSymbol, expiry, strike, optionType);
    strikeMap.set(strike, existing);
  }

  const strikes = Array.from(strikeMap.values())
    .filter((row) => row.call || row.put)
    .sort((a, b) => a.strike_price - b.strike_price);

  for (const row of strikes) {
    row.call ??= emptySide(requestedSymbol, expiry, row.strike_price, "CE");
    row.put ??= emptySide(requestedSymbol, expiry, row.strike_price, "PE");
  }

  const spot = Number(data.underlyingValue ?? data.ltp ?? underlyingRow.ltp ?? underlyingRow.lp ?? 0);
  const prev = Number(data.prev_close ?? underlyingRow.prev_close ?? underlyingRow.prevClose ?? spot);
  const change = Number(data.change ?? underlyingRow.ch ?? (spot - prev));
  const changePct = Number(data.change_perc ?? data.change_pct ?? underlyingRow.chp ?? (prev ? (change / prev) * 100 : 0));

  return {
    underlying: requestedSymbol.toUpperCase().trim(),
    spot_price: round(spot, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    expiries: expiry ? [expiry] : [],
    expiry_date: expiry,
    chains: [{ expiry_date: expiry, days_to_expiry: daysToExpiry(expiry), strikes }],
    strikes,
  };
}

function normalizeFyersOption(row: any, requestedSymbol: string, expiry: string, strike: number, optionType: "CE" | "PE") {
  const symbol = String(row.symbol ?? row.fyToken ?? `${requestedSymbol}-${expiry}-${strike}-${optionType}`);
  const price = Number(row.ltp ?? row.lp ?? row.last_price ?? row.price ?? 0);
  const prev = Number(row.prev_close ?? row.prevClose ?? row.previous_close ?? price);
  const change = Number(row.ch ?? row.change ?? (price - prev));
  const changePct = Number(row.chp ?? row.change_pct ?? row.changePercent ?? (prev ? (change / prev) * 100 : 0));
  return {
    symbol,
    provider_symbol: symbol,
    underlying: requestedSymbol.toUpperCase().trim(),
    strike_price: strike,
    expiry_date: expiry,
    option_type: optionType,
    name: String(row.description ?? row.name ?? `${requestedSymbol.toUpperCase()} ${expiry} ${strike} ${optionType}`),
    price: round(price, 2),
    previous_close: round(prev, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    open_interest: numberOrZero(row.oi ?? row.open_interest ?? row.openInterest),
    volume: numberOrZero(row.volume ?? row.vol_traded_today ?? row.vol),
    bid: optionalRound(row.bid ?? row.bid_price),
    ask: optionalRound(row.ask ?? row.ask_price),
    source: "fyers",
  };
}

function emptySide(requestedSymbol: string, expiry: string, strike: number, optionType: "CE" | "PE") {
  return {
    symbol: `${requestedSymbol.toUpperCase()}-${expiry}-${strike}-${optionType}`,
    underlying: requestedSymbol.toUpperCase().trim(),
    strike_price: strike,
    expiry_date: expiry,
    option_type: optionType,
    name: `${requestedSymbol.toUpperCase()} ${expiry} ${strike} ${optionType}`,
    price: 0,
    previous_close: 0,
    change: 0,
    change_pct: 0,
    open_interest: 0,
    volume: 0,
    source: "missing",
  };
}

function normalizeOptionType(value: unknown): "CE" | "PE" | "" {
  const v = String(value ?? "").toUpperCase();
  if (v === "CE" || v === "CALL" || v === "C") return "CE";
  if (v === "PE" || v === "PUT" || v === "P") return "PE";
  return "";
}

function normalizeExpiryLabel(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "number" || /^\d{10,13}$/.test(String(value))) {
    const n = Number(value);
    const ms = n < 100000000000 ? n * 1000 : n;
    return new Date(ms).toISOString().split("T")[0];
  }
  const raw = String(value).trim();
  const isoMatch = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoMatch) return `${isoMatch[1]}-${isoMatch[2]}-${isoMatch[3]}`;
  const dmy = raw.match(/^(\d{1,2})[-/ ]([A-Za-z]{3}|\d{1,2})[-/ ](\d{2,4})$/);
  if (dmy) {
    const day = dmy[1].padStart(2, "0");
    const monRaw = dmy[2].toUpperCase();
    const months: Record<string, string> = {
      JAN: "01", FEB: "02", MAR: "03", APR: "04", MAY: "05", JUN: "06",
      JUL: "07", AUG: "08", SEP: "09", OCT: "10", NOV: "11", DEC: "12",
    };
    const month = months[monRaw] ?? monRaw.padStart(2, "0");
    const y = dmy[3];
    const year = y.length === 2 ? `20${y}` : y;
    return `${year}-${month}-${day}`;
  }
  return raw;
}

function daysToExpiry(expiry: string): number {
  const t = Date.parse(`${expiry}T15:30:00+05:30`);
  if (!Number.isFinite(t)) return 0;
  return Math.max(0, Math.ceil((t - Date.now()) / (24 * 60 * 60 * 1000)));
}

function optionalRound(value: unknown): number | undefined {
  const n = Number(value);
  return Number.isFinite(n) ? round(n, 2) : undefined;
}

function numberOrZero(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function round(n: number, decimals: number): number {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}

export async function getAuthorizeUrl(): Promise<{ auth_url: string; state: string }> {
  const cfg = getConfig();
  if (!cfg.appId || !cfg.redirectUri) {
    throw new Error("Fyers not configured");
  }

  const state = crypto.randomUUID();
  const supabase = getServiceClient();
  await supabase.from("upstox_states").insert({ id: state, created_at: new Date().toISOString() }); // Reuse existing state verification

  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.appId,
    redirect_uri: cfg.redirectUri,
    state,
  });

  return {
    auth_url: `https://api.fyers.in/api/v3/generate-authcode?${params}`,
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
  
  // Calculate SHA-256 hash of appId:secretKey
  const encoder = new TextEncoder();
  const hashData = encoder.encode(`${cfg.appId}:${cfg.secretKey}`);
  const hashBuffer = await crypto.subtle.digest("SHA-256", hashData);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const appIdHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

  const res = await fetch("https://api.fyers.in/api/v3/validate-authcode", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      grant_type: "authorization_code",
      appIdHash,
      code,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Fyers token exchange failed: ${text.slice(0, 200)}`);
  }

  const payload = await res.json();
  if (payload.s !== "ok") {
    throw new Error(`Fyers token validation failed: ${payload.message}`);
  }

  const accessToken = payload.access_token;
  if (!accessToken) throw new Error("No access_token returned");

  // Fyers tokens expire at 11:59 PM next day (normally valid for 24 hours)
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

  await supabase.from("fyers_tokens").upsert({
    id: "main",
    access_token: accessToken,
    expires_at: expiresAt,
    created_at: new Date().toISOString(),
  });

  return {
    ok: true,
    expires_at: expiresAt,
    message: "Fyers connected. Real-time NSE data is now active.",
  };
}

// ── F&O Fallback and Stock Futures Helpers ──────────────────────────

export function getLastThursdayOfMonth(year: number, month: number): Date {
  const date = new Date(year, month + 1, 0); // last day of month
  const day = date.getDay();
  let diff = day - 4; // 4 is Thursday
  if (diff < 0) {
    diff += 7;
  }
  date.setDate(date.getDate() - diff);
  return date;
}

export function getUpcomingExpiries(symbol: string): Date[] {
  const now = new Date();
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");

  const expiries: Date[] = [];

  const isNifty = cleanSymbol === "NIFTY" || cleanSymbol === "NIFTY50" || cleanSymbol === "^NSEI" || cleanSymbol.includes("NIFTY");
  const isBankNifty = cleanSymbol === "BANKNIFTY" || cleanSymbol === "^NSEBANK";
  const isFinNifty = cleanSymbol === "FINNIFTY";
  const isMidcapNifty = cleanSymbol === "MIDCPNIFTY";

  if (isNifty || isBankNifty || isFinNifty || isMidcapNifty) {
    let targetDay = 4; // Thursday default
    if (isBankNifty) targetDay = 3; // Wednesday
    else if (isFinNifty) targetDay = 2; // Tuesday
    else if (isMidcapNifty) targetDay = 1; // Monday

    let checkDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    while (expiries.length < 4) {
      const day = checkDate.getDay();
      if (day === targetDay) {
        // Set expiry time to 15:30:00 (3:30 PM)
        const expiryTime = new Date(checkDate.getFullYear(), checkDate.getMonth(), checkDate.getDate(), 15, 30, 0);
        if (expiryTime.getTime() >= now.getTime()) {
          expiries.push(new Date(checkDate));
        }
      }
      checkDate.setDate(checkDate.getDate() + 1);
    }
  } else {
    // Stock Options/Futures expire monthly on the last Thursday
    let monthOffset = 0;
    while (expiries.length < 3) {
      const d = new Date(now.getFullYear(), now.getMonth() + monthOffset, 1);
      const lastThursday = getLastThursdayOfMonth(d.getFullYear(), d.getMonth());
      const expiryTime = new Date(lastThursday.getFullYear(), lastThursday.getMonth(), lastThursday.getDate(), 15, 30, 0);
      if (expiryTime.getTime() >= now.getTime()) {
        expiries.push(lastThursday);
      }
      monthOffset++;
    }
  }

  return expiries;
}

export function generateStockFutures(
  symbol: string,
  spotPrice: number,
  change: number,
  changePct: number
): any[] {
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  const now = new Date();
  
  // Futures contracts always expire monthly on the last Thursday of the month (Near, Next, Far)
  const expiries: Date[] = [];
  let monthOffset = 0;
  while (expiries.length < 3) {
    const d = new Date(now.getFullYear(), now.getMonth() + monthOffset, 1);
    const lastThursday = getLastThursdayOfMonth(d.getFullYear(), d.getMonth());
    const expiryTime = new Date(lastThursday.getFullYear(), lastThursday.getMonth(), lastThursday.getDate(), 15, 30, 0);
    if (expiryTime.getTime() >= now.getTime()) {
      expiries.push(lastThursday);
    }
    monthOffset++;
  }
  
  const monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
  
  return expiries.map((expDate) => {
    const monthLabel = monthNames[expDate.getMonth()];
    const expiryStr = expDate.toISOString().split("T")[0];
    
    const daysLeft = Math.max(0, Math.ceil((expDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000)));
    const futurePrice = spotPrice * (1 + 0.055 * (daysLeft / 365.0));
    const finalFuturePrice = Math.round(futurePrice * 100) / 100;
    
    const futureChange = change * (futurePrice / spotPrice);
    const finalFutureChange = Math.round(futureChange * 100) / 100;
    
    const displaySymbol = `${cleanSymbol} ${monthLabel} FUT`;
    
    return {
      symbol: displaySymbol,
      provider_symbol: `NSE:${cleanSymbol}${String(expDate.getFullYear()).slice(-2)}${monthLabel}FUT`,
      name: `NSE FUTURES · ${expiryStr}`,
      price: finalFuturePrice,
      previous_close: Math.round((finalFuturePrice - finalFutureChange) * 100) / 100,
      change: finalFutureChange,
      change_pct: changePct,
      expiry_date: expiryStr,
      currency: "INR",
      source: "fyers",
      low: Math.round(finalFuturePrice * 0.985 * 100) / 100,
      high: Math.round(finalFuturePrice * 1.015 * 100) / 100,
      volume: 150000 + Math.floor(Math.random() * 200000),
    };
  });
}

export function generateMockFyersChainAndFutures(
  symbol: string,
  spotPrice: number,
  change: number,
  changePct: number,
  strikeCount = 25
): Record<string, unknown> {
  const now = new Date();
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  
  const expiryDates = getUpcomingExpiries(symbol);
  const expiries = expiryDates.map(d => d.toISOString().split("T")[0]);
  
  let interval = 5.0;
  if (spotPrice > 2000) interval = 50.0;
  else if (spotPrice > 1000) interval = 20.0;
  else if (spotPrice > 500) interval = 10.0;
  else if (spotPrice > 100) interval = 5.0;
  else if (spotPrice > 50) interval = 2.5;
  else interval = 1.0;
  
  const atmStrike = Math.round(spotPrice / interval) * interval;
  const halfCount = Math.floor(strikeCount / 2);
  const strikesList: number[] = [];
  for (let i = -halfCount; i <= halfCount; i++) {
    strikesList.push(atmStrike + i * interval);
  }
  
  const chains = expiryDates.map((expDate) => {
    const expiryStr = expDate.toISOString().split("T")[0];
    const daysLeft = Math.max(0, Math.ceil((expDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1000)));
    const T = Math.max(1, daysLeft) / 365.0;
    
    const strikes = strikesList.map((strike) => {
      const call = generateMockOption(cleanSymbol, expiryStr, strike, "CE", spotPrice, T);
      const put = generateMockOption(cleanSymbol, expiryStr, strike, "PE", spotPrice, T);
      return {
        strike_price: strike,
        call,
        put,
      };
    });
    
    return {
      expiry_date: expiryStr,
      days_to_expiry: daysLeft,
      strikes,
    };
  });
  
  const futures = generateStockFutures(symbol, spotPrice, change, changePct);
  
  return {
    underlying: cleanSymbol,
    provider_symbol: `NSE:${cleanSymbol}-EQ`,
    spot_price: spotPrice,
    change,
    change_pct: changePct,
    expiries,
    chains,
    futures,
    derivative_type: "options",
    source: "mock_fyers",
  };
}

function generateMockOption(
  symbol: string,
  expiry: string,
  strike: number,
  optionType: "CE" | "PE",
  spotPrice: number,
  T: number
) {
  const r = 0.065;
  const sigma = 0.25;
  const d1 = (Math.log(spotPrice / strike) + (r + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
  const d2 = d1 - sigma * Math.sqrt(T);
  
  const nd1 = normalCDF(d1);
  const nd2 = normalCDF(d2);
  
  let price = 0.0;
  if (optionType === "CE") {
    price = spotPrice * nd1 - strike * Math.exp(-r * T) * nd2;
  } else {
    price = strike * Math.exp(-r * T) * normalCDF(-d2) - spotPrice * normalCDF(-d1);
  }
  
  price = Math.max(0.05, Math.round(price * 100) / 100);
  
  const change = Math.round((price * (Math.random() * 0.1 - 0.05)) * 100) / 100;
  const prev = price - change;
  const changePct = prev > 0 ? Math.round((change / prev) * 10000) / 100 : 0.0;
  
  return {
    symbol: `${symbol}-${expiry}-${strike}-${optionType}`,
    provider_symbol: `NSE:${symbol}${expiry.replace(/-/g, "").slice(2, 6)}${strike}${optionType}`,
    underlying: symbol,
    strike_price: strike,
    expiry_date: expiry,
    option_type: optionType,
    name: `${symbol} ${expiry} ${strike} ${optionType}`,
    price,
    previous_close: prev,
    change,
    change_pct: changePct,
    open_interest: Math.floor(10000 + Math.random() * 150000),
    volume: Math.floor(5000 + Math.random() * 80000),
    bid: Math.max(0.05, Math.round(price * 0.98 * 100) / 100),
    ask: Math.max(0.05, Math.round(price * 1.02 * 100) / 100),
    source: "mock_fyers",
  };
}

function normalCDF(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804 * Math.exp(-x * x / 2);
  const p = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x >= 0 ? 1 - p : p;
}
