"""Live check for US equity support.

Hits the deployed read-path functions and asserts the things that would silently
break US stocks: the ".NS" suffix bug, the hardcoded INR currency, and search
returning crypto for a us_stock query.

Read-only. Safe to run at any time.

    python scripts/verify_us_stocks.py
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_env() -> tuple[str, str]:
    url = key = ""
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith("SUPABASE_URL="):
            url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
        elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
            key = line.split("=", 1)[1].strip().strip('"')
    if not url or not key:
        raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from .env")
    return url, key


URL, KEY = load_env()


def call(path: str) -> object:
    req = urllib.request.Request(
        f"{URL}/functions/v1/{path}",
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return {"__error__": exc.read().decode()[:300], "__status__": exc.code}


failures: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{(' — ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def main() -> int:
    print("market-quote, US equities")
    for symbol in ("AAPL", "MSFT", "NVDA"):
        q = call(f"market-quote?symbol={symbol}&market=us_stock")
        if not isinstance(q, dict) or "__error__" in q:
            check(f"{symbol} quote", False, str(q)[:160])
            continue
        price = q.get("price")
        check(
            f"{symbol} priced",
            isinstance(price, (int, float)) and price > 0,
            f"price={price}",
        )
        check(f"{symbol} currency is USD", q.get("currency") == "USD", f"got {q.get('currency')}")
        check(f"{symbol} market is us_stock", q.get("market") == "us_stock", f"got {q.get('market')}")
        # The old bug: toYahooSymbol appended .NS to everything.
        check(
            f"{symbol} not suffixed with .NS",
            not str(q.get("yf_symbol", "")).endswith(".NS"),
            f"yf_symbol={q.get('yf_symbol')}",
        )
        fx = q.get("fx_rate")
        check(
            f"{symbol} carries a sane USD/INR rate",
            isinstance(fx, (int, float)) and 50 < fx < 150,
            f"fx_rate={fx}",
        )
        if isinstance(price, (int, float)) and isinstance(fx, (int, float)):
            print(f"        {symbol}: ${price:,.2f}  (approx Rs {price * fx:,.0f} at {fx:.2f})")

    print("\nmarket-quote, Indian equities still work")
    q = call("market-quote?symbol=RELIANCE&market=stock")
    if isinstance(q, dict) and "__error__" not in q:
        check("RELIANCE priced", (q.get("price") or 0) > 0, f"price={q.get('price')}")
        check("RELIANCE currency is INR", q.get("currency") == "INR", f"got {q.get('currency')}")
        check("RELIANCE keeps .NS", str(q.get("yf_symbol", "")).endswith(".NS"),
              f"yf_symbol={q.get('yf_symbol')}")
    else:
        check("RELIANCE quote", False, str(q)[:160])

    print("\nmarket-search, us_stock branch")
    hits = call("market-search?q=apple&market=us_stock")
    if isinstance(hits, list):
        symbols = [h.get("symbol") for h in hits if isinstance(h, dict)]
        check("returns results", len(hits) > 0, f"{len(hits)} hits")
        check("AAPL present", "AAPL" in symbols, f"first few: {symbols[:6]}")
        check(
            "all tagged us_stock",
            all(h.get("market") == "us_stock" for h in hits if isinstance(h, dict)),
        )
        check(
            "no Indian listings leaked in",
            not any("." in str(s) for s in symbols),
            f"symbols={symbols[:6]}",
        )
    else:
        check("us_stock search", False, str(hits)[:200])

    print("\nmarket-search, Indian branch unchanged")
    hits = call("market-search?q=reliance&market=stock")
    check("returns Indian results", isinstance(hits, list) and len(hits) > 0,
          f"{len(hits) if isinstance(hits, list) else hits}")

    print("\nmarket-status")
    st = call("market-status")
    if isinstance(st, dict) and "us_stock" in st:
        us = st["us_stock"]
        check("reports a us_stock block", isinstance(us, dict))
        check("open flag is boolean", isinstance(us.get("open"), bool), f"open={us.get('open')}")
        check("dst flag is boolean", isinstance(us.get("dst"), bool), f"dst={us.get('dst')}")
        print(f"        US session now: open={us.get('open')} dst={us.get('dst')} {us.get('ist_hours')}")
        check("nse block still present", isinstance(st.get("nse"), dict))
    else:
        check("market-status us_stock", False, str(st)[:200])

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        return 1
    print("All US stock read-path checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
