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

orders = get(f"orders?user_id=eq.{user_id}&order=created_at.asc")
print(f"Total orders: {len(orders)}")

print(f"{'Idx':<4} {'Created At':<24} {'Symbol':<12} {'Side':<5} {'Type':<6} {'Status':<10} {'Qty':<15} {'Price':<10} {'is_exit':<8} {'Total':<15}")
print("-" * 115)

for idx, o in enumerate(orders):
    qty = str(o.get('quantity'))
    if len(qty) > 14:
        qty = f"{float(qty):.2e}"
    price = str(o.get('price'))
    tot = str(o.get('total'))
    if len(tot) > 14:
        tot = f"{float(tot):.2e}"
    print(f"{idx:<4} {o.get('created_at')[:23]:<24} {o.get('symbol'):<12} {o.get('side'):<5} {o.get('order_type'):<6} {o.get('status'):<10} {qty:<15} {price:<10} {str(o.get('is_exit')):<8} {tot:<15}")

