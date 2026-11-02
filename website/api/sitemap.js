// Vercel Serverless Function — dynamic XML Sitemap at /sitemap.xml.
//
// Generates a search-engine standard sitemap containing the core static pages
// and all published blog posts dynamically fetched from Supabase.
//
// Served with s-maxage=3600 so Vercel's edge cache keeps crawler load low
// while ensuring newly published articles appear within an hour.

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
    .split("'").join('&apos;');
}

function formatDate(dateStr) {
  if (!dateStr) return new Date().toISOString().split('T')[0];
  try {
    return new Date(dateStr).toISOString().split('T')[0];
  } catch {
    return new Date().toISOString().split('T')[0];
  }
}

export default async function handler(_req, res) {
  if (!SUPABASE_URL || !SUPABASE_ANON) {
    return res.status(500).send('Database connection is not configured');
  }

  const today = new Date().toISOString().split('T')[0];

  const staticPages = [
    { loc: `${SITE}/`, lastmod: today, changefreq: 'daily', priority: '1.0' },
    { loc: `${SITE}/paper-trading-app-india`, lastmod: today, changefreq: 'daily', priority: '1.0' },
    { loc: `${SITE}/options-trading-simulator`, lastmod: today, changefreq: 'daily', priority: '0.9' },
    { loc: `${SITE}/brokerage-calculator`, lastmod: today, changefreq: 'daily', priority: '0.9' },
    { loc: `${SITE}/blog`, lastmod: today, changefreq: 'daily', priority: '0.9' },
    { loc: `${SITE}/topup`, lastmod: today, changefreq: 'weekly', priority: '0.8' },
    { loc: `${SITE}/about`, lastmod: '2026-11-01', changefreq: 'monthly', priority: '0.7' },
    { loc: `${SITE}/contact`, lastmod: '2026-11-01', changefreq: 'monthly', priority: '0.6' },
    { loc: `${SITE}/terms`, lastmod: '2026-11-01', changefreq: 'monthly', priority: '0.5' },
    { loc: `${SITE}/privacy`, lastmod: '2026-11-01', changefreq: 'monthly', priority: '0.5' },
    { loc: `${SITE}/refund`, lastmod: '2026-11-01', changefreq: 'monthly', priority: '0.5' },
  ];

  let posts = [];
  try {
    const query =
      `${SUPABASE_URL}/rest/v1/blog_posts` +
      `?select=slug,published_at,updated_at` +
      `&published_at=not.is.null` +
      `&order=published_at.desc&limit=1000`;

    const response = await fetch(query, {
      headers: {
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`,
        Accept: 'application/json',
      },
    });

    if (response.ok) {
      posts = await response.json();
    } else {
      console.error('sitemap fetch posts failed with status:', response.status);
    }
  } catch (error) {
    console.error('sitemap error fetching posts:', error?.message ?? error);
  }

  const xmlEntries = [
    ...staticPages.map(
      (p) =>
        `  <url>\n    <loc>${esc(p.loc)}</loc>\n    <lastmod>${p.lastmod}</lastmod>\n    <changefreq>${p.changefreq}</changefreq>\n    <priority>${p.priority}</priority>\n  </url>`
    ),
    ...(Array.isArray(posts) ? posts : []).map((p) => {
      const lastmod = formatDate(p.updated_at || p.published_at);
      return `  <url>\n    <loc>${esc(`${SITE}/blog/${p.slug}`)}</loc>\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>0.8</priority>\n  </url>`;
    }),
  ];

  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${xmlEntries.join('\n')}\n</urlset>`;

  res.setHeader('Content-Type', 'application/xml; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=3600, stale-while-revalidate=86400');
  return res.status(200).send(xml);
}
