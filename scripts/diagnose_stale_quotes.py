"""Why aren't prices moving?

Compares the live market-quote response against what is sitting in quotes_cache,
and reports how old the cached rows are. The app reads the cache first, so a stale
cache looks like frozen prices even when the upstream feed is fine.

Read-only.

    python scripts/diagnose_stale_quotes.py
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_env() -> tuple[str, str]:
    url = key = ""
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith("SUPABASE_URL="):
            url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
        elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
            key = line.split("=", 1)[1].strip().strip('"')
    return url, key


URL, KEY = load_env()
HEAD = {"apikey": KEY, "Authorization": f"Bearer {KEY}"}


def get(path: str):
    req = urllib.request.Request(f"{URL}/{path}", headers=HEAD)
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return {"__error__": exc.read().decode()[:300], "__status__": exc.code}
    except Exception as exc:
        return {"__error__": f"{type(exc).__name__}: {exc}"}


def age(ts: str | None) -> str:
    if not ts:
        return "never"
    try:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return f"unparseable ({ts})"
    secs = (datetime.now(timezone.utc) - t).total_seconds()
    if secs < 120:
        return f"{secs:.0f}s ago"
    if secs < 7200:
        return f"{secs / 60:.0f}m ago"
    return f"{secs / 3600:.1f}h ago"


def main() -> int:
    print("=== live upstream (market-quote) ===")
    live: dict[str, float] = {}
    for symbol, market in [("ETH", "crypto"), ("BTC", "crypto"), ("RELIANCE", "stock"), ("AAPL", "us_stock")]:
        q = get(f"functions/v1/market-quote?symbol={symbol}&market={market}")
        if isinstance(q, dict) and "__error__" in q:
            print(f"  {symbol:<9} {market:<9} ERROR {q['__error__'][:90]}")
            continue
        live[f"{symbol}|{market}"] = q.get("price", 0)
        print(f"  {symbol:<9} {market:<9} price={q.get('price')} currency={q.get('currency')} "
              f"source={q.get('source')} change%={q.get('change_pct')}")

    print("\n=== quotes_cache (what the app reads first) ===")
    rows = get("rest/v1/quotes_cache?select=symbol,market,price,updated_at&order=updated_at.desc&limit=12")
    if isinstance(rows, dict):
        print(f"  ERROR {rows.get('__error__', '')[:200]}")
    elif not rows:
        print("  (cache is EMPTY)")
    else:
        for r in rows:
            key = f"{r['symbol']}|{r['market']}"
            drift = ""
            if key in live and r["price"]:
                d = abs(float(r["price"]) - float(live[key])) / float(live[key]) * 100
                drift = f"  drift_vs_live={d:.2f}%"
            print(f"  {r['symbol']:<10} {r['market']:<9} price={r['price']:<12} "
                  f"updated={age(r['updated_at'])}{drift}")

    print("\n=== does the upstream value actually change? ===")
    first = get("functions/v1/market-quote?symbol=ETH&market=crypto")
    time.sleep(20)
    second = get("functions/v1/market-quote?symbol=ETH&market=crypto")
    p1 = first.get("price") if isinstance(first, dict) else None
    p2 = second.get("price") if isinstance(second, dict) else None
    print(f"  ETH now={p1}  after 20s={p2}  {'CHANGED' if p1 != p2 else 'identical'}")
    if p1 == p2:
        print("  (identical over 20s is normal for a thin feed; the cache age above")
        print("   is the more telling number)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
