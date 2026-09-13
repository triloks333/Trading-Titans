"""Read-only dump of one profile's portfolio: holdings, F&O positions, orders.

    python scripts/show_profile_portfolio.py 90a78b3e
    python scripts/show_profile_portfolio.py kapilagarwal991@gmail.com

Accepts a profile id prefix or an email. Read-only: never writes.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"}

if len(sys.argv) < 2:
    sys.exit(__doc__)
needle = sys.argv[1].strip()


def get(path: str):
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def quote(symbol: str, market: str) -> float | None:
    q = urllib.parse.urlencode({"symbol": symbol, "market": market})
    req = urllib.request.Request(
        f"{url}/functions/v1/market-quote?{q}", headers=HEAD
    )
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return float(json.loads(r.read()).get("price") or 0) or None
    except Exception:
        return None


# ── Resolve the profile ────────────────────────────────────────────────────────
COLS = ("id,email,name,wallet_balance,subscription_active,display_currency,"
        "location,created_at,total_realized_pnl,total_xp")

if "@" in needle:
    profiles = get(f"profiles?email=eq.{urllib.parse.quote(needle)}&select={COLS}")
else:
    # PostgREST cannot LIKE a uuid column, so match the prefix client-side.
    profiles = [
        r for r in get(f"profiles?select={COLS}")
        if str(r["id"]).startswith(needle.lower())
    ]
if not profiles:
    sys.exit(f"no profile matched '{needle}'")
if len(profiles) > 1:
    sys.exit(f"'{needle}' matched {len(profiles)} profiles; be more specific")

p = profiles[0]
pid = p["id"]
print(f"profile   : {p['name']}  <{p['email']}>")
print(f"id        : {pid}")
print(f"wallet    : {p['wallet_balance']}  (INR, stored)")
print(f"currency  : {p.get('display_currency')}   location: {p.get('location')}")
print(f"subscribed: {p.get('subscription_active')}")
print(f"joined    : {p.get('created_at')}")

# ── Holdings ──────────────────────────────────────────────────────────────────
holdings = get(f"holdings?user_id=eq.{pid}&select=symbol,market,quantity,avg_price,"
               "native_avg_price,native_currency&order=market,symbol")
print(f"\nHOLDINGS ({len(holdings)})")
if not holdings:
    print("  none")
total_cost = total_value = 0.0
for h in holdings:
    qty = float(h["quantity"] or 0)
    avg = float(h["avg_price"] or 0)
    cost = qty * avg
    ltp = quote(h["symbol"], h["market"])
    value = qty * ltp if ltp else None
    total_cost += cost
    if value:
        total_value += value
    pnl = (value - cost) if value else None
    pct = (pnl / cost * 100) if (pnl is not None and cost) else None
    print(
        f"  {h['symbol']:12s} {h['market']:9s} qty={qty:<12.4f} "
        f"avg={avg:<12.2f} ltp={(ltp if ltp else 0):<12.2f} "
        f"cost={cost:<13.2f} value={(value or 0):<13.2f} "
        f"pnl={(pnl if pnl is not None else 0):<12.2f} "
        f"{('%.2f%%' % pct) if pct is not None else ''}"
    )
    if qty < 0:
        print("      ^ NEGATIVE QUANTITY - structurally invalid (historic oversell)")

if holdings:
    print(f"  {'TOTAL':12s} {'':9s} cost={total_cost:.2f} value={total_value:.2f} "
          f"pnl={total_value - total_cost:.2f}")

# ── F&O ───────────────────────────────────────────────────────────────────────
fo = get(f"fo_positions?user_id=eq.{pid}&select=symbol,instrument_type,option_type,"
         "strike_price,net_qty,avg_entry_price,lot_size,margin_blocked,is_settled,"
         "expiry_date&order=symbol")
open_fo = [f for f in fo if not f.get("is_settled")]
print(f"\nF&O POSITIONS ({len(open_fo)} open, {len(fo) - len(open_fo)} settled)")
for f in open_fo:
    print(f"  {f['symbol']:26s} {f.get('instrument_type',''):7s} "
          f"{f.get('option_type') or '':3s} strike={f.get('strike_price')} "
          f"qty={f.get('net_qty')} lot={f.get('lot_size')} "
          f"avg={f.get('avg_entry_price')} margin={f.get('margin_blocked')} "
          f"expiry={f.get('expiry_date')}")
if not open_fo:
    print("  none open")

# ── Orders ────────────────────────────────────────────────────────────────────
orders = get(f"orders?user_id=eq.{pid}&select=symbol,market,side,order_type,quantity,"
             "price,status,created_at&order=created_at.desc&limit=15")
counts = get(f"orders?user_id=eq.{pid}&select=status")
by_status: dict[str, int] = {}
for o in counts:
    by_status[o["status"]] = by_status.get(o["status"], 0) + 1
print(f"\nORDERS ({len(counts)} total) {by_status}")
for o in orders:
    print(f"  {o['created_at'][:19]}  {o['symbol']:12s} {o['market']:9s} "
          f"{o['side']:4s} {o.get('order_type',''):7s} qty={o['quantity']} "
          f"price={o.get('price')} {o['status']}")

# ── Watchlist ─────────────────────────────────────────────────────────────────
watch = get(f"watchlist?user_id=eq.{pid}&select=symbol,market&order=market,symbol")
print(f"\nWATCHLIST ({len(watch)})")
print("  " + (", ".join(f"{w['symbol']}({w['market']})" for w in watch) or "none"))
