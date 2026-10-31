import json
import pathlib
import urllib.request
from collections import Counter
from datetime import datetime

ROOT = pathlib.Path('.')
url = key = ""
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

HEAD = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}

def get(path):
    r = urllib.request.Request(f'{url}/rest/v1/{path}', headers=HEAD)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            c = resp.read()
            return json.loads(c) if c else []
    except Exception as e:
        return f"Error: {e}"

print("=== CHECKING TABLES ===")
# 1. Paid orders
paid = get('payment_orders?status=eq.paid&select=*&order=created_at.asc')
print(f"Total PAID orders: {len(paid)}")
for p in paid:
    print(f"  {p.get('created_at')} | {p.get('sku')} | {p.get('kind')} | {p.get('currency')} {p.get('amount_paise')/100} | user: {p.get('user_id')[:8]} | order_id: {p.get('provider_order_id')} | sub_id: {p.get('provider_subscription_id')}")

# 2. Payment events
events = get('payment_events?select=*&order=created_at.desc')
if isinstance(events, list):
    print(f"\nTotal payment_events logged: {len(events)}")
    for ev in events[:15]:
        print(f"  {ev.get('created_at')} | {ev.get('event_type')} | {ev.get('provider_event_id')}")
else:
    print(f"\npayment_events response: {events}")

# 3. All orders timeline
orders = get('payment_orders?select=*&order=created_at.desc')
print(f"\nTotal payment_orders: {len(orders)}")
by_status = Counter(o.get('status') for o in orders)
print(f"Status breakdown: {by_status}")

by_sku = Counter(o.get('sku') for o in orders)
print(f"SKU breakdown: {by_sku}")

# Group by date
by_day = Counter(o.get('created_at')[:10] for o in orders)
print("\nDaily checkout creation activity (last 15 active days):")
for day, count in sorted(by_day.items(), reverse=True)[:15]:
    paid_on_day = sum(1 for o in orders if o.get('created_at')[:10] == day and o.get('status') == 'paid')
    print(f"  {day}: {count} checkouts created, {paid_on_day} paid")

# 4. Check repeat attempts by user
user_attempts = Counter(o.get('user_id') for o in orders)
multi_try_users = {u: c for u, c in user_attempts.items() if c > 1}
print(f"\nUsers with multiple checkout attempts: {len(multi_try_users)} out of {len(user_attempts)} users")
for u, c in sorted(multi_try_users.items(), key=lambda x: x[1], reverse=True)[:10]:
    user_orders = [o for o in orders if o.get('user_id') == u]
    skus = [o.get('sku') for o in user_orders]
    statuses = [o.get('status') for o in user_orders]
    print(f"  User {u[:8]}: {c} attempts | SKUs: {skus} | Statuses: {statuses}")
