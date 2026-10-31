import urllib.request
import urllib.parse
import json
import ssl

SUPABASE_URL = "https://bftvimnhpoiuoyryyiff.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak"

ctx = ssl.create_default_context()

def check_all_news():
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/blog_posts?select=id,slug,title,excerpt,cover_url,body_markdown,published_at&order=published_at.desc",
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Accept": "application/json"
        }
    )
    with urllib.request.urlopen(req, context=ctx) as res:
        posts = json.loads(res.read().decode('utf-8'))

    print(f"Total published news/blog posts in Supabase: {len(posts)}")
    print("=" * 80)
    
    by_market = {}
    for p in posts:
        excerpt = p.get("excerpt") or ""
        market = "general"
        if "[market:" in excerpt:
            market = excerpt.split("]")[0].replace("[market:", "").strip().lower()
        by_market.setdefault(market, []).append(p)

    for market, m_posts in by_market.items():
        print(f"\n--- MARKET: {market.upper()} ({len(m_posts)} articles) ---")
        for i, p in enumerate(m_posts, 1):
            body_len = len(p.get("body_markdown") or "")
            cover = "YES" if p.get("cover_url") else "NO"
            print(f"{i}. {p['title']}")
            print(f"   Slug: {p['slug']}")
            print(f"   Cover: {cover} | Body length: {body_len} chars")
            print(f"   Website URL: https://thetradingtitans.com/blog/{p['slug']}")

if __name__ == "__main__":
    check_all_news()
