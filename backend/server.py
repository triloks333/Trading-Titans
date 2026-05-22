"""Trading Titans backend - paper trading on real markets."""
from __future__ import annotations

import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import bcrypt
import jwt
import requests
import yfinance as yf
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel, EmailStr, Field
from starlette.middleware.cors import CORSMiddleware

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / ".env")

MONGO_URL = os.environ.get("MONGO_URL", "")
DB_NAME = os.environ.get("DB_NAME", "trading_titans")
JWT_SECRET = os.environ.get("JWT_SECRET", "trading-titans-dev-secret-change-me")
JWT_ALGO = "HS256"
TOKEN_TTL_MIN = 60 * 24 * 7  # 7 days

# Upstox (real-time NSE/BSE via developer OAuth)
UPSTOX_KEY = os.environ.get("UPSTOX_API_KEY", "")
UPSTOX_SECRET = os.environ.get("UPSTOX_API_SECRET", "")
UPSTOX_REDIRECT = os.environ.get("UPSTOX_REDIRECT_URI", "")
UPSTOX_BASE = "https://api.upstox.com/v2"

# ---------- Optional DB (MongoDB) ----------
client: Optional[AsyncIOMotorClient] = None
db: Any = None

if MONGO_URL:
    try:
        client = AsyncIOMotorClient(MONGO_URL)
        db = client[DB_NAME]
        logging.info("MongoDB connected: %s", DB_NAME)
    except Exception as e:
        logging.warning("MongoDB not available, auth/trade endpoints disabled: %s", e)
        client = None
        db = None


# ---------- Lifespan ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    if db is not None:
        try:
            await db.users.create_index("email", unique=True)
            await db.orders.create_index([("user_id", 1), ("created_at", -1)])
            await db.holdings.create_index([("user_id", 1), ("symbol", 1), ("market", 1)], unique=True)
            await db.watchlist.create_index([("user_id", 1), ("symbol", 1), ("market", 1)], unique=True)
        except Exception as e:
            logging.warning("MongoDB index creation failed: %s", e)
    yield
    if client is not None:
        client.close()


app = FastAPI(title="Trading Titans API", lifespan=lifespan)
api = APIRouter(prefix="/api")
bearer = HTTPBearer(auto_error=True)


# ---------- Models ----------
class UserPublic(BaseModel):
    id: str
    email: EmailStr
    name: str
    wallet_balance: float
    subscription_active: bool
    created_at: datetime


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserPublic


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    name: str = Field(min_length=1, max_length=64)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class OrderIn(BaseModel):
    symbol: str
    market: str  # "stock" | "crypto"
    side: str  # "buy" | "sell"
    quantity: float = Field(gt=0)


class WhatIfIn(BaseModel):
    symbol: str
    market: str
    amount: float = Field(gt=0)
    years_ago: float = Field(gt=0, le=20)


class WatchlistIn(BaseModel):
    symbol: str
    market: str


# ---------- Helpers ----------
def hash_pw(p: str) -> str:
    return bcrypt.hashpw(p.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_pw(p: str, h: str) -> bool:
    try:
        return bcrypt.checkpw(p.encode(), h.encode())
    except Exception:
        return False


def make_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {"sub": user_id, "iat": int(now.timestamp()), "exp": int((now + timedelta(minutes=TOKEN_TTL_MIN)).timestamp())}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGO)


async def current_user(cred: HTTPAuthorizationCredentials = Depends(bearer)) -> dict:
    try:
        payload = jwt.decode(cred.credentials, JWT_SECRET, algorithms=[JWT_ALGO])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    if db is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Database not configured")
    user = await db.users.find_one({"_id": payload.get("sub")}, {"password_hash": 0})
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")
    return user


def to_public(user: dict) -> UserPublic:
    return UserPublic(
        id=user["_id"],
        email=user["email"],
        name=user.get("name", ""),
        wallet_balance=float(user.get("wallet_balance", 0.0)),
        subscription_active=bool(user.get("subscription_active", False)),
        created_at=user.get("created_at", datetime.now(timezone.utc)),
    )


# ---------- Market data (Yahoo Finance + CoinGecko) ----------
_QUOTE_CACHE: dict[str, tuple[float, dict]] = {}
_QUOTE_TTL = 15  # seconds for stocks
_CRYPTO_TTL = 120  # seconds for crypto (CoinGecko free tier is heavily rate-limited)


def _yf_symbol(sym: str) -> str:
    """Normalize Indian stock symbol for yfinance."""
    s = sym.upper().strip()
    if s.endswith(".NS") or s.endswith(".BO") or s in ("^NSEI", "^BSESN", "^NSEBANK"):
        return s
    return f"{s}.NS"


def _yf_quote(sym: str) -> dict:
    cache_key = f"yf:{sym}"
    now = time.time()
    cached = _QUOTE_CACHE.get(cache_key)
    if cached and now - cached[0] < _QUOTE_TTL:
        return cached[1]
    ticker = yf.Ticker(sym)
    fast = ticker.fast_info
    try:
        price = float(fast.last_price) if fast.last_price else None
    except Exception:
        price = None
    try:
        prev = float(fast.previous_close) if fast.previous_close else None
    except Exception:
        prev = None
    if price is None or prev is None:
        # fallback to history
        hist = ticker.history(period="2d")
        if not hist.empty:
            price = float(hist["Close"].iloc[-1])
            prev = float(hist["Close"].iloc[-2]) if len(hist) > 1 else price
    if price is None:
        raise HTTPException(404, f"No data for {sym}")
    info_name = sym
    try:
        info = ticker.get_info()
        info_name = info.get("longName") or info.get("shortName") or sym
    except Exception:
        pass
    change = price - (prev or price)
    change_pct = (change / prev * 100) if prev else 0.0
    out = {
        "symbol": sym.replace(".NS", "").replace(".BO", ""),
        "yf_symbol": sym,
        "name": info_name,
        "price": round(price, 2),
        "previous_close": round(prev or price, 2),
        "change": round(change, 2),
        "change_pct": round(change_pct, 2),
        "currency": "INR" if (sym.endswith(".NS") or sym.endswith(".BO") or sym.startswith("^NSE") or sym.startswith("^BSE")) else "USD",
        "market": "stock",
    }
    _QUOTE_CACHE[cache_key] = (now, out)
    return out


_CG_LIST: list[dict] = []
_CG_LIST_TIME: float = 0


def _cg_list() -> list[dict]:
    global _CG_LIST, _CG_LIST_TIME
    now = time.time()
    if _CG_LIST and now - _CG_LIST_TIME < 3600:
        return _CG_LIST
    try:
        r = requests.get("https://api.coingecko.com/api/v3/coins/list", timeout=10)
        if r.status_code == 200:
            _CG_LIST = r.json()
            _CG_LIST_TIME = now
    except Exception as e:
        logging.exception("coingecko list failed: %s", e)
    return _CG_LIST


def _cg_id(sym: str) -> Optional[str]:
    s = sym.lower().strip()
    overrides = {"btc": "bitcoin", "eth": "ethereum", "sol": "solana", "ada": "cardano",
                 "xrp": "ripple", "doge": "dogecoin", "bnb": "binancecoin", "matic": "matic-network",
                 "dot": "polkadot", "ltc": "litecoin", "avax": "avalanche-2", "shib": "shiba-inu"}
    if s in overrides:
        return overrides[s]
    for c in _cg_list():
        if c.get("symbol", "").lower() == s:
            return c["id"]
    return None


def _cg_quote(sym: str) -> dict:
    cache_key = f"cg:{sym}"
    now = time.time()
    cached = _QUOTE_CACHE.get(cache_key)
    if cached and now - cached[0] < _CRYPTO_TTL:
        return cached[1]
    cg_id = _cg_id(sym)
    if not cg_id:
        raise HTTPException(404, f"Unknown crypto {sym}")
    try:
        r = requests.get(
            "https://api.coingecko.com/api/v3/simple/price",
            params={"ids": cg_id, "vs_currencies": "inr", "include_24hr_change": "true"},
            timeout=10,
        )
    except Exception as e:
        if cached:
            return cached[1]
        raise HTTPException(502, f"Crypto provider unreachable: {e}")
    if r.status_code == 429:
        if cached:
            return cached[1]
        raise HTTPException(429, "Crypto provider rate-limit. Try again shortly.")
    if r.status_code != 200:
        if cached:
            return cached[1]
        raise HTTPException(502, "Crypto provider error")
    data = r.json().get(cg_id, {})
    price = float(data.get("inr", 0))
    change_pct = float(data.get("inr_24h_change", 0) or 0)
    prev = price / (1 + change_pct / 100) if change_pct else price
    out = {
        "symbol": sym.upper(),
        "yf_symbol": cg_id,
        "name": cg_id.replace("-", " ").title(),
        "price": round(price, 2),
        "previous_close": round(prev, 2),
        "change": round(price - prev, 2),
        "change_pct": round(change_pct, 2),
        "currency": "INR",
        "market": "crypto",
    }
    _QUOTE_CACHE[cache_key] = (now, out)
    return out


def get_quote(symbol: str, market: str) -> dict:
    if market == "crypto":
        return _cg_quote(symbol)
    # Try Upstox first if authorized; fall back to Yahoo Finance
    try:
        ux = _upstox_quote(symbol)
        if ux:
            return ux
    except Exception as e:
        logging.debug("upstox quote failed for %s, falling back to yfinance: %s", symbol, e)
    return _yf_quote(_yf_symbol(symbol))


# ---------- Upstox (real-time NSE/BSE) ----------
import secrets as _secrets
from urllib.parse import urlencode as _urlencode


_UPSTOX_INSTRUMENT_MAP: dict[str, str] = {}  # symbol -> instrument_key cache


async def _upstox_token() -> Optional[str]:
    if db is None:
        return None
    try:
        doc = await db.upstox_token.find_one({"_id": "main"})
        if not doc:
            return None
        expires_at = doc.get("expires_at")
        if expires_at and expires_at <= datetime.now(timezone.utc):
            return None
        return doc.get("access_token")
    except Exception:
        return None


def _upstox_instrument_key(symbol: str) -> str:
    s = symbol.upper().strip()
    if s in _UPSTOX_INSTRUMENT_MAP:
        return _UPSTOX_INSTRUMENT_MAP[s]
    # Default convention; works for most NSE EQ instruments after instrument-master ingestion
    return f"NSE_EQ|{s}"


def _upstox_quote(symbol: str) -> Optional[dict]:
    """Synchronous quote via Upstox. Returns None if not configured/authorized."""
    if not MONGO_URL:
        return None
    try:
        import pymongo
        sync_client = pymongo.MongoClient(MONGO_URL, serverSelectionTimeoutMS=2000)
        doc = sync_client[DB_NAME].upstox_token.find_one({"_id": "main"})
        sync_client.close()
    except Exception:
        return None
    if not doc:
        return None
    expires_at = doc.get("expires_at")
    if expires_at and expires_at <= datetime.now(timezone.utc):
        return None
    token = doc.get("access_token")
    if not token:
        return None
    key = _upstox_instrument_key(symbol)
    cache_key = f"ux:{key}"
    now = time.time()
    cached = _QUOTE_CACHE.get(cache_key)
    if cached and now - cached[0] < _QUOTE_TTL:
        return cached[1]
    try:
        r = requests.get(
            f"{UPSTOX_BASE}/market-quote/quotes",
            params={"instrument_key": key},
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            timeout=8,
        )
    except Exception:
        return None
    if r.status_code != 200:
        return None
    data = r.json().get("data", {})
    if not data:
        return None
    # data is a dict keyed by something like "NSE_EQ:RELIANCE"
    first = next(iter(data.values()))
    price = float(first.get("last_price") or 0)
    prev = float(first.get("ohlc", {}).get("close") or first.get("close_price") or price)
    change = price - prev
    change_pct = (change / prev * 100) if prev else 0.0
    out = {
        "symbol": symbol.upper(),
        "yf_symbol": key,
        "name": first.get("symbol") or symbol.upper(),
        "price": round(price, 2),
        "previous_close": round(prev, 2),
        "change": round(change, 2),
        "change_pct": round(change_pct, 2),
        "currency": "INR",
        "market": "stock",
        "source": "upstox",
    }
    _QUOTE_CACHE[cache_key] = (now, out)
    return out


@api.get("/upstox/status")
async def upstox_status():
    if not UPSTOX_KEY:
        return {"configured": False, "authorized": False, "reason": "not_configured"}
    doc = await db.upstox_token.find_one({"_id": "main"})
    if not doc:
        return {"configured": True, "authorized": False, "reason": "not_logged_in"}
    expires_at = doc.get("expires_at")
    now = datetime.now(timezone.utc)
    if expires_at and expires_at <= now:
        return {"configured": True, "authorized": False, "reason": "expired", "expired_at": expires_at.isoformat()}
    remaining = int((expires_at - now).total_seconds()) if expires_at else None
    return {"configured": True, "authorized": True, "expires_at": expires_at.isoformat() if expires_at else None, "remaining_seconds": remaining}


@api.get("/upstox/authorize-url")
async def upstox_authorize_url():
    if not UPSTOX_KEY or not UPSTOX_REDIRECT:
        raise HTTPException(400, "Upstox not configured. Set UPSTOX_API_KEY and UPSTOX_REDIRECT_URI.")
    state = _secrets.token_urlsafe(16)
    await db.upstox_state.insert_one({"_id": state, "created_at": datetime.now(timezone.utc)})
    params = {
        "response_type": "code",
        "client_id": UPSTOX_KEY,
        "redirect_uri": UPSTOX_REDIRECT,
        "state": state,
    }
    return {"auth_url": f"https://api.upstox.com/v2/login/authorization/dialog?{_urlencode(params)}", "state": state}


@api.get("/upstox/callback")
async def upstox_callback(code: str, state: str):
    valid_state = await db.upstox_state.find_one({"_id": state})
    if not valid_state:
        raise HTTPException(400, "Invalid state")
    await db.upstox_state.delete_one({"_id": state})
    try:
        r = requests.post(
            f"{UPSTOX_BASE}/login/authorization/token",
            data={
                "code": code,
                "client_id": UPSTOX_KEY,
                "client_secret": UPSTOX_SECRET,
                "redirect_uri": UPSTOX_REDIRECT,
                "grant_type": "authorization_code",
            },
            headers={"accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"},
            timeout=15,
        )
    except Exception as e:
        raise HTTPException(502, f"Upstox unreachable: {e}")
    if r.status_code != 200:
        raise HTTPException(502, f"Upstox token exchange failed: {r.text[:200]}")
    payload = r.json()
    access_token = payload.get("access_token")
    if not access_token:
        raise HTTPException(502, "No access_token returned")
    # Upstox tokens expire at 3:30 AM IST next day
    from zoneinfo import ZoneInfo
    ist = ZoneInfo("Asia/Kolkata")
    now_ist = datetime.now(ist)
    cutoff = now_ist.replace(hour=3, minute=30, second=0, microsecond=0)
    if now_ist >= cutoff:
        cutoff = cutoff + timedelta(days=1)
    expires_at = cutoff.astimezone(timezone.utc)
    await db.upstox_token.replace_one(
        {"_id": "main"},
        {
            "_id": "main",
            "access_token": access_token,
            "expires_at": expires_at,
            "created_at": datetime.now(timezone.utc),
        },
        upsert=True,
    )
    return {"ok": True, "expires_at": expires_at.isoformat(), "message": "Upstox connected. Real-time NSE data is now active."}


# ---------- Auth routes ----------
@api.post("/auth/register", response_model=TokenOut, status_code=201)
async def register(payload: RegisterIn):
    email = payload.email.lower()
    existing = await db.users.find_one({"email": email})
    if existing:
        raise HTTPException(400, "Email already registered")
    uid = str(uuid.uuid4())
    # MVP: every new signup gets ₹1,00,000 demo cash automatically (free tier)
    doc = {
        "_id": uid,
        "email": email,
        "name": payload.name,
        "password_hash": hash_pw(payload.password),
        "wallet_balance": 100000.0,
        "subscription_active": True,
        "plan": "free_starter",
        "total_realized_pnl": 0.0,
        "created_at": datetime.now(timezone.utc),
    }
    await db.users.insert_one(doc)
    return TokenOut(access_token=make_token(uid), user=to_public(doc))


@api.post("/auth/login", response_model=TokenOut)
async def login(payload: LoginIn):
    user = await db.users.find_one({"email": payload.email.lower()})
    if not user or not verify_pw(payload.password, user["password_hash"]):
        raise HTTPException(401, "Invalid email or password")
    return TokenOut(access_token=make_token(user["_id"]), user=to_public(user))


@api.get("/auth/me", response_model=UserPublic)
async def me(user: dict = Depends(current_user)):
    return to_public(user)


# ---------- Market routes ----------
@api.get("/market/overview")
async def market_overview():
    overview = []
    # Nifty 50, Sensex, Bank Nifty
    for sym in ["^NSEI", "^BSESN", "^NSEBANK"]:
        try:
            q = _yf_quote(sym)
            q["display_name"] = {"^NSEI": "NIFTY 50", "^BSESN": "SENSEX", "^NSEBANK": "BANK NIFTY"}[sym]
            q["category"] = "index"
            overview.append(q)
        except Exception as e:
            logging.warning("overview yf err %s: %s", sym, e)
    # Top crypto
    for sym in ["BTC", "ETH", "SOL"]:
        try:
            q = _cg_quote(sym)
            q["display_name"] = q["name"]
            q["category"] = "crypto"
            overview.append(q)
        except Exception as e:
            logging.warning("overview cg err %s: %s", sym, e)
    return overview


@api.get("/market/quote")
async def market_quote(symbol: str, market: str = "stock"):
    return get_quote(symbol, market)


@api.get("/market/search")
async def market_search(q: str = Query(min_length=1), market: str = "stock"):
    q_low = q.lower().strip()
    results: list[dict] = []
    if market == "stock":
        # Curated NSE stock list for search (top Indian stocks)
        for s in CURATED_STOCKS:
            if q_low in s["symbol"].lower() or q_low in s["name"].lower():
                results.append(s)
                if len(results) >= 25:
                    break
    else:
        for c in _cg_list()[:5000]:
            if c.get("symbol", "").lower() == q_low or q_low in c.get("name", "").lower() or q_low in c.get("id", "").lower():
                results.append({"symbol": c["symbol"].upper(), "name": c["name"], "market": "crypto", "id": c["id"]})
                if len(results) >= 25:
                    break
    return results


@api.get("/market/history")
async def market_history(symbol: str, market: str = "stock", range: str = "1mo"):
    """range: 1d, 5d, 1mo, 3mo, 6mo, 1y, 5y"""
    cache_key = f"hist:{market}:{symbol}:{range}"
    now = time.time()
    cached = _QUOTE_CACHE.get(cache_key)
    # cache history for 5 minutes
    if cached and now - cached[0] < 300:
        return cached[1]
    if market == "crypto":
        cg_id = _cg_id(symbol)
        if not cg_id:
            raise HTTPException(404, "Unknown crypto")
        days_map = {"1d": 1, "5d": 7, "1mo": 30, "3mo": 90, "6mo": 180, "1y": 365, "5y": 1825}
        days = days_map.get(range, 30)
        try:
            r = requests.get(
                f"https://api.coingecko.com/api/v3/coins/{cg_id}/market_chart",
                params={"vs_currency": "inr", "days": days},
                timeout=15,
            )
        except Exception as e:
            if cached:
                return cached[1]
            raise HTTPException(502, f"History provider unreachable: {e}")
        if r.status_code != 200:
            if cached:
                return cached[1]
            if r.status_code == 429:
                raise HTTPException(429, "History provider rate-limit. Try again shortly.")
            raise HTTPException(502, "History provider error")
        points = r.json().get("prices", [])
        step = max(1, len(points) // 60)
        out = {"symbol": symbol.upper(), "points": [{"t": p[0], "v": round(p[1], 2)} for p in points[::step]]}
        _QUOTE_CACHE[cache_key] = (now, out)
        return out
    sym = _yf_symbol(symbol)
    period_map = {"1d": "1d", "5d": "5d", "1mo": "1mo", "3mo": "3mo", "6mo": "6mo", "1y": "1y", "5y": "5y"}
    interval_map = {"1d": "5m", "5d": "30m", "1mo": "1d", "3mo": "1d", "6mo": "1d", "1y": "1d", "5y": "1wk"}
    period = period_map.get(range, "1mo")
    interval = interval_map.get(range, "1d")
    hist = yf.Ticker(sym).history(period=period, interval=interval)
    if hist.empty:
        return {"symbol": symbol.upper(), "points": []}
    points = []
    for idx, row in hist.iterrows():
        try:
            ts = int(idx.timestamp() * 1000)
            points.append({"t": ts, "v": round(float(row["Close"]), 2)})
        except Exception:
            continue
    return {"symbol": symbol.upper(), "points": points}


# ---------- Trading routes ----------
@api.post("/trade/order")
async def place_order(payload: OrderIn, user: dict = Depends(current_user)):
    if payload.side not in ("buy", "sell"):
        raise HTTPException(400, "Side must be buy/sell")
    if payload.market not in ("stock", "crypto"):
        raise HTTPException(400, "Market must be stock/crypto")
    quote = get_quote(payload.symbol, payload.market)
    price = quote["price"]
    total = price * payload.quantity
    sym = quote["symbol"]
    holding_filter = {"user_id": user["_id"], "symbol": sym, "market": payload.market}
    holding = await db.holdings.find_one(holding_filter)
    if payload.side == "buy":
        if user["wallet_balance"] < total:
            raise HTTPException(400, f"Insufficient wallet balance. Need ₹{total:,.2f}")
        new_bal = user["wallet_balance"] - total
        if holding:
            new_qty = holding["quantity"] + payload.quantity
            new_avg = (holding["avg_price"] * holding["quantity"] + total) / new_qty
            await db.holdings.update_one(holding_filter, {"$set": {"quantity": new_qty, "avg_price": new_avg, "name": quote["name"]}})
        else:
            await db.holdings.insert_one({
                **holding_filter,
                "quantity": payload.quantity,
                "avg_price": price,
                "name": quote["name"],
                "created_at": datetime.now(timezone.utc),
            })
        realized = 0.0
    else:  # sell
        if not holding or holding["quantity"] < payload.quantity:
            raise HTTPException(400, "Insufficient holdings to sell")
        realized = (price - holding["avg_price"]) * payload.quantity
        new_bal = user["wallet_balance"] + total
        new_qty = holding["quantity"] - payload.quantity
        if new_qty <= 0.0000001:
            await db.holdings.delete_one(holding_filter)
        else:
            await db.holdings.update_one(holding_filter, {"$set": {"quantity": new_qty}})
        await db.users.update_one(
            {"_id": user["_id"]},
            {"$inc": {"total_realized_pnl": realized}},
        )
    await db.users.update_one({"_id": user["_id"]}, {"$set": {"wallet_balance": new_bal}})
    order = {
        "_id": str(uuid.uuid4()),
        "user_id": user["_id"],
        "symbol": sym,
        "name": quote["name"],
        "market": payload.market,
        "side": payload.side,
        "quantity": payload.quantity,
        "price": price,
        "total": total,
        "realized_pnl": realized,
        "created_at": datetime.now(timezone.utc),
    }
    await db.orders.insert_one(order)
    return {
        "order_id": order["_id"],
        "symbol": sym,
        "side": payload.side,
        "quantity": payload.quantity,
        "price": price,
        "total": total,
        "realized_pnl": realized,
        "new_balance": new_bal,
    }


@api.get("/portfolio")
async def get_portfolio(user: dict = Depends(current_user)):
    holdings_cursor = db.holdings.find({"user_id": user["_id"]}, {"_id": 0})
    holdings_raw = await holdings_cursor.to_list(500)
    holdings = []
    invested_value = 0.0
    current_value = 0.0
    for h in holdings_raw:
        try:
            q = get_quote(h["symbol"], h["market"])
            cur_price = q["price"]
        except Exception:
            cur_price = h["avg_price"]
        invested = h["avg_price"] * h["quantity"]
        current = cur_price * h["quantity"]
        invested_value += invested
        current_value += current
        holdings.append({
            "symbol": h["symbol"],
            "name": h.get("name", h["symbol"]),
            "market": h["market"],
            "quantity": h["quantity"],
            "avg_price": h["avg_price"],
            "current_price": cur_price,
            "invested": round(invested, 2),
            "current": round(current, 2),
            "pnl": round(current - invested, 2),
            "pnl_pct": round((current - invested) / invested * 100, 2) if invested else 0.0,
        })
    holdings.sort(key=lambda x: x["current"], reverse=True)
    return {
        "wallet_balance": user["wallet_balance"],
        "invested_value": round(invested_value, 2),
        "current_value": round(current_value, 2),
        "unrealized_pnl": round(current_value - invested_value, 2),
        "unrealized_pnl_pct": round((current_value - invested_value) / invested_value * 100, 2) if invested_value else 0.0,
        "realized_pnl": round(user.get("total_realized_pnl", 0.0), 2),
        "holdings": holdings,
    }


@api.get("/orders")
async def list_orders(user: dict = Depends(current_user), limit: int = 50):
    cursor = db.orders.find({"user_id": user["_id"]}, {"_id": 0, "user_id": 0}).sort("created_at", -1).limit(limit)
    return await cursor.to_list(limit)


@api.get("/analytics")
async def analytics(user: dict = Depends(current_user)):
    orders = await db.orders.find({"user_id": user["_id"]}, {"_id": 0, "user_id": 0}).to_list(1000)
    sells = [o for o in orders if o["side"] == "sell"]
    wins = [o for o in sells if o.get("realized_pnl", 0) > 0]
    losses = [o for o in sells if o.get("realized_pnl", 0) < 0]
    total_trades = len(orders)
    win_rate = (len(wins) / len(sells) * 100) if sells else 0.0
    best = max(sells, key=lambda o: o.get("realized_pnl", 0), default=None)
    worst = min(sells, key=lambda o: o.get("realized_pnl", 0), default=None)
    return {
        "total_trades": total_trades,
        "buy_trades": sum(1 for o in orders if o["side"] == "buy"),
        "sell_trades": len(sells),
        "win_rate": round(win_rate, 1),
        "winning_trades": len(wins),
        "losing_trades": len(losses),
        "realized_pnl": round(user.get("total_realized_pnl", 0.0), 2),
        "best_trade": best,
        "worst_trade": worst,
    }


# ---------- Watchlist ----------
@api.get("/watchlist")
async def get_watchlist(user: dict = Depends(current_user)):
    items = await db.watchlist.find({"user_id": user["_id"]}, {"_id": 0, "user_id": 0}).to_list(100)
    out = []
    for it in items:
        try:
            q = get_quote(it["symbol"], it["market"])
            out.append({**it, **q})
        except Exception:
            out.append(it)
    return out


@api.post("/watchlist")
async def add_watchlist(payload: WatchlistIn, user: dict = Depends(current_user)):
    sym = payload.symbol.upper()
    try:
        await db.watchlist.insert_one({"user_id": user["_id"], "symbol": sym, "market": payload.market, "created_at": datetime.now(timezone.utc)})
    except Exception:
        pass
    return {"ok": True}


@api.delete("/watchlist")
async def remove_watchlist(symbol: str, market: str, user: dict = Depends(current_user)):
    await db.watchlist.delete_one({"user_id": user["_id"], "symbol": symbol.upper(), "market": market})
    return {"ok": True}


# ---------- Leaderboard ----------
@api.get("/leaderboard")
async def leaderboard(user: dict = Depends(current_user)):
    users = await db.users.find({}, {"_id": 1, "name": 1, "total_realized_pnl": 1, "wallet_balance": 1}).to_list(500)
    out = []
    for u in users:
        # We compute unrealized too if cheap, else just realized
        out.append({
            "user_id": u["_id"],
            "name": u.get("name", "Trader"),
            "realized_pnl": round(u.get("total_realized_pnl", 0.0), 2),
            "is_self": u["_id"] == user["_id"],
        })
    out.sort(key=lambda x: x["realized_pnl"], reverse=True)
    for i, row in enumerate(out):
        row["rank"] = i + 1
    return out[:50]


# ---------- What-If ----------
@api.post("/whatif")
async def what_if(payload: WhatIfIn):
    # Compute approx historical price
    target_date = datetime.now(timezone.utc) - timedelta(days=int(payload.years_ago * 365))
    if payload.market == "crypto":
        cg_id = _cg_id(payload.symbol)
        if not cg_id:
            raise HTTPException(404, "Unknown crypto")
        days = int(payload.years_ago * 365)
        r = requests.get(
            f"https://api.coingecko.com/api/v3/coins/{cg_id}/market_chart",
            params={"vs_currency": "inr", "days": days},
            timeout=15,
        )
        prices = r.json().get("prices", [])
        if not prices:
            raise HTTPException(404, "No history")
        old_price = prices[0][1]
        new_price = prices[-1][1]
    else:
        sym = _yf_symbol(payload.symbol)
        period = "5y" if payload.years_ago > 1 else "1y"
        hist = yf.Ticker(sym).history(period=period)
        if hist.empty:
            raise HTTPException(404, "No history")
        old_price = float(hist["Close"].iloc[0])
        new_price = float(hist["Close"].iloc[-1])
    units = payload.amount / old_price
    current_value = units * new_price
    pnl = current_value - payload.amount
    pnl_pct = pnl / payload.amount * 100
    return {
        "symbol": payload.symbol.upper(),
        "amount_invested": payload.amount,
        "purchase_date": target_date.isoformat(),
        "purchase_price": round(old_price, 2),
        "current_price": round(new_price, 2),
        "units": round(units, 4),
        "current_value": round(current_value, 2),
        "pnl": round(pnl, 2),
        "pnl_pct": round(pnl_pct, 2),
    }


# ---------- Loss Autopsy (rule-based) ----------
@api.get("/autopsy")
async def loss_autopsy(user: dict = Depends(current_user)):
    """Analyse worst losing trades + current losing holdings with educational tips."""
    # Worst losing closed trades
    sells = await db.orders.find({"user_id": user["_id"], "side": "sell", "realized_pnl": {"$lt": 0}}).sort("realized_pnl", 1).to_list(20)
    # Current losing holdings
    portfolio = await get_portfolio(user=user)
    losing_holdings = [h for h in portfolio["holdings"] if h["pnl"] < 0]
    losing_holdings.sort(key=lambda x: x["pnl"])
    insights = []
    for h in losing_holdings[:5]:
        tip = _autopsy_tip(h["pnl_pct"], h["market"])
        insights.append({
            "type": "open_loss",
            "symbol": h["symbol"],
            "name": h["name"],
            "loss": h["pnl"],
            "loss_pct": h["pnl_pct"],
            "tip": tip,
        })
    for s in sells[:5]:
        loss_pct = (s["realized_pnl"] / (s["price"] * s["quantity"])) * 100
        insights.append({
            "type": "closed_loss",
            "symbol": s["symbol"],
            "name": s.get("name", s["symbol"]),
            "loss": round(s["realized_pnl"], 2),
            "loss_pct": round(loss_pct, 2),
            "tip": _autopsy_tip(loss_pct, s["market"]),
        })
    if not insights:
        return {
            "summary": "No losing positions found. You're on fire, Titan! Keep your risk discipline tight.",
            "insights": [],
        }
    total_loss = sum(i["loss"] for i in insights)
    return {
        "summary": f"You have ₹{abs(total_loss):,.0f} in unresolved losses across {len(insights)} positions. Read the lessons below.",
        "insights": insights,
    }


def _autopsy_tip(loss_pct: float, market: str) -> str:
    if loss_pct < -25:
        return "Severe drawdown. Consider whether your thesis still holds. Cut losses if the fundamentals broke."
    if loss_pct < -10:
        return "Meaningful loss. Review your entry — did you average up or chase momentum? Set a stop-loss next time."
    if market == "crypto":
        return "Crypto is highly volatile. Size your position so a 30% drawdown is survivable."
    return "Small loss. Tag the reason: news, sector rotation, or noise. Don't average down without conviction."


# ---------- Subscription (Razorpay - MOCKED, kept for future) ----------
# Plan tiers — kept on backend for when payment goes live
PLANS = {
    "titan_1l": {"name": "Titan Starter", "price": 199, "cash": 100000.0},
    "titan_5l": {"name": "Titan Pro", "price": 899, "cash": 500000.0},
    "titan_10l": {"name": "Titan Elite", "price": 1499, "cash": 1000000.0},
}


@api.get("/subscription/plans")
async def list_plans():
    return [{"id": k, **v} for k, v in PLANS.items()]


class SubscribeIn(BaseModel):
    plan_id: str = "titan_1l"
    payment_id: Optional[str] = None
    order_id: Optional[str] = None
    signature: Optional[str] = None


@api.post("/subscription/create-order")
async def create_subscription_order(plan_id: str = "titan_1l", user: dict = Depends(current_user)):
    """Returns a (mock) Razorpay order for the given plan. Real keys would create actual order."""
    plan = PLANS.get(plan_id)
    if not plan:
        raise HTTPException(400, "Unknown plan")
    order = {
        "id": f"order_mock_{uuid.uuid4().hex[:12]}",
        "amount": plan["price"] * 100,  # paise
        "currency": "INR",
        "plan_id": plan_id,
        "plan": plan,
        "key_id": os.environ.get("RAZORPAY_KEY_ID", "rzp_test_MOCK_KEY"),
        "is_mock": not bool(os.environ.get("RAZORPAY_KEY_ID")),
    }
    return order


@api.post("/subscription/activate")
async def activate_subscription(payload: SubscribeIn, user: dict = Depends(current_user)):
    """Top up wallet for the selected plan. MOCKED Razorpay — credits cash without real verification."""
    plan = PLANS.get(payload.plan_id)
    if not plan:
        raise HTTPException(400, "Unknown plan")
    new_balance = user["wallet_balance"] + plan["cash"]
    await db.users.update_one(
        {"_id": user["_id"]},
        {"$set": {
            "subscription_active": True,
            "wallet_balance": new_balance,
            "plan": payload.plan_id,
            "subscribed_at": datetime.now(timezone.utc),
        }},
    )
    await db.orders.insert_one({
        "_id": str(uuid.uuid4()),
        "user_id": user["_id"],
        "symbol": plan["name"].upper().replace(" ", "_"),
        "name": f"{plan['name']} Top-up",
        "market": "subscription",
        "side": "credit",
        "quantity": 1,
        "price": float(plan["price"]),
        "total": float(plan["price"]),
        "realized_pnl": 0.0,
        "created_at": datetime.now(timezone.utc),
    })
    return {"ok": True, "new_balance": new_balance, "credited": plan["cash"], "message": f"{plan['name']} activated. ₹{int(plan['cash']):,} credited."}


# ---------- Curated stock list ----------
CURATED_STOCKS = [
    {"symbol": "RELIANCE", "name": "Reliance Industries", "market": "stock"},
    {"symbol": "TCS", "name": "Tata Consultancy Services", "market": "stock"},
    {"symbol": "HDFCBANK", "name": "HDFC Bank", "market": "stock"},
    {"symbol": "INFY", "name": "Infosys", "market": "stock"},
    {"symbol": "ICICIBANK", "name": "ICICI Bank", "market": "stock"},
    {"symbol": "HINDUNILVR", "name": "Hindustan Unilever", "market": "stock"},
    {"symbol": "ITC", "name": "ITC Limited", "market": "stock"},
    {"symbol": "SBIN", "name": "State Bank of India", "market": "stock"},
    {"symbol": "BHARTIARTL", "name": "Bharti Airtel", "market": "stock"},
    {"symbol": "KOTAKBANK", "name": "Kotak Mahindra Bank", "market": "stock"},
    {"symbol": "LT", "name": "Larsen & Toubro", "market": "stock"},
    {"symbol": "AXISBANK", "name": "Axis Bank", "market": "stock"},
    {"symbol": "ASIANPAINT", "name": "Asian Paints", "market": "stock"},
    {"symbol": "MARUTI", "name": "Maruti Suzuki", "market": "stock"},
    {"symbol": "BAJFINANCE", "name": "Bajaj Finance", "market": "stock"},
    {"symbol": "WIPRO", "name": "Wipro", "market": "stock"},
    {"symbol": "HCLTECH", "name": "HCL Technologies", "market": "stock"},
    {"symbol": "ULTRACEMCO", "name": "UltraTech Cement", "market": "stock"},
    {"symbol": "TITAN", "name": "Titan Company", "market": "stock"},
    {"symbol": "SUNPHARMA", "name": "Sun Pharmaceutical", "market": "stock"},
    {"symbol": "NESTLEIND", "name": "Nestle India", "market": "stock"},
    {"symbol": "TATAMOTORS", "name": "Tata Motors", "market": "stock"},
    {"symbol": "ADANIENT", "name": "Adani Enterprises", "market": "stock"},
    {"symbol": "ADANIPORTS", "name": "Adani Ports", "market": "stock"},
    {"symbol": "POWERGRID", "name": "Power Grid Corporation", "market": "stock"},
    {"symbol": "NTPC", "name": "NTPC", "market": "stock"},
    {"symbol": "ONGC", "name": "Oil & Natural Gas Corp", "market": "stock"},
    {"symbol": "COALINDIA", "name": "Coal India", "market": "stock"},
    {"symbol": "JSWSTEEL", "name": "JSW Steel", "market": "stock"},
    {"symbol": "TATASTEEL", "name": "Tata Steel", "market": "stock"},
    {"symbol": "M&M", "name": "Mahindra & Mahindra", "market": "stock"},
    {"symbol": "BAJAJFINSV", "name": "Bajaj Finserv", "market": "stock"},
    {"symbol": "INDUSINDBK", "name": "IndusInd Bank", "market": "stock"},
    {"symbol": "TECHM", "name": "Tech Mahindra", "market": "stock"},
    {"symbol": "DRREDDY", "name": "Dr. Reddy's Labs", "market": "stock"},
    {"symbol": "CIPLA", "name": "Cipla", "market": "stock"},
    {"symbol": "GRASIM", "name": "Grasim Industries", "market": "stock"},
    {"symbol": "BRITANNIA", "name": "Britannia Industries", "market": "stock"},
    {"symbol": "HEROMOTOCO", "name": "Hero MotoCorp", "market": "stock"},
    {"symbol": "EICHERMOT", "name": "Eicher Motors", "market": "stock"},
    {"symbol": "BAJAJ-AUTO", "name": "Bajaj Auto", "market": "stock"},
    {"symbol": "DIVISLAB", "name": "Divi's Laboratories", "market": "stock"},
    {"symbol": "HDFCLIFE", "name": "HDFC Life Insurance", "market": "stock"},
    {"symbol": "SBILIFE", "name": "SBI Life Insurance", "market": "stock"},
    {"symbol": "TATACONSUM", "name": "Tata Consumer Products", "market": "stock"},
    {"symbol": "PIDILITIND", "name": "Pidilite Industries", "market": "stock"},
    {"symbol": "DMART", "name": "Avenue Supermarts", "market": "stock"},
    {"symbol": "ZOMATO", "name": "Zomato", "market": "stock"},
    {"symbol": "PAYTM", "name": "One97 Communications (Paytm)", "market": "stock"},
    {"symbol": "IRCTC", "name": "IRCTC", "market": "stock"},
]


# ---------- Health ----------
@api.get("/")
async def root():
    return {"message": "Trading Titans API", "status": "ok"}


app.include_router(api)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
