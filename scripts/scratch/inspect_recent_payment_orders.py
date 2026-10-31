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

HEAD = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Accept": "application/json"
}

def get(path: str):
    r = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            content = resp.read()
            return json.loads(content) if content else []
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} on {path}: {e.read().decode('utf-8', errors='ignore')}")
        return []

print("=== RECENT PAYMENT ORDERS (SINCE SEPT 12) ===")
recent = get("payment_orders?created_at=gte.2026-09-12T00:00:00Z&order=created_at.desc")
print(f"Total attempts since Sept 12: {len(recent)}")

for o in recent:
    ca = o.get("created_at", "")[:19]
    print(f"{ca} | ID: {o['id'][:8]} | User: {o['user_id'][:8]} | SKU: {o['sku']:<14} | Kind: {o['kind']:<12} | Status: {o['status']:<8} | sub_id: {o.get('provider_subscription_id')} | order_id: {o.get('provider_order_id')}")
