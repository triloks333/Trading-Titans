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

print("LEADERBOARD ROW:")
lb = get(f"leaderboard?id=eq.{user_id}")
print(json.dumps(lb, indent=2))

print("\nTOP AND BOTTOM PROFILES BY WALLET BALANCE:")
profiles = get("profiles?select=id,name,email,wallet_balance,total_realized_pnl&order=wallet_balance.asc&limit=5")
for p in profiles:
    print(p)
