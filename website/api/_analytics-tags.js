// Analytics tags for the server-rendered pages (/blog, /blog/:slug, landing
// pages). Underscore-prefixed, so Vercel bundles it as a helper rather than
// deploying it as a function.
//
// The React SPA gets Vercel Web Analytics from `inject()` in src/main.tsx; these
// pages never load that bundle, so they include the Insights script directly.
// Both load /api/analytics for GA4 and CTA tracking.
export const ANALYTICS_TAGS =
  '<script defer src="/_vercel/insights/script.js"></script>\n' +
  '<script defer src="/api/analytics"></script>';
