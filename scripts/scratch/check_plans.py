import urllib.request, json, pathlib

ROOT = pathlib.Path('.')
env_file = ROOT / '.env'
env = {}
for line in env_file.read_text(encoding='utf-8').splitlines():
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1)
        env[k.strip()] = v.strip().strip('"').strip("'")

url = env['SUPABASE_URL']
key = env['SUPABASE_SERVICE_ROLE_KEY']

req = urllib.request.Request(
    f"{url}/rest/v1/plan_catalogue?select=*&order=sort_order.asc",
    headers={'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}
)

with urllib.request.urlopen(req) as res:
    plans = json.loads(res.read())

print("Found", len(plans), "plans in plan_catalogue:")
for p in plans:
    print(f"SKU: {p.get('sku')} | Title: {p.get('title')} | Price (paise): {p.get('price_paise')} (Rs {p.get('price_paise',0)/100}) | Grant: Rs {p.get('cash_grant')} | Active: {p.get('is_active')} | Kind: {p.get('kind')} | RZP Plan ID: {p.get('razorpay_plan_id')}")
