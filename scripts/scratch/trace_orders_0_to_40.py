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
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())

user_id = "068fd8ef-27a2-495d-be98-36dd7958965d"

orders = get(f"orders?user_id=eq.{user_id}&order=created_at.asc&limit=40")
for idx, o in enumerate(orders):
    qty = str(o.get('quantity'))
    if len(qty) > 14:
        qty = f"{float(qty):.2e}"
    price = str(o.get('price'))
    tot = str(o.get('total'))
    if len(tot) > 14:
        tot = f"{float(tot):.2e}"
    ca = o.get('created_at', '')[:19]
    ea = (o.get('executed_at') or '')[:19]
    print(f"#{idx:02d} {ca} | ex:{ea} | {o.get('symbol'):<9} | {o.get('side'):<4} | {o.get('order_type'):<6} | {o.get('status'):<9} | qty={qty:<14} | px={price:<8} | exit={str(o.get('is_exit')):<5} | tot={tot}")
