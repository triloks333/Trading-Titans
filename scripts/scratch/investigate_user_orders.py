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

user_id = "068fd8ef-27a2-495d-be98-36dd7958965d"

print("="*80)
print(f"ORDERS FOR USER {user_id}")
print("="*80)

orders = get(f"orders?user_id=eq.{user_id}&order=created_at.desc&limit=50")
for o in orders:
    print(f"Order ID: {o.get('id')}")
    print(f"  Symbol: {o.get('symbol')}, Market: {o.get('market')}, Side: {o.get('side')}, Type: {o.get('order_type')}")
    print(f"  Status: {o.get('status')}, Qty: {o.get('quantity')}, Price: {o.get('price')}, Executed Price: {o.get('executed_price')}")
    print(f"  Created: {o.get('created_at')}, Executed: {o.get('executed_at')}")
    print(f"  Notes/Metadata: {o.get('notes') or o.get('metadata')}")

print("\n" + "="*80)
print(f"HOLDINGS FOR USER {user_id}")
print("="*80)

holdings = get(f"holdings?user_id=eq.{user_id}")
for h in holdings:
    print(f"Holding: {h.get('symbol')} ({h.get('market')})")
    print(f"  Qty: {h.get('quantity')}, Avg Price: {h.get('avg_price')}, Native Avg: {h.get('native_avg_price')}")

print("\n" + "="*80)
print(f"FO POSITIONS FOR USER {user_id}")
print("="*80)

fo_pos = get(f"fo_positions?user_id=eq.{user_id}")
for p in fo_pos:
    print(p)
