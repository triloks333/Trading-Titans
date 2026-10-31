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
print(f"INVESTIGATING USER {user_id}")
print("="*80)

profile = get(f"profiles?id=eq.{user_id}")[0]
print(f"Profile: {json.dumps(profile, indent=2)}")

print("\n--- HOLDINGS ---")
holdings = get(f"holdings?user_id=eq.{user_id}")
print(f"Count: {len(holdings)}")
for h in holdings:
    print(json.dumps(h, indent=2))

print("\n--- F&O POSITIONS ---")
fo_positions = get(f"fo_positions?user_id=eq.{user_id}")
print(f"Count: {len(fo_positions)}")
for p in fo_positions:
    print(json.dumps(p, indent=2))

print("\n--- ORDERS ---")
orders = get(f"orders?user_id=eq.{user_id}&order=created_at.asc")
print(f"Count: {len(orders)}")
for o in orders:
    print(json.dumps(o, indent=2))

print("\n--- FO ORDERS (if table exists) ---")
fo_orders = get(f"fo_orders?user_id=eq.{user_id}&order=created_at.asc")
print(f"Count: {len(fo_orders)}")
for o in fo_orders:
    print(json.dumps(o, indent=2))

print("\n--- WALLET TRANSACTIONS / LEDGER ---")
ledger = get(f"wallet_ledger?user_id=eq.{user_id}&order=created_at.asc")
if not ledger:
    ledger = get(f"wallet_transactions?user_id=eq.{user_id}&order=created_at.asc")
print(f"Count: {len(ledger)}")
for l in ledger:
    print(json.dumps(l, indent=2))

print("\n--- SETTLEMENTS (if any) ---")
settlements = get(f"fo_settlements?user_id=eq.{user_id}&order=created_at.asc")
print(f"Count: {len(settlements)}")
for s in settlements:
    print(json.dumps(s, indent=2))
