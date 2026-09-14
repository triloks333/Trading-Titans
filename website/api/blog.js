// Vercel Serverless Function — server-rendered blog index at /blog.
//
// Server-rendered for the same reason as the individual post: this site is a Vite
// SPA behind a catch-all rewrite, so a crawler reaching /blog through the SPA would
// find no links to the posts and would never discover them. The index is how the
// posts get crawled at all.
//
// Anon key deliberately, so the published-only RLS policy is what gates the list
// rather than this file's own query.

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SUPABASE_ANON =
  process.env.VITE_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;

const SITE = 'https://thetradingtitans.com';

function esc(value) {
  return String(value ?? '')
    .split('&').join('&amp;')
    .split('<').join('&lt;')
    .split('>').join('&gt;')
    .split('"').join('&quot;')
    .split("'").join('&#39;');
}

function card(post) {
  const date = post.published_at
    ? new Date(post.published_at).toLocaleDateString('en-IN',
        { day: 'numeric', month: 'long', year: 'numeric' })
    : '';
  return `<li class="card">
${post.cover_url
      ? `<a href="/blog/${esc(post.slug)}"><img src="${esc(post.cover_url)}" alt="" loading="lazy"></a>`
      : ''}
<div>
<h2><a href="/blog/${esc(post.slug)}">${esc(post.title)}</a></h2>
<div class="meta">${esc(date)}</div>
${post.excerpt ? `<p>${esc(post.excerpt)}</p>` : ''}
</div>
</li>`;
}

function page(posts) {
  const description =
    'Guides and market explainers from Trading Titans — learn to trade with '
    + 'virtual money before risking your own.';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Blog — Trading Titans</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${SITE}/blog">
<meta property="og:type" content="website">
<meta property="og:title" content="Trading Titans Blog">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${SITE}/blog">
<style>
:root{color-scheme:light}
*{box-sizing:border-box}
body{margin:0;background:#F4F7FB;color:#0B1B2B;
  font:16px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
header,main,footer{max-width:820px;margin:0 auto;padding:0 20px}
header{padding-top:32px}
.brand{font-weight:800;text-decoration:none;color:#0B1B2B;font-size:15px}
h1{font-size:32px;margin:24px 0 28px}
ul{list-style:none;margin:0;padding:0;display:grid;gap:20px}
.card{background:#fff;border:1px solid #DDE7F2;border-radius:12px;overflow:hidden;
  display:grid;grid-template-columns:200px 1fr}
.card>div{padding:16px 18px}
.card img{width:100%;height:100%;object-fit:cover;display:block}
.card h2{font-size:19px;margin:0 0 4px;line-height:1.3}
.card h2 a{color:#0B1B2B;text-decoration:none}
.card p{margin:8px 0 0;color:#334E68;font-size:14px}
.meta{color:#627D98;font-size:12.5px}
.empty{background:#fff;border:1px solid #DDE7F2;border-radius:12px;padding:28px;
  color:#627D98}
footer{padding:48px 20px;color:#627D98;font-size:13px}
a{color:#1A73E8}
@media(max-width:620px){.card{grid-template-columns:1fr}.card img{height:170px}}
</style>
</head>
<body>
<header><a class="brand" href="${SITE}">Trading Titans</a></header>
<main>
<h1>Blog</h1>
${posts.length
      ? `<ul>${posts.map(card).join('\n')}</ul>`
      : '<div class="empty">No posts yet. Check back soon.</div>'}
</main>
<footer>
<a href="${SITE}">Home</a> ·
<a href="${SITE}/app">Open the app</a> ·
<a href="${SITE}/privacy">Privacy</a>
</footer>
</body>
</html>`;
}

export default async function handler(_req, res) {
  if (!SUPABASE_URL || !SUPABASE_ANON) {
    return res.status(500).send('Blog is not configured');
  }
  try {
    const query =
      `${SUPABASE_URL}/rest/v1/blog_posts` +
      `?select=slug,title,excerpt,cover_url,published_at` +
      `&order=published_at.desc&limit=50`;
    const response = await fetch(query, {
      headers: {
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`,
        Accept: 'application/json',
      },
    });
    if (!response.ok) throw new Error(`supabase ${response.status}`);
    const posts = await response.json();

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control',
      'public, max-age=0, s-maxage=300, stale-while-revalidate=86400');
    return res.status(200).send(page(Array.isArray(posts) ? posts : []));
  } catch (error) {
    console.error('blog index render failed:', error?.message ?? error);
    return res.status(500).send('Could not load the blog');
  }
}
