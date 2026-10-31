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

orders = get(f"orders?user_id=eq.{user_id}&symbol=eq.RELIANCE")
print(f"RELIANCE orders count: {len(orders)}")
for o in orders:
    print(json.dumps(o, indent=2))

print("\nAll orders with quantity > 100:")
all_orders = get(f"orders?user_id=eq.{user_id}&quantity=gt.100")
for o in all_orders:
    print(f"ID: {o['id']}, Symbol: {o['symbol']}, Side: {o['side']}, Qty: {o['quantity']}, Status: {o['status']}, Type: {o['order_type']}, Price: {o.get('price')}, ExecutedPrice: {o.get('executed_price')}, Created: {o['created_at']}, Executed: {o.get('executed_at')}")
