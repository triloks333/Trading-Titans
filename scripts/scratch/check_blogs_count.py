import json, pathlib, urllib.request

ROOT = pathlib.Path('.').resolve()
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

req = urllib.request.Request(
    f"{url}/rest/v1/blog_posts?select=slug,title,excerpt,published_at&order=published_at.desc",
    headers={'apikey': key, 'Authorization': f'Bearer {key}'}
)
data = json.loads(urllib.request.urlopen(req).read().decode('utf-8'))
print(f"Total current posts: {len(data)}")
by_market = {}
for p in data:
    exc = p.get('excerpt') or ''
    m = 'unknown'
    if exc.startswith('[market:'):
        m = exc.split(']')[0].replace('[market:', '')
    by_market[m] = by_market.get(m, 0) + 1

print("By market category:", by_market)
