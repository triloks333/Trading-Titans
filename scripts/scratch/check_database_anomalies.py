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

print("=== CHECKING ALL PROFILES FOR ANOMALIES ===")
profiles = get("profiles?select=id,name,email,wallet_balance,total_realized_pnl")
anomalies = []
for p in profiles:
    wb = float(p.get("wallet_balance") or 0)
    pnl = float(p.get("total_realized_pnl") or 0)
    if wb < -10000 or wb > 1000000000 or abs(pnl) > 10000000:
        anomalies.append(p)

print(f"Found {len(anomalies)} anomalous profiles:")
for a in anomalies:
    print(f"ID: {a['id']}, Name: {a['name']}, Email: {a['email']}, Wallet: {a['wallet_balance']}, Realized PnL: {a['total_realized_pnl']}")

print("\n=== CHECKING ALL ORDERS FOR RIDICULOUS QUANTITIES (>1,000,000) ===")
huge_orders = get("orders?quantity=gt.1000000&select=id,user_id,symbol,side,quantity,price,total,status,created_at")
print(f"Found {len(huge_orders)} huge orders:")
for o in huge_orders:
    print(f"User: {o['user_id'][:8]}, Symbol: {o['symbol']}, Side: {o['side']}, Qty: {o['quantity']}, Status: {o['status']}, Created: {o['created_at']}")
