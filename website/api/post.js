// Vercel Serverless Function — server-rendered blog post.
//
// The whole reason this is a function and not a React route: the rest of this site
// is a Vite SPA behind a catch-all rewrite to index.html, so a crawler fetching
// /blog/<slug> would receive an empty shell and index nothing. Search engines do
// execute JavaScript now, but inconsistently and on their own schedule, and
// social unfurlers (WhatsApp, X, LinkedIn) do not execute it at all — an og:image
// injected client-side never appears in a shared link. So the HTML, the title, the
// canonical and the Open Graph tags are all produced here, before the response
// leaves the server.
//
// Reads with the ANON key on purpose. `blog_posts` has an RLS policy that exposes
// only rows where published_at <= now(), so a draft cannot leak even if this
// function asked for one. Using the service-role key here would remove that
// protection and put the only safeguard in this file's own WHERE clause.

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

/// Escapes text for HTML text nodes and attribute values.
///
/// Post bodies are written by admins, but "the author is trusted" is not a reason
/// to interpolate raw strings into a page — a stray `</script>` in a code sample
/// would break out just as effectively as an attack, and this output is served
/// from our own origin where it would inherit the site's trust.
function esc(value) {
  return String(value ?? '')
    .split('&').join('&amp;')
    .split('<').join('&lt;')
    .split('>').join('&gt;')
    .split('"').join('&quot;')
    .split("'").join('&#39;');
}

// A deliberately small Markdown subset: headings, bold, italic, inline code,
// fenced code, links, images, lists, paragraphs.
//
// ponytail: hand-rolled rather than pulling in a Markdown library plus a
// sanitiser. Everything is escaped BEFORE any markup is introduced, so the output
// cannot contain author-supplied HTML at all — which is a stronger guarantee than
// escaping afterwards, and it is why a sanitiser is not needed. The ceiling is
// tables, footnotes and nested lists; the upgrade path is markdown-it plus
// DOMPurify, at which point the escape-first order must be preserved.
function renderMarkdown(markdown) {
  const source = String(markdown ?? '').replace(/\r\n/g, '\n');
  const out = [];
  const lines = source.split('\n');
  let inCode = false;
  let listType = null;
  let paragraph = [];

  const closeParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join(' '))}</p>`);
      paragraph = [];
    }
  };
  const closeList = () => {
    if (listType) {
      out.push(`</${listType}>`);
      listType = null;
    }
  };

  for (const raw of lines) {
    const line = raw.trimEnd();

    if (line.trim().startsWith('```')) {
      closeParagraph();
      closeList();
      out.push(inCode ? '</code></pre>' : '<pre><code>');
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      // Already escaped, and never passed through inline(), so a code sample
      // containing markdown or angle brackets survives verbatim.
      out.push(esc(raw));
      continue;
    }

    if (line.trim() === '') {
      closeParagraph();
      closeList();
      continue;
    }

    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      closeParagraph();
      closeList();
      // Offset by one: the post title is the page's h1, so a '#' in the body is an
      // h2. Two h1s on a page is a real SEO problem, not a style preference.
      const level = Math.min(heading[1].length + 1, 5);
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      continue;
    }

    const bullet = /^[-*]\s+(.*)$/.exec(line);
    const numbered = /^\d+\.\s+(.*)$/.exec(line);
    if (bullet || numbered) {
      closeParagraph();
      const wanted = bullet ? 'ul' : 'ol';
      if (listType !== wanted) {
        closeList();
        out.push(`<${wanted}>`);
        listType = wanted;
      }
      out.push(`<li>${inline((bullet || numbered)[1])}</li>`);
      continue;
    }

    closeList();
    paragraph.push(line.trim());
  }
  closeParagraph();
  closeList();
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}

// Inline formatting. Runs on ALREADY-ESCAPED text, so the only tags in the result
// are the ones introduced right here.
function inline(text) {
  let s = esc(text);
  // Images before links: the syntax differs by one leading '!' and doing links
  // first would consume them.
  s = s.replace(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g,
    (_m, alt, url) => `<img src="${url}" alt="${alt}" loading="lazy">`);
  // Only http(s). A javascript: or data: href written into a post would run on our
  // own origin.
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
    (_m, label, url) => `<a href="${url}" rel="noopener">${label}</a>`);
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
  return s;
}

function page({ post, html }) {
  const cleanExcerpt = (post.excerpt || '').replace(/^\[market:[^\]]+\]\s*/i, '');
  const description = cleanExcerpt || `${post.title} on the Trading Titans blog.`;
  const url = `${SITE}/blog/${post.slug}`;
  const published = post.published_at
    ? new Date(post.published_at).toISOString()
    : null;

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(post.title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${esc(url)}">
<meta property="og:type" content="article">
<meta property="og:title" content="${esc(post.title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
${post.cover_url ? `<meta property="og:image" content="${esc(post.cover_url)}">` : ''}
<meta name="twitter:card" content="${post.cover_url ? 'summary_large_image' : 'summary'}">
${published ? `<meta property="article:published_time" content="${esc(published)}">` : ''}
<script type="application/ld+json">${JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: post.title,
    description,
    datePublished: published,
    dateModified: post.updated_at
      ? new Date(post.updated_at).toISOString()
      : published,
    image: post.cover_url || undefined,
    mainEntityOfPage: { '@type': 'WebPage', '@id': url },
    publisher: { '@type': 'Organization', name: 'Trading Titans' },
  })}</script>
<style>
:root{color-scheme:light}
*{box-sizing:border-box}
body{margin:0;background:#F4F7FB;color:#0B1B2B;
  font:16px/1.65 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
header,main,footer{max-width:720px;margin:0 auto;padding:0 20px}
header{padding-top:32px}
a{color:#1A73E8}
.brand{font-weight:800;text-decoration:none;color:#0B1B2B;font-size:15px}
h1{font-size:34px;line-height:1.2;margin:24px 0 8px}
.meta{color:#627D98;font-size:13px;margin-bottom:24px}
.cover{width:100%;height:auto;border-radius:10px;margin:0 0 28px}
main img{max-width:100%;height:auto;border-radius:8px}
pre{background:#0B1B2B;color:#F4F7FB;padding:14px 16px;border-radius:8px;
  overflow-x:auto;font-size:13.5px}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.92em}
p>code,li>code{background:#E6EEF7;padding:1px 5px;border-radius:4px}
blockquote{margin:0;padding-left:16px;border-left:3px solid #DDE7F2;color:#334E68}
footer{padding:48px 20px;color:#627D98;font-size:13px}
.cta{display:inline-block;margin-top:8px;background:#1A73E8;color:#fff;
  padding:11px 18px;border-radius:8px;text-decoration:none;font-weight:700}
</style>
</head>
<body>
<header><a class="brand" href="${SITE}">Trading Titans</a></header>
<main>
<h1>${esc(post.title)}</h1>
<div class="meta">${published
    ? new Date(published).toLocaleDateString('en-IN',
        { day: 'numeric', month: 'long', year: 'numeric' })
    : ''}</div>
${post.cover_url ? `<img class="cover" src="${esc(post.cover_url)}" alt="">` : ''}
${html}
<p><a class="cta" href="${SITE}/app">Start trading with virtual money</a></p>
</main>
<footer>
<a href="${SITE}/blog">All posts</a> ·
<a href="${SITE}/privacy">Privacy</a> ·
<a href="${SITE}/terms">Terms</a>
</footer>
</body>
</html>`;
}

function notFound() {
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Post not found — Trading Titans</title>
<meta name="robots" content="noindex">
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;
background:#F4F7FB;color:#0B1B2B;font:16px/1.6 -apple-system,BlinkMacSystemFont,
'Segoe UI',Roboto,sans-serif;text-align:center;padding:24px}
a{color:#1A73E8}</style></head>
<body><div><h1>That post is not here</h1>
<p>It may have been moved or is not published yet.</p>
<p><a href="https://thetradingtitans.com/blog">See all posts</a></p>
</div></body></html>`;
}

// Exported for post.check.mjs. Vercel only cares about the default export, so
// naming these costs nothing and makes the escaping testable without a server.
export { esc, inline, renderMarkdown };

export default async function handler(req, res) {
  const slug = String(req.query?.slug ?? '').trim().toLowerCase();

  // Validated before it reaches the database, and the same shape the table's CHECK
  // enforces. Keeps a malformed slug from becoming a PostgREST query at all.
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug) || slug.length < 3) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.status(404).send(notFound());
  }

  if (!SUPABASE_URL || !SUPABASE_ANON) {
    // Never a 200: a soft error page would get indexed in place of the post.
    return res.status(500).send('Blog is not configured');
  }

  try {
    const query =
      `${SUPABASE_URL}/rest/v1/blog_posts` +
      `?slug=eq.${encodeURIComponent(slug)}` +
      `&select=slug,title,excerpt,body_markdown,cover_url,published_at,updated_at` +
      `&limit=1`;
    const response = await fetch(query, {
      headers: {
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`,
        Accept: 'application/json',
      },
    });
    if (!response.ok) throw new Error(`supabase ${response.status}`);
    const rows = await response.json();
    const post = Array.isArray(rows) ? rows[0] : null;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    if (!post) {
      // A real 404 status, so a crawler drops it instead of indexing an error page.
      return res.status(404).send(notFound());
    }

    // Cached at the edge for 5 minutes, then served stale while revalidating, so a
    // post that gets shared widely does not turn into one database read per visitor.
    res.setHeader('Cache-Control',
      'public, max-age=0, s-maxage=300, stale-while-revalidate=86400');
    return res.status(200).send(page({
      post,
      html: renderMarkdown(post.body_markdown),
    }));
  } catch (error) {
    console.error('blog post render failed:', error?.message ?? error);
    return res.status(500).send('Could not load that post');
  }
}
