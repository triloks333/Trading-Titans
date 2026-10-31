import json
import pathlib
import urllib.request

ROOT = pathlib.Path('.').resolve()
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

HEAD = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}

req = urllib.request.Request(f'{url}/rest/v1/chat_feed?limit=1', headers=HEAD)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        rows = json.loads(r.read())
        print('chat_feed rows:', rows)
        if rows:
            print('Columns in chat_feed:', list(rows[0].keys()))
except Exception as e:
    print('Error reading chat_feed:', e)
