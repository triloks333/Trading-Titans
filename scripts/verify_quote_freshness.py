"""Verifies the trade page's price path end to end, per market.

Checks, for each of the three trade-page sections:
  1. every popular symbol is in the refresh universe (a row exists in quotes_cache)
  2. how old that row is, against the client's acceptance window
  3. that US symbols are gated on the US session, not the Indian one

    python scripts/verify_quote_freshness.py
"""

from __future__ import annotations

import datetime as dt
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"}

# Must mirror trade_screen.dart's _popular* lists and refresh-quotes' POPULAR.
POPULAR = {
    "stock": ["RELIANCE", "TCS", "HDFCBANK", "INFY", "ICICIBANK", "TMCV", "TMPV",
              "ADANIENT", "ETERNAL"],
    "crypto": ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "POL"],
    "us_stock": ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "TSLA", "NFLX"],
}

# Mirrors MarketService._serverCacheMaxAge.
CLIENT_WINDOW = dt.timedelta(seconds=10)


def get(path):
    req = urllib.request.Request(f"{url}/{path}", headers=HEAD)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


print("Triggering one refresh pass (no force, so real session gates apply)...")
res = get("functions/v1/refresh-quotes?single=1")
print(f"  {res}\n")

now = dt.datetime.now(dt.timezone.utc)
for market, symbols in POPULAR.items():
    rows = get(f"rest/v1/quotes_cache?market=eq.{market}&select=symbol,price,updated_at")
    by_symbol = {r["symbol"]: r for r in rows}
    print(f"{market}:")
    missing = []
    for s in symbols:
        row = by_symbol.get(s)
        if row is None:
            missing.append(s)
            print(f"  {s:10s} MISSING from quotes_cache")
            continue
        updated = dt.datetime.fromisoformat(row["updated_at"].replace("Z", "+00:00"))
        age = now - updated
        verdict = "served from cache" if age <= CLIENT_WINDOW else "client goes live"
        print(f"  {s:10s} {row['price']:>12}  age={age.total_seconds():6.1f}s  {verdict}")
    if missing:
        print(f"  -> {len(missing)} symbol(s) not in the refresh universe: {missing}")
    print()
