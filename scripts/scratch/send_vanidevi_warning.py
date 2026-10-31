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
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def post(path: str, data):
    r = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD, method="POST")
    r.data = json.dumps(data).encode("utf-8")
    with urllib.request.urlopen(r, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))

uid = "068fd8ef-27a2-495d-be98-36dd7958965d"

notif = {
    "user_id": uid,
    "title": "⚠️ Warning: Abnormal Trading Activity Detected",
    "body": "We detected abnormal orders with unrealistic quantities (including 5,000,000,000,000 shares of RELIANCE) on your account. Attempting to exploit order inputs or trading mechanics is strictly prohibited and violates fair usage policies. Your negative balance has been corrected, corrupted holdings cleared, and your demo wallet restored to ₹10,000. Please trade responsibly.",
    "is_read": False,
    "action_type": "wallet",
    "action_data": {
        "cta_label": "View Wallet",
        "cta_route": "wallet"
    }
}

res = post("notifications", notif)
print("Notification sent successfully:")
print(json.dumps(res, indent=2))
