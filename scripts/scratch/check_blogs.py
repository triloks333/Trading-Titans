import urllib.request, json, pathlib

ROOT = pathlib.Path('.')
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

HEAD = {'apikey': key, 'Authorization': f'Bearer {key}', 'Accept': 'application/json'}
r = urllib.request.Request(f'{url}/rest/v1/blog_posts?select=slug,title,published_at,excerpt&order=published_at.desc', headers=HEAD)
with urllib.request.urlopen(r) as resp:
    posts = json.loads(resp.read())
print(f'Total posts: {len(posts)}')
for i, p in enumerate(posts):
    print(f"{i+1}. {p['slug']} | pub={p['published_at']}")
