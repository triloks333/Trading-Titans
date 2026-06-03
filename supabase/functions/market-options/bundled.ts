// supabase/functions/market-options/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// supabase/functions/_shared/cors.ts
var corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  "Access-Control-Max-Age": "86400"
};
function handleCors(req) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

// supabase/functions/_shared/fyers.ts
import { createClient } from "jsr:@supabase/supabase-js@2";
var FYERS_DATA_BASE = "https://api-t1.fyers.in/data";
function getConfig() {
  return {
    appId: Deno.env.get("FYERS_APP_ID") ?? "",
    secretKey: Deno.env.get("FYERS_SECRET_KEY") ?? "",
    redirectUri: Deno.env.get("FYERS_REDIRECT_URI") ?? ""
  };
}
function getServiceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, serviceKey);
}
function toFyersOptionUnderlying(sym) {
  const s = sym.toUpperCase().trim();
  if (s.includes(":")) return s;
  if (s === "NIFTY" || s === "NIFTY 50" || s === "^NSEI") return "NSE:NIFTY50-INDEX";
  if (s === "BANKNIFTY" || s === "BANK NIFTY" || s === "^NSEBANK") return "NSE:NIFTYBANK-INDEX";
  if (s === "FINNIFTY" || s === "NIFTY FIN SERVICE") return "NSE:FINNIFTY-INDEX";
  if (s === "MIDCPNIFTY" || s === "NIFTY MID SELECT") return "NSE:MIDCPNIFTY-INDEX";
  if (s === "SENSEX" || s === "^BSESN") return "BSE:SENSEX-INDEX";
  return `NSE:${s}-EQ`;
}
async function fetchOptionChain(symbol, strikeCount = 25) {
  const supabase = getServiceClient();
  const { data: doc } = await supabase.from("fyers_tokens").select("*").eq("id", "main").maybeSingle();
  if (!doc?.access_token) return null;
  const expiresAt = doc.expires_at ? new Date(doc.expires_at).getTime() : 0;
  if (expiresAt && expiresAt <= Date.now()) return null;
  const cfg = getConfig();
  if (!cfg.appId) return null;
  const authHeaders = {
    Authorization: `${cfg.appId}:${doc.access_token}`,
    Accept: "application/json"
  };
  const underlyingSymbol = toFyersOptionUnderlying(symbol);
  async function requestChain(timestamp = "") {
    const payload = {
      symbol: underlyingSymbol,
      strikecount: strikeCount,
      timestamp
    };
    const postRes = await fetch(`${FYERS_DATA_BASE}/options-chain`, {
      method: "POST",
      headers: {
        ...authHeaders,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });
    if (postRes.ok) {
      const json3 = await postRes.json();
      if (json3?.s === "ok") return json3;
    }
    const params = new URLSearchParams({
      symbol: underlyingSymbol,
      strikecount: String(strikeCount),
      timestamp
    });
    const getRes = await fetch(`${FYERS_DATA_BASE}/options-chain?${params}`, {
      headers: authHeaders
    });
    if (!getRes.ok) return null;
    const json2 = await getRes.json();
    return json2?.s === "ok" ? json2 : null;
  }
  const first = await requestChain("");
  if (!first) return null;
  const firstData = first.data ?? {};
  const expiryRows = Array.isArray(firstData.expiryData) ? firstData.expiryData : [];
  const expiryTargets = expiryRows.map((row) => ({
    label: normalizeExpiryLabel(row.date ?? row.expiry ?? row.expiryDate),
    timestamp: String(row.expiry ?? row.timestamp ?? row.value ?? "")
  })).filter((row) => row.label).slice(0, 6);
  if (expiryTargets.length === 0) {
    const normalized = normalizeFyersChain(firstData, symbol, "");
    return normalized ? withSource(normalized) : null;
  }
  const chainResponses = await Promise.all(
    expiryTargets.map(async (row, idx) => {
      if (idx === 0) return first;
      if (!row.timestamp) return first;
      return await requestChain(row.timestamp);
    })
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
      strikes: normalized.strikes
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
    source: "fyers"
  };
}
function withSource(payload) {
  return {
    ...payload,
    derivative_type: "options",
    source: "fyers"
  };
}
function normalizeFyersChain(data, requestedSymbol, fallbackExpiry) {
  const rows = Array.isArray(data.optionsChain) ? data.optionsChain : [];
  const optionRows = rows.filter((row) => {
    const type = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    return type === "CE" || type === "PE";
  });
  if (optionRows.length === 0) return null;
  const underlyingRow = rows.find((row) => {
    const type = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    return type !== "CE" && type !== "PE";
  }) ?? {};
  const firstOption = optionRows[0] ?? {};
  const expiry = normalizeExpiryLabel(
    firstOption.expiry_date ?? firstOption.expiryDate ?? firstOption.expiry ?? data.expiry ?? fallbackExpiry
  );
  const strikeMap = /* @__PURE__ */ new Map();
  for (const row of optionRows) {
    const strike = Number(row.strike_price ?? row.strikePrice ?? row.strike);
    if (!Number.isFinite(strike)) continue;
    const optionType = normalizeOptionType(row.option_type ?? row.optionType ?? row.type);
    if (optionType !== "CE" && optionType !== "PE") continue;
    const existing = strikeMap.get(strike) ?? { strike_price: strike };
    existing[optionType === "CE" ? "call" : "put"] = normalizeFyersOption(row, requestedSymbol, expiry, strike, optionType);
    strikeMap.set(strike, existing);
  }
  const strikes = Array.from(strikeMap.values()).filter((row) => row.call || row.put).sort((a, b) => a.strike_price - b.strike_price);
  for (const row of strikes) {
    row.call ??= emptySide(requestedSymbol, expiry, row.strike_price, "CE");
    row.put ??= emptySide(requestedSymbol, expiry, row.strike_price, "PE");
  }
  const spot = Number(data.underlyingValue ?? data.ltp ?? underlyingRow.ltp ?? underlyingRow.lp ?? 0);
  const prev = Number(data.prev_close ?? underlyingRow.prev_close ?? underlyingRow.prevClose ?? spot);
  const change = Number(data.change ?? underlyingRow.ch ?? spot - prev);
  const changePct = Number(data.change_perc ?? data.change_pct ?? underlyingRow.chp ?? (prev ? change / prev * 100 : 0));
  return {
    underlying: requestedSymbol.toUpperCase().trim(),
    spot_price: round(spot, 2),
    change: round(change, 2),
    change_pct: round(changePct, 2),
    expiries: expiry ? [expiry] : [],
    expiry_date: expiry,
    chains: [{ expiry_date: expiry, days_to_expiry: daysToExpiry(expiry), strikes }],
    strikes
  };
}
function normalizeFyersOption(row, requestedSymbol, expiry, strike, optionType) {
  const symbol = String(row.symbol ?? row.fyToken ?? `${requestedSymbol}-${expiry}-${strike}-${optionType}`);
  const price = Number(row.ltp ?? row.lp ?? row.last_price ?? row.price ?? 0);
  const prev = Number(row.prev_close ?? row.prevClose ?? row.previous_close ?? price);
  const change = Number(row.ch ?? row.change ?? price - prev);
  const changePct = Number(row.chp ?? row.change_pct ?? row.changePercent ?? (prev ? change / prev * 100 : 0));
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
    source: "fyers"
  };
}
function emptySide(requestedSymbol, expiry, strike, optionType) {
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
    source: "missing"
  };
}
function normalizeOptionType(value) {
  const v = String(value ?? "").toUpperCase();
  if (v === "CE" || v === "CALL" || v === "C") return "CE";
  if (v === "PE" || v === "PUT" || v === "P") return "PE";
  return "";
}
function normalizeExpiryLabel(value) {
  if (value == null) return "";
  if (typeof value === "number" || /^\d{10,13}$/.test(String(value))) {
    const n = Number(value);
    const ms = n < 1e11 ? n * 1e3 : n;
    return new Date(ms).toISOString().split("T")[0];
  }
  const raw = String(value).trim();
  const isoMatch = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoMatch) return `${isoMatch[1]}-${isoMatch[2]}-${isoMatch[3]}`;
  const dmy = raw.match(/^(\d{1,2})[-/ ]([A-Za-z]{3}|\d{1,2})[-/ ](\d{2,4})$/);
  if (dmy) {
    const day = dmy[1].padStart(2, "0");
    const monRaw = dmy[2].toUpperCase();
    const months = {
      JAN: "01",
      FEB: "02",
      MAR: "03",
      APR: "04",
      MAY: "05",
      JUN: "06",
      JUL: "07",
      AUG: "08",
      SEP: "09",
      OCT: "10",
      NOV: "11",
      DEC: "12"
    };
    const month = months[monRaw] ?? monRaw.padStart(2, "0");
    const y = dmy[3];
    const year = y.length === 2 ? `20${y}` : y;
    return `${year}-${month}-${day}`;
  }
  return raw;
}
function daysToExpiry(expiry) {
  const t = Date.parse(`${expiry}T15:30:00+05:30`);
  if (!Number.isFinite(t)) return 0;
  return Math.max(0, Math.ceil((t - Date.now()) / (24 * 60 * 60 * 1e3)));
}
function optionalRound(value) {
  const n = Number(value);
  return Number.isFinite(n) ? round(n, 2) : void 0;
}
function numberOrZero(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}
function round(n, decimals) {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}
function getLastThursdayOfMonth(year, month) {
  const date = new Date(year, month + 1, 0);
  const day = date.getDay();
  let diff = day - 4;
  if (diff < 0) {
    diff += 7;
  }
  date.setDate(date.getDate() - diff);
  return date;
}
function getUpcomingExpiries(symbol) {
  const now = /* @__PURE__ */ new Date();
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  const expiries = [];
  const isNifty = cleanSymbol === "NIFTY" || cleanSymbol === "NIFTY50" || cleanSymbol === "^NSEI" || cleanSymbol.includes("NIFTY");
  const isBankNifty = cleanSymbol === "BANKNIFTY" || cleanSymbol === "^NSEBANK";
  const isFinNifty = cleanSymbol === "FINNIFTY";
  const isMidcapNifty = cleanSymbol === "MIDCPNIFTY";
  if (isNifty || isBankNifty || isFinNifty || isMidcapNifty) {
    let targetDay = 4;
    if (isBankNifty) targetDay = 3;
    else if (isFinNifty) targetDay = 2;
    else if (isMidcapNifty) targetDay = 1;
    let checkDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    while (expiries.length < 4) {
      const day = checkDate.getDay();
      if (day === targetDay) {
        const expiryTime = new Date(checkDate.getFullYear(), checkDate.getMonth(), checkDate.getDate(), 15, 30, 0);
        if (expiryTime.getTime() >= now.getTime()) {
          expiries.push(new Date(checkDate));
        }
      }
      checkDate.setDate(checkDate.getDate() + 1);
    }
  } else {
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
function generateStockFutures(symbol, spotPrice, change, changePct) {
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  const now = /* @__PURE__ */ new Date();
  const expiries = [];
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
    const daysLeft = Math.max(0, Math.ceil((expDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1e3)));
    const futurePrice = spotPrice * (1 + 0.055 * (daysLeft / 365));
    const finalFuturePrice = Math.round(futurePrice * 100) / 100;
    const futureChange = change * (futurePrice / spotPrice);
    const finalFutureChange = Math.round(futureChange * 100) / 100;
    const displaySymbol = `${cleanSymbol} ${monthLabel} FUT`;
    return {
      symbol: displaySymbol,
      provider_symbol: `NSE:${cleanSymbol}${String(expDate.getFullYear()).slice(-2)}${monthLabel}FUT`,
      name: `NSE FUTURES \xB7 ${expiryStr}`,
      price: finalFuturePrice,
      previous_close: Math.round((finalFuturePrice - finalFutureChange) * 100) / 100,
      change: finalFutureChange,
      change_pct: changePct,
      expiry_date: expiryStr,
      currency: "INR",
      source: "fyers",
      low: Math.round(finalFuturePrice * 0.985 * 100) / 100,
      high: Math.round(finalFuturePrice * 1.015 * 100) / 100,
      volume: 15e4 + Math.floor(Math.random() * 2e5)
    };
  });
}
function generateMockFyersChainAndFutures(symbol, spotPrice, change, changePct, strikeCount = 25) {
  const now = /* @__PURE__ */ new Date();
  const cleanSymbol = symbol.toUpperCase().trim().replace(".NS", "").replace(".BO", "");
  const expiryDates = getUpcomingExpiries(symbol);
  const expiries = expiryDates.map((d) => d.toISOString().split("T")[0]);
  let interval = 5;
  if (spotPrice > 2e3) interval = 50;
  else if (spotPrice > 1e3) interval = 20;
  else if (spotPrice > 500) interval = 10;
  else if (spotPrice > 100) interval = 5;
  else if (spotPrice > 50) interval = 2.5;
  else interval = 1;
  const atmStrike = Math.round(spotPrice / interval) * interval;
  const halfCount = Math.floor(strikeCount / 2);
  const strikesList = [];
  for (let i = -halfCount; i <= halfCount; i++) {
    strikesList.push(atmStrike + i * interval);
  }
  const chains = expiryDates.map((expDate) => {
    const expiryStr = expDate.toISOString().split("T")[0];
    const daysLeft = Math.max(0, Math.ceil((expDate.getTime() - now.getTime()) / (24 * 60 * 60 * 1e3)));
    const T = Math.max(1, daysLeft) / 365;
    const strikes = strikesList.map((strike) => {
      const call = generateMockOption(cleanSymbol, expiryStr, strike, "CE", spotPrice, T);
      const put = generateMockOption(cleanSymbol, expiryStr, strike, "PE", spotPrice, T);
      return {
        strike_price: strike,
        call,
        put
      };
    });
    return {
      expiry_date: expiryStr,
      days_to_expiry: daysLeft,
      strikes
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
    source: "mock_fyers"
  };
}
function generateMockOption(symbol, expiry, strike, optionType, spotPrice, T) {
  const r = 0.065;
  const sigma = 0.25;
  const d1 = (Math.log(spotPrice / strike) + (r + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
  const d2 = d1 - sigma * Math.sqrt(T);
  const nd1 = normalCDF(d1);
  const nd2 = normalCDF(d2);
  let price = 0;
  if (optionType === "CE") {
    price = spotPrice * nd1 - strike * Math.exp(-r * T) * nd2;
  } else {
    price = strike * Math.exp(-r * T) * normalCDF(-d2) - spotPrice * normalCDF(-d1);
  }
  price = Math.max(0.05, Math.round(price * 100) / 100);
  const change = Math.round(price * (Math.random() * 0.1 - 0.05) * 100) / 100;
  const prev = price - change;
  const changePct = prev > 0 ? Math.round(change / prev * 1e4) / 100 : 0;
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
    open_interest: Math.floor(1e4 + Math.random() * 15e4),
    volume: Math.floor(5e3 + Math.random() * 8e4),
    bid: Math.max(0.05, Math.round(price * 0.98 * 100) / 100),
    ask: Math.max(0.05, Math.round(price * 1.02 * 100) / 100),
    source: "mock_fyers"
  };
}
function normalCDF(x) {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804 * Math.exp(-x * x / 2);
  const p = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x >= 0 ? 1 - p : p;
}

// supabase/functions/_shared/coindcx.ts
var COINDCX_BASE = "https://api.coindcx.com";
var _cachedFuturesPrices = null;
var _futuresPricesUpdate = 0;
var _cachedActiveFutures = {};
var _activeFuturesUpdate = {};
async function fetchFuturesChain(sym) {
  const underlying = sym.toUpperCase().trim().replace(/INR$|USDT$/, "");
  const pairs = await fetchActiveFutures("USDT");
  const matching = pairs.filter((pair) => futuresUnderlying(pair) === underlying || futuresUnderlying(pair).replace(/^1000/, "") === underlying).slice(0, 20);
  if (matching.length === 0) return null;
  const prices = await fetchFuturesPrices();
  const futures = matching.map((pair) => {
    const ticker = prices[pair] ?? {};
    const price = Number(ticker.ls ?? 0);
    const changePct = Number(ticker.pc ?? 0);
    const prev = changePct ? price / (1 + changePct / 100) : price;
    const change = price - prev;
    return {
      symbol: pair,
      provider_symbol: pair,
      underlying,
      instrument_type: "FUTURE",
      contract_type: "PERPETUAL",
      expiry_date: "PERPETUAL",
      settlement: "never",
      name: `${futuresUnderlying(pair)} Perpetual Futures`,
      price: round2(price, 4),
      previous_close: round2(prev, 4),
      change: round2(change, 4),
      change_pct: round2(changePct, 2),
      mark_price: ticker.mp != null ? round2(Number(ticker.mp), 4) : void 0,
      funding_rate: ticker.fr != null ? Number(ticker.fr) : void 0,
      high: ticker.h != null ? round2(Number(ticker.h), 4) : void 0,
      low: ticker.l != null ? round2(Number(ticker.l), 4) : void 0,
      volume: ticker.v != null ? Number(ticker.v) : void 0,
      currency: "USDT",
      source: "coindcx"
    };
  });
  const first = futures[0];
  return {
    underlying,
    spot_price: first?.price ?? 0,
    change: first?.change ?? 0,
    change_pct: first?.change_pct ?? 0,
    expiries: ["PERPETUAL"],
    futures,
    derivative_type: "futures",
    source: "coindcx"
  };
}
async function fetchFuturesPrices() {
  const now = Date.now();
  if (_cachedFuturesPrices && now - _futuresPricesUpdate < 3e3) {
    return _cachedFuturesPrices;
  }
  const response = await fetch("https://public.coindcx.com/market_data/v3/current_prices/futures/rt");
  if (!response.ok) {
    throw new Error(`CoinDCX futures prices failed: ${response.status}`);
  }
  const data = await response.json();
  _cachedFuturesPrices = data?.prices ?? {};
  _futuresPricesUpdate = now;
  return _cachedFuturesPrices;
}
async function fetchActiveFutures(marginCurrency) {
  const now = Date.now();
  const cached = _cachedActiveFutures[marginCurrency];
  if (cached && now - (_activeFuturesUpdate[marginCurrency] ?? 0) < 60 * 60 * 1e3) {
    return cached;
  }
  const url = `${COINDCX_BASE}/exchange/v1/derivatives/futures/data/active_instruments?margin_currency_short_name[]=${marginCurrency}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`CoinDCX active futures failed: ${response.status}`);
  }
  const data = await response.json();
  _cachedActiveFutures[marginCurrency] = Array.isArray(data) ? data.map((x) => String(x).toUpperCase()) : [];
  _activeFuturesUpdate[marginCurrency] = now;
  return _cachedActiveFutures[marginCurrency];
}
function normalizeFuturesPair(sym) {
  return sym.replace(/-FUTURES$/, "").toUpperCase();
}
function futuresUnderlying(pair) {
  const match = normalizeFuturesPair(pair).match(/^B-([A-Z0-9]+)_/);
  return match?.[1] ?? pair;
}
function round2(n, decimals) {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}

// supabase/functions/_shared/yahoo.ts
var YAHOO_BASE = "https://query1.finance.yahoo.com/v8/finance/chart";
var YAHOO_QUOTE = "https://query1.finance.yahoo.com/v7/finance/quote";
var UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";
var CURATED_NAMES = {
  "RELIANCE": "Reliance Industries",
  "TCS": "Tata Consultancy Services",
  "HDFCBANK": "HDFC Bank",
  "INFY": "Infosys",
  "ICICIBANK": "ICICI Bank",
  "HINDUNILVR": "Hindustan Unilever",
  "ITC": "ITC Limited",
  "SBIN": "State Bank of India",
  "BHARTIARTL": "Bharti Airtel",
  "KOTAKBANK": "Kotak Mahindra Bank",
  "LT": "Larsen & Toubro",
  "AXISBANK": "Axis Bank",
  "ASIANPAINT": "Asian Paints",
  "MARUTI": "Maruti Suzuki",
  "BAJFINANCE": "Bajaj Finance",
  "WIPRO": "Wipro",
  "HCLTECH": "HCL Technologies",
  "ULTRACEMCO": "UltraTech Cement",
  "TITAN": "Titan Company",
  "SUNPHARMA": "Sun Pharmaceutical",
  "NESTLEIND": "Nestle India",
  "TATAMOTORS": "Tata Motors",
  "TMCV": "Tata Motors - Commercial",
  "TMPV": "Tata Motors - Passenger",
  "ADANIENT": "Adani Enterprises",
  "ADANIPORTS": "Adani Ports",
  "POWERGRID": "Power Grid Corporation",
  "NTPC": "NTPC",
  "ONGC": "Oil & Natural Gas Corp",
  "COALINDIA": "Coal India",
  "JSWSTEEL": "JSW Steel",
  "TATASTEEL": "Tata Steel",
  "M&M": "Mahindra & Mahindra",
  "BAJAJFINSV": "Bajaj Finserv",
  "INDUSINDBK": "IndusInd Bank",
  "TECHM": "Tech Mahindra",
  "DRREDDY": "Dr. Reddy's Labs",
  "CIPLA": "Cipla",
  "GRASIM": "Grasim Industries",
  "BRITANNIA": "Britannia Industries",
  "HEROMOTOCO": "Hero MotoCorp",
  "EICHERMOT": "Eicher Motors",
  "BAJAJ-AUTO": "Bajaj Auto",
  "DIVISLAB": "Divi's Laboratories",
  "HDFCLIFE": "HDFC Life Insurance",
  "SBILIFE": "SBI Life Insurance",
  "TATACONSUM": "Tata Consumer Products",
  "PIDILITIND": "Pidilite Industries",
  "DMART": "Avenue Supermarts",
  "ZOMATO": "Zomato",
  "PAYTM": "One97 Communications (Paytm)",
  "IRCTC": "IRCTC"
};
function toYfSymbol(sym) {
  const s = sym.toUpperCase().trim();
  if (s.endsWith(".NS") || s.endsWith(".BO") || ["^NSEI", "^BSESN", "^NSEBANK"].includes(s)) return s;
  return `${s}.NS`;
}
function displayName(sym) {
  const map = {
    "^NSEI": "NIFTY 50",
    "^BSESN": "SENSEX",
    "^NSEBANK": "BANK NIFTY"
  };
  return map[sym] ?? sym;
}
async function fetchQuote(symbol) {
  const yfSym = toYfSymbol(symbol);
  const url = `${YAHOO_BASE}/${encodeURIComponent(yfSym)}?interval=1d&range=2d`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`YF chart failed: ${res.status} for ${yfSym}`);
  const json2 = await res.json();
  const result = json2?.chart?.result?.[0];
  if (!result) throw new Error(`No YF result for ${yfSym}`);
  const meta = result.meta ?? {};
  const timestamps = result.timestamp ?? [];
  const closes = result.indicators?.quote?.[0]?.close ?? [];
  let price = meta.regularMarketPrice ?? closes[closes.length - 1];
  let prevClose = meta.chartPreviousClose ?? meta.previousClose ?? price;
  if (price == null && closes.length > 0) {
    price = closes[closes.length - 1];
  }
  if (prevClose == null && closes.length > 1) {
    prevClose = closes[closes.length - 2];
  }
  price = Number(price) || 0;
  prevClose = Number(prevClose) || price;
  const change = price - prevClose;
  const changePct = prevClose ? change / prevClose * 100 : 0;
  const currency = meta.currency ?? "INR";
  const rawSym = yfSym.replace(".NS", "").replace(".BO", "");
  let name = CURATED_NAMES[rawSym] ?? rawSym;
  let qResult = null;
  try {
    const qUrl = `${YAHOO_QUOTE}?symbols=${encodeURIComponent(yfSym)}`;
    const qRes = await fetch(qUrl, { headers: { "User-Agent": UA } });
    if (qRes.ok) {
      const qJson = await qRes.json();
      qResult = qJson?.quoteResponse?.result?.[0];
      if (qResult) {
        if (name === rawSym) {
          name = qResult.longName ?? qResult.shortName ?? rawSym;
        }
      }
    }
  } catch {
  }
  const dayLow = qResult?.regularMarketDayLow ?? meta.regularMarketDayLow;
  const dayHigh = qResult?.regularMarketDayHigh ?? meta.regularMarketDayHigh;
  const open = qResult?.regularMarketOpen ?? meta.regularMarketOpen;
  const volume = qResult?.regularMarketVolume ?? meta.regularMarketVolume;
  return {
    symbol: rawSym,
    yf_symbol: yfSym,
    name,
    price: round3(price, 2),
    previous_close: round3(prevClose, 2),
    change: round3(change, 2),
    change_pct: round3(changePct, 2),
    currency: currency === "INR" || yfSym.startsWith("^") ? "INR" : "USD",
    market: "stock",
    display_name: displayName(yfSym),
    category: yfSym.startsWith("^") ? "index" : "stock",
    day_low: dayLow != null ? round3(Number(dayLow), 2) : void 0,
    day_high: dayHigh != null ? round3(Number(dayHigh), 2) : void 0,
    open: open != null ? round3(Number(open), 2) : void 0,
    volume: volume != null ? Number(volume) : void 0
  };
}
function round3(n, decimals) {
  const m = Math.pow(10, decimals);
  return Math.round(n * m) / m;
}

// supabase/functions/market-options/index.ts
serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const url = new URL(req.url);
    const symbol = url.searchParams.get("symbol") ?? "";
    const market = url.searchParams.get("market") ?? "stock";
    const strikeCount = Number(url.searchParams.get("strike_count") ?? "25");
    if (!symbol) {
      return json({ error: "symbol required" }, 400);
    }
    if (market === "crypto") {
      const futures = await fetchFuturesChain(symbol);
      if (!futures) {
        return json({
          error: "No CoinDCX futures contracts found for this crypto symbol.",
          derivative_type: "futures",
          source: "coindcx"
        }, 404);
      }
      return json(futures);
    }
    let chain = await fetchOptionChain(symbol, Number.isFinite(strikeCount) ? strikeCount : 25);
    if (!chain) {
      try {
        const quote = await fetchQuote(symbol);
        if (quote) {
          const spotPrice = quote.price ?? 100;
          const change = quote.change ?? 0;
          const changePct = quote.change_pct ?? 0;
          chain = generateMockFyersChainAndFutures(symbol, spotPrice, change, changePct, strikeCount);
        }
      } catch (_) {
      }
    }
    if (!chain) {
      return json({
        error: "Fyers option chain unavailable and fallback failed. Check Fyers auth/token or try an F&O-enabled NSE/BSE symbol.",
        derivative_type: "options",
        source: "fyers"
      }, 404);
    }
    return json(chain);
  } catch (err) {
    return json({ error: err?.message ?? "Unable to fetch derivatives data" }, 500);
  }
});
function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}
