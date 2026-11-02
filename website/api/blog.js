// Vercel Serverless Function — server-rendered blog index at /blog.
//
// Server-rendered for the same reason as the individual post: this site is a Vite
// SPA behind a catch-all rewrite, so a crawler reaching /blog through the SPA would
// find no links to the posts and would never discover them. The index is how the
// posts get crawled at all.
//
// Anon key deliberately, so the published-only RLS policy is what gates the list
// rather than this file's own query.

import { ANALYTICS_TAGS } from './_analytics-tags.js';

const SUPABASE_URL = (
  process.env.VITE_SUPABASE_URL ||
  process.env.SUPABASE_URL ||
  'https://bftvimnhpoiuoyryyiff.supabase.co'
).replace(/^[\uFEFF\s]+|[\uFEFF\s]+$/g, '');
const SUPABASE_ANON = (
  process.env.VITE_SUPABASE_ANON_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak'
).replace(/^[\uFEFF\s]+|[\uFEFF\s]+$/g, '');

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
  const cleanExcerpt = (post.excerpt || '').replace(/^\[market:[^\]]+\]\s*/i, '');
  return `<li class="card">
${post.cover_url
      ? `<a href="/blog/${esc(post.slug)}"><img src="${esc(post.cover_url)}" alt="" loading="lazy"></a>`
      : ''}
<div>
<h2><a href="/blog/${esc(post.slug)}">${esc(post.title)}</a></h2>
<div class="meta">${esc(date)}</div>
${cleanExcerpt ? `<p>${esc(cleanExcerpt)}</p>` : ''}
</div>
</li>`;
}

function page(posts) {
  const title = 'Market News & Trading Blog — Trading Titans';
  const description =
    'Latest market updates, stock analysis, F&O insights and paper trading guides from Trading Titans. Learn to trade with virtual cash before risking your own.';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${SITE}/blog">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${SITE}/blog">
<meta property="og:image" content="${SITE}/screens/s1.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${SITE}/screens/s1.png">
<link rel="sitemap" type="application/xml" title="Sitemap" href="${SITE}/sitemap.xml">
<style>
:root{color-scheme:light}
*{box-sizing:border-box}
body{margin:0;background:#F4F7FB;color:#0B1B2B;
  font:16px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
header,main,footer{max-width:860px;margin:0 auto;padding:0 20px}
header{padding-top:28px;display:flex;align-items:center;justify-content:space-between}
.brand{font-weight:800;text-decoration:none;color:#0B1B2B;font-size:16px}
.cta-btn{display:inline-block;background:#e8702a;color:#fff;text-decoration:none;
  padding:8px 16px;border-radius:20px;font-size:13px;font-weight:600;transition:opacity 0.2s}
.cta-btn:hover{opacity:0.9}
h1{font-size:32px;margin:24px 0 8px;line-height:1.2}
.subhead{color:#627D98;font-size:15px;margin:0 0 28px}
ul{list-style:none;margin:0;padding:0;display:grid;gap:20px}
.card{background:#fff;border:1px solid #DDE7F2;border-radius:12px;overflow:hidden;
  display:grid;grid-template-columns:220px 1fr;transition:box-shadow 0.2s}
.card:hover{box-shadow:0 4px 14px rgba(0,0,0,0.06)}
.card>div{padding:16px 18px}
.card img{width:100%;height:100%;object-fit:cover;display:block}
.card h2{font-size:18px;margin:0 0 6px;line-height:1.35}
.card h2 a{color:#0B1B2B;text-decoration:none}
.card h2 a:hover{color:#1A73E8}
.card p{margin:8px 0 0;color:#334E68;font-size:14px;line-height:1.5}
.meta{color:#627D98;font-size:12.5px;font-weight:500}
.empty{background:#fff;border:1px solid #DDE7F2;border-radius:12px;padding:28px;
  color:#627D98}
footer{padding:48px 20px;color:#627D98;font-size:13px;border-top:1px solid #DDE7F2;margin-top:40px}
a{color:#1A73E8}
@media(max-width:620px){.card{grid-template-columns:1fr}.card img{height:180px}
  header{flex-direction:column;align-items:flex-start;gap:12px}}
</style>
${ANALYTICS_TAGS}
</head>
<body>
<header>
  <a class="brand" href="${SITE}">Trading Titans</a>
  <a class="cta-btn" href="https://play.google.com/store/apps/details?id=com.kwm.tradingtitans" target="_blank" rel="noopener">
    Download Free App (₹1,100 Demo Cash)
  </a>
</header>
<main>
<h1>Market News &amp; Educational Insights</h1>
<p class="subhead">${posts.length} articles on Indian Stocks, US Equities, Crypto, F&amp;O and Global Macro trends.</p>
${posts.length
      ? `<ul>${posts.map(card).join('\n')}</ul>`
      : '<div class="empty">No posts yet. Check back soon.</div>'}
</main>
<footer>
<a href="${SITE}">Home</a> ·
<a href="${SITE}/sitemap.xml">XML Sitemap</a> ·
<a href="${SITE}/topup">Plans</a> ·
<a href="${SITE}/privacy">Privacy</a> ·
<a href="${SITE}/terms">Terms</a>
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
      `&published_at=not.is.null` +
      `&order=published_at.desc&limit=500`;
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
