import json
import pathlib
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"}

def get(path: str):
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} for {path}: {e.read().decode('utf-8', errors='ignore')}")
        return []

def quote(symbol: str, market: str) -> float | None:
    q = urllib.parse.urlencode({"symbol": symbol, "market": market})
    req = urllib.request.Request(f"{url}/functions/v1/market-quote?{q}", headers=HEAD)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return float(json.loads(r.read()).get("price") or 0) or None
    except Exception:
        return None

user_id = "068fd8ef-27a2-495d-be98-36dd7958965d"

profile = get(f"profiles?id=eq.{user_id}")[0]
holdings = get(f"holdings?user_id=eq.{user_id}")

print("PROFILE SUMMARY:")
print(f"Name: {profile.get('name')}")
print(f"Email: {profile.get('email')}")
print(f"Wallet Balance: {profile.get('wallet_balance'):,}")
print(f"Total Realized PnL: {profile.get('total_realized_pnl')}")

print("\nHOLDINGS & UNREALIZED PnL:")
total_invested = 0
total_current_value = 0

for h in holdings:
    sym = h['symbol']
    mkt = h['market']
    qty = float(h['quantity'])
    avg = float(h['avg_price'])
    ltp = quote(sym, mkt) or avg
    
    cost = qty * avg
    curr_val = qty * ltp
    pnl = curr_val - cost
    pnl_pct = (pnl / cost * 100) if cost != 0 else 0
    
    total_invested += cost
    total_current_value += curr_val
    
    print(f"Symbol: {sym} ({mkt})")
    print(f"  Qty: {qty:,}")
    print(f"  Avg Price: INR {avg:.2f}")
    print(f"  LTP: INR {ltp:.2f}")
    print(f"  Cost (Invested): INR {cost:,.2f}")
    print(f"  Current Value: INR {curr_val:,.2f}")
    print(f"  Unrealized PnL: INR {pnl:,.2f} ({pnl_pct:.2f}%)")

print("\nOVERALL PORTFOLIO:")
print(f"Total Invested: INR {total_invested:,.2f}")
print(f"Total Current Value: INR {total_current_value:,.2f}")
tot_unrealized = total_current_value - total_invested
print(f"Total Unrealized PnL: INR {tot_unrealized:,.2f}")
total_portfolio_value = profile.get('wallet_balance') + total_current_value
print(f"Total Portfolio Value (Wallet + Holdings Value): INR {total_portfolio_value:,.2f}")
