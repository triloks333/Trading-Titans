import urllib.request, json, pathlib
from collections import Counter

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
    with urllib.request.urlopen(r) as resp:
        return json.loads(resp.read())

profiles = get('profiles?select=id,location,country_code,state')
locations = Counter(p.get('location') for p in profiles)
print("Location breakdown:", locations)

orders = get('payment_orders?select=id,currency,user_id,status,sku')
currencies = Counter(o.get('currency') for o in orders)
print("Order Currencies:", currencies)

usd_users = list(set(o['user_id'] for o in orders if o.get('currency') == 'USD'))
print(f"Users with USD orders: {len(usd_users)}")
for uid in usd_users[:10]:
    p = next((x for x in profiles if x['id'] == uid), None)
    print(f"  User {uid[:8]} | loc: {p.get('location') if p else 'N/A'} | country: {p.get('country_code') if p else 'N/A'}")
