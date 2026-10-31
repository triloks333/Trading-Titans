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

ledger = get(f"wallet_transactions?user_id=eq.{user_id}&order=created_at.asc")
print(f"Total ledger entries: {len(ledger)}")

for idx, l in enumerate(ledger):
    amt = l.get('amount')
    bb = l.get('balance_before')
    ba = l.get('balance_after')
    ca = l.get('created_at', '')[:19]
    desc = l.get('description')
    kind = l.get('kind')
    print(f"#{idx:02d} {ca} | {kind:<6} | amt={amt:<18} | before={bb:<18} | after={ba:<18} | {desc}")
