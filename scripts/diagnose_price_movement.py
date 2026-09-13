"""Measures whether quotes actually move, per market, at the app's poll rate.

The trade list polls market-quote every 4s. If the upstream price only changes
every couple of minutes, the list looks frozen even though the polling works —
so before changing app code, measure the source.

Reports per symbol:
  - how many distinct prices appeared over the sample window
  - the seconds between changes
  - which provider served it (coindcx / binance / yahoo / cache)

    python scripts/diagnose_price_movement.py
"""

from __future__ import annotations

import json
import pathlib
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"}

# One symbol per market: the three sections of the trade page.
TARGETS = [
    ("RELIANCE", "stock"),
    ("TCS", "stock"),
    ("BTC", "crypto"),
    ("ETH", "crypto"),
    ("AAPL", "us_stock"),
]

SAMPLES = 10
INTERVAL = 4  # matches AppConstants.dashboardPricePoll


def quote(symbol: str, market: str):
    req = urllib.request.Request(
        f"{url}/functions/v1/market-quote?symbol={symbol}&market={market}",
        headers=HEAD,
    )
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read())


def rest(path: str):
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


print("=== quotes_cache freshness (the app rejects rows older than 45s) ===")
try:
    rows = rest("quotes_cache?select=symbol,market,price,updated_at"
                "&order=updated_at.desc&limit=8")
    if not rows:
        print("  table is empty")
    for m in rows:
        print(f"  {m['symbol']:12s} {m['market']:9s} {m['price']:>12} "
              f"updated_at={m['updated_at']}")
except Exception as exc:
    print(f"  unavailable: {exc}")

print("\n=== sampling market-quote every "
      f"{INTERVAL}s, {SAMPLES} times ({SAMPLES * INTERVAL}s total) ===")

series: dict[tuple[str, str], list[tuple[float, float, str]]] = {t: [] for t in TARGETS}

for i in range(SAMPLES):
    t0 = time.time()
    for target in TARGETS:
        sym, mkt = target
        try:
            q = quote(sym, mkt)
            series[target].append(
                (time.time(), float(q.get("price") or 0), str(q.get("source")))
            )
        except Exception as exc:
            series[target].append((time.time(), -1.0, f"error:{type(exc).__name__}"))
    elapsed = time.time() - t0
    print(f"  sample {i + 1}/{SAMPLES} took {elapsed:.1f}s")
    if i < SAMPLES - 1:
        time.sleep(max(0, INTERVAL - elapsed))

print()
for (sym, mkt), points in series.items():
    prices = [p for _, p, _ in points]
    sources = {s for _, _, s in points}
    distinct = sorted(set(prices))
    changes = sum(1 for a, b in zip(prices, prices[1:]) if a != b)
    span = points[-1][0] - points[0][0]
    print(f"{sym:10s} {mkt:9s} source={','.join(sorted(sources)):10s} "
          f"distinct={len(distinct):2d} changes={changes:2d} over {span:.0f}s")
    print(f"           values: {prices}")


# ── How often does the cache actually change? ───────────────────────────────────
# The app prefers a quotes_cache row up to 45s old, so the effective refresh rate
# of the trade list is bounded by the refresh-quotes job, not by the 4s poll.
print("\n=== quotes_cache write cadence (watching RELIANCE/BTC updated_at) ===")
watch = ["RELIANCE", "BTC"]
seen: dict[str, set] = {w: set() for w in watch}
stamps: dict[str, list] = {w: [] for w in watch}
for i in range(12):
    for w in watch:
        try:
            rows = rest(f"quotes_cache?symbol=eq.{w}&select=price,updated_at&limit=1")
            if rows:
                seen[w].add((rows[0]["price"], rows[0]["updated_at"]))
                stamps[w].append(rows[0]["updated_at"])
        except Exception:
            pass
    time.sleep(5)

for w in watch:
    uniq = sorted({s for s in stamps[w]})
    print(f"  {w:10s} distinct updated_at over 60s: {len(uniq)}")
    for s in uniq:
        print(f"             {s}")
