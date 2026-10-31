import json, pathlib, urllib.request

ROOT = pathlib.Path('.').resolve()
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

HEAD = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json', 'Content-Type': 'application/json', 'Prefer': 'return=representation'}
req = urllib.request.Request(f'{url}/rest/v1/profiles?id=eq.bafab9da-751d-4f1e-ad38-bf8251a70c10', headers=HEAD, data=json.dumps({'display_currency': 'INR'}).encode('utf-8'), method='PATCH')
with urllib.request.urlopen(req) as r:
    print('Reverted to INR:', r.status)
