import { storage } from "@/src/utils/storage";

const BASE = process.env.EXPO_PUBLIC_BACKEND_URL || "";
const API = `${BASE}/api`;
const TOKEN_KEY = "tt_token";

export async function getToken(): Promise<string | null> {
  return await storage.secureGet<string>(TOKEN_KEY, "");
}

export async function setToken(t: string | null): Promise<void> {
  if (t) await storage.secureSet(TOKEN_KEY, t);
  else await storage.secureRemove(TOKEN_KEY);
}

async function request<T>(path: string, opts: RequestInit = {}, auth = true): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...((opts.headers as Record<string, string>) || {}),
  };
  if (auth) {
    const t = await getToken();
    if (t) headers.Authorization = `Bearer ${t}`;
  }
  const res = await fetch(`${API}${path}`, { ...opts, headers });
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const j = await res.json();
      detail = j.detail || detail;
    } catch {}
    throw new Error(detail);
  }
  return (await res.json()) as T;
}

// ---------- Types ----------
export interface User {
  id: string;
  email: string;
  name: string;
  wallet_balance: number;
  subscription_active: boolean;
  created_at: string;
}

export interface AuthResponse {
  access_token: string;
  token_type: string;
  user: User;
}

export interface Quote {
  symbol: string;
  yf_symbol?: string;
  name: string;
  price: number;
  previous_close: number;
  change: number;
  change_pct: number;
  currency: string;
  market: string;
  display_name?: string;
  category?: string;
}

export interface Holding {
  symbol: string;
  name: string;
  market: string;
  quantity: number;
  avg_price: number;
  current_price: number;
  invested: number;
  current: number;
  pnl: number;
  pnl_pct: number;
}

export interface Portfolio {
  wallet_balance: number;
  invested_value: number;
  current_value: number;
  unrealized_pnl: number;
  unrealized_pnl_pct: number;
  realized_pnl: number;
  holdings: Holding[];
}

export interface Order {
  symbol: string;
  name: string;
  market: string;
  side: string;
  quantity: number;
  price: number;
  total: number;
  realized_pnl: number;
  created_at: string;
}

export interface HistoryPoint {
  t: number;
  v: number;
}

export interface SearchItem {
  symbol: string;
  name: string;
  market: string;
}

// ---------- API ----------
export const api = {
  register: (email: string, password: string, name: string) =>
    request<AuthResponse>("/auth/register", { method: "POST", body: JSON.stringify({ email, password, name }) }, false),
  login: (email: string, password: string) =>
    request<AuthResponse>("/auth/login", { method: "POST", body: JSON.stringify({ email, password }) }, false),
  me: () => request<User>("/auth/me"),

  marketOverview: () => request<Quote[]>("/market/overview", {}, false),
  quote: (symbol: string, market: string) =>
    request<Quote>(`/market/quote?symbol=${encodeURIComponent(symbol)}&market=${market}`, {}, false),
  search: (q: string, market: string) =>
    request<SearchItem[]>(`/market/search?q=${encodeURIComponent(q)}&market=${market}`, {}, false),
  history: (symbol: string, market: string, range: string) =>
    request<{ symbol: string; points: HistoryPoint[] }>(
      `/market/history?symbol=${encodeURIComponent(symbol)}&market=${market}&range=${range}`,
      {},
      false
    ),

  placeOrder: (symbol: string, market: string, side: "buy" | "sell", quantity: number) =>
    request<any>("/trade/order", { method: "POST", body: JSON.stringify({ symbol, market, side, quantity }) }),
  portfolio: () => request<Portfolio>("/portfolio"),
  orders: () => request<Order[]>("/orders"),
  analytics: () => request<any>("/analytics"),
  leaderboard: () => request<any[]>("/leaderboard"),

  watchlist: () => request<any[]>("/watchlist"),
  addWatch: (symbol: string, market: string) =>
    request<any>("/watchlist", { method: "POST", body: JSON.stringify({ symbol, market }) }),
  removeWatch: (symbol: string, market: string) =>
    request<any>(`/watchlist?symbol=${encodeURIComponent(symbol)}&market=${market}`, { method: "DELETE" }),

  whatIf: (symbol: string, market: string, amount: number, years_ago: number) =>
    request<any>("/whatif", { method: "POST", body: JSON.stringify({ symbol, market, amount, years_ago }) }, false),
  autopsy: () => request<any>("/autopsy"),

  upstoxStatus: () => request<any>("/upstox/status", {}, false),
  upstoxAuthUrl: () => request<{ auth_url: string; state: string }>("/upstox/authorize-url", {}, false),

  createSubscriptionOrder: (planId: string = "titan_1l") =>
    request<any>(`/subscription/create-order?plan_id=${encodeURIComponent(planId)}`, { method: "POST" }),
  listPlans: () => request<any[]>("/subscription/plans", {}, false),
  activateSubscription: (payload: any = {}) =>
    request<any>("/subscription/activate", { method: "POST", body: JSON.stringify(payload) }),
};
