import json
import pathlib
import urllib.parse
import urllib.request
from collections import Counter

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

print("="*80)
print("ANALYSIS OF PAYMENT_ORDERS & SUBSCRIPTIONS")
print("="*80)

orders = get("payment_orders?select=*&order=created_at.desc")
print(f"Total payment_orders initiated: {len(orders)}")

# Breakdown by status
status_counts = Counter(o.get("status") for o in orders)
print(f"Status breakdown: {dict(status_counts)}")

# Breakdown by kind (topup vs subscription)
kind_counts = Counter(o.get("kind") for o in orders)
print(f"Kind breakdown: {dict(kind_counts)}")

# Breakdown by SKU
sku_counts = Counter(o.get("sku") for o in orders)
print(f"SKU breakdown: {dict(sku_counts)}")

# Successful payments
successful = [o for o in orders if o.get("status") == "paid" or o.get("paid_at")]
print(f"\nSuccessful paid orders: {len(successful)}")
for s in successful:
    print(f"  ID: {s['id']}, SKU: {s['sku']}, Amount: {s['amount_paise']/100} INR, User: {s['user_id'][:8]}, PaidAt: {s.get('paid_at')}")

# Failed or Abandoned orders ("created" but never paid)
abandoned = [o for o in orders if o.get("status") == "created" and not o.get("paid_at")]
print(f"\nAbandoned orders (initiated checkout but never paid): {len(abandoned)}")

# Unique users who tried to buy
unique_attempt_users = set(o["user_id"] for o in orders)
print(f"Unique users who initiated at least 1 checkout: {len(unique_attempt_users)}")

# Top users by attempts
user_attempts = Counter(o["user_id"] for o in orders)
print("\nTop 5 users with most checkout attempts:")
for uid, count in user_attempts.most_common(5):
    prof = get(f"profiles?id=eq.{uid}&select=name,email")
    pname = prof[0]["name"] if prof else "Unknown"
    pemail = prof[0]["email"] if prof else "Unknown"
    print(f"  {pname} ({pemail}): {count} attempts")

print("\n--- PAYMENT_EVENTS TABLE ---")
events = get("payment_events?select=*&order=created_at.desc&limit=20")
print(f"Total payment_events sample count: {len(events)}")
for e in events:
    print(f"  Event: {e.get('event_type') or e.get('type') or e.get('event')}, Created: {e.get('created_at')}")
    if 'payload' in e:
        # print snippet
        pstr = str(e['payload'])[:120]
        print(f"    Payload: {pstr}")

print("\n--- SUBSCRIPTIONS TABLE ---")
subs = get("subscriptions?select=*&order=created_at.desc")
print(f"Total subscriptions in table: {len(subs)}")
sub_status = Counter(s.get("status") for s in subs)
print(f"Subscription statuses: {dict(sub_status)}")
for s in subs:
    print(f"  ID: {s['id']}, SKU: {s['sku']}, Tier: {s['tier']}, Status: {s['status']}, Created: {s['created_at']}")
