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
        return f"Error {e.code}: {e.read().decode('utf-8', errors='ignore')}"

# Search for any payment tables
print("--- CHECKING PAYMENT TABLES ---")
for t in ["payment_orders", "payments", "razorpay_orders", "purchases", "subscriptions", "user_subscriptions", "wallet_recharges", "invoices"]:
    res = get(f"{t}?select=*&limit=5")
    if isinstance(res, list):
        print(f"Table '{t}' exists! Row count in sample: {len(res)}")
        if res:
            print(f"Sample row: {json.dumps(res[0], indent=2)}")
    else:
        print(f"Table '{t}': {res}")
