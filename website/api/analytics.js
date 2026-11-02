// Vercel Serverless Function — the site-wide analytics loader at /api/analytics.
//
// One script for every surface on thetradingtitans.com: the React marketing
// SPA, the server-rendered SEO pages (/blog, /blog/:slug, the landing pages)
// and the web app under /app, which is a separate Vercel project rewritten onto
// this domain and so can load this same path. Keeping it in one place means the
// three cannot drift into counting different things.
//
// The GA4 measurement ID comes from the GA_MEASUREMENT_ID environment variable
// at request time, not build time, so setting or changing it in Vercel takes
// effect within the edge cache window without a rebuild. With no ID set the
// script still defines window.ttTrack (as a harmless queue) and still tags Play
// Store links, so callers never have to check whether analytics is on.

const GA_ID = (process.env.GA_MEASUREMENT_ID || process.env.VITE_GA_MEASUREMENT_ID || '')
  .replace(/^[﻿\s]+|[﻿\s]+$/g, '');

function script(gaId) {
  return `(function () {
  var GA_ID = ${JSON.stringify(gaId)};
  var w = window;
  if (w.__ttAnalytics) return;
  w.__ttAnalytics = true;

  w.dataLayer = w.dataLayer || [];
  w.gtag = w.gtag || function () { w.dataLayer.push(arguments); };
  w.ttTrack = function (name, params) {
    try { w.gtag('event', name, params || {}); } catch (e) {}
  };

  function pageSlug() {
    var p = location.pathname.replace(/\\/+$/, '');
    return p ? p.slice(1).replace(/[^a-z0-9]+/gi, '_').slice(0, 80) : 'home';
  }

  function ctaLocation(a) {
    var tagged = a.closest('[data-cta]');
    if (tagged) return tagged.getAttribute('data-cta');
    var region = a.closest('section[id],header,footer,nav,main');
    return region ? (region.id || region.tagName.toLowerCase()) : 'body';
  }

  // Capture phase, so the referrer is on the href before the browser follows it.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var url;
    try { url = new URL(a.href, location.href); } catch (err) { return; }
    var where = ctaLocation(a);

    if (url.hostname === 'play.google.com' && url.pathname.indexOf('/store/apps/details') === 0) {
      // Play Console attributes installs by the referrer parameter, so this is
      // what makes "installs from the website, by page" a report rather than a
      // guess. An explicit referrer already on the link wins.
      if (!url.searchParams.has('referrer')) {
        url.searchParams.set('referrer',
          'utm_source=website&utm_medium=web_cta&utm_campaign=' + pageSlug() + '&utm_content=' + where);
        a.href = url.toString();
      }
      w.ttTrack('play_store_click', { link_location: where, page_slug: pageSlug(), transport_type: 'beacon' });
      return;
    }

    var onApp = location.pathname.indexOf('/app') === 0;
    if (!onApp && url.origin === location.origin && /^\\/app(\\/|$)/.test(url.pathname)) {
      w.ttTrack('open_web_app_click', { link_location: where, page_slug: pageSlug(), transport_type: 'beacon' });
    }
  }, true);

  if (!GA_ID) return;
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_ID);
  document.head.appendChild(s);
  w.gtag('js', new Date());
  w.gtag('config', GA_ID);
})();
`;
}

export default function handler(_req, res) {
  const id = /^G-[A-Z0-9]{4,20}$/.test(GA_ID) ? GA_ID : '';
  res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=3600, stale-while-revalidate=86400');
  return res.status(200).send(script(id));
}
