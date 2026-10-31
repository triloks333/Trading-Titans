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

def req(path: str, method: str = "GET", data=None):
    r = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD, method=method)
    if data is not None:
        r.add_header("Content-Type", "application/json")
        r.data = json.dumps(data).encode("utf-8")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            content = resp.read()
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} on {method} {path}: {e.read().decode('utf-8', errors='ignore')}")
        return None

uid = "068fd8ef-27a2-495d-be98-36dd7958965d"

print("--- PENDING ORDERS ---")
pending = req(f"orders?user_id=eq.{uid}&status=eq.pending")
for p in pending:
    print(f"ID: {p['id']}, Symbol: {p['symbol']}, Side: {p['side']}, Qty: {p['quantity']}, Price: {p['price']}")

print("\n--- HOLDINGS ---")
holdings = req(f"holdings?user_id=eq.{uid}")
for h in holdings:
    print(f"ID: {h.get('id')}, Symbol: {h['symbol']}, Qty: {h['quantity']}")

print("\n--- PROFILE ---")
profile = req(f"profiles?id=eq.{uid}")[0]
print(f"Wallet: {profile.get('wallet_balance')}, Realized PnL: {profile.get('total_realized_pnl')}")
