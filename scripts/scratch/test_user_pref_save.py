import json, pathlib, urllib.request

ROOT = pathlib.Path('.').resolve()
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

# Let's inspect get_user_preferences SQL or call directly
query = """
SELECT p.id, p.display_currency, p.preferred_markets 
FROM public.profiles p 
LIMIT 3;
"""
req = urllib.request.Request(
    f"{url}/rest/v1/profiles?select=id,display_currency,preferred_markets&limit=3",
    headers={'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    print("Sample profiles:", data)
