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

HEAD = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json', 'Content-Type': 'application/json'}

# Check if edit_chat_message RPC exists
req = urllib.request.Request(f'{url}/rest/v1/rpc/edit_chat_message', headers=HEAD, data=json.dumps({'p_message_id': '00000000-0000-0000-0000-000000000000', 'p_new_body': 'test'}).encode('utf-8'))
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        print('RPC response:', r.read())
except urllib.error.HTTPError as e:
    print('HTTP status:', e.code, e.read().decode())
