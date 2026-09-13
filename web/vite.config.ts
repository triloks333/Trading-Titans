import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

/*
 * The app is served at https://thetradingtitans.com/app, not at a domain root.
 *
 * Two settings make that work, and they have to agree:
 *
 *   base:   '/app/'      — every asset URL in index.html is emitted as
 *                          /app/assets/..., so it resolves correctly under the
 *                          path. Left at '/' the browser would ask
 *                          thetradingtitans.com/assets/... which belongs to the
 *                          marketing site, and the app would load a blank page.
 *   outDir: 'dist/app'   — the files physically live under /app/ too, so the
 *                          host needs no asset rewriting: the URL in the HTML and
 *                          the path on disk are the same string.
 *
 * `basename` on the router in main.tsx is the third part of the same decision, and
 * it reads `import.meta.env.BASE_URL` so it follows this file automatically.
 * `authRedirectUrl()` in lib/supabase.ts is the fourth. Change the base and all of
 * them move together.
 *
 * The fifth piece lives outside this project: `website/vercel.json` proxies
 * /app/* through to this deployment. Its two /app rules MUST stay above the
 * `/(.*)` catch-all, because Vercel takes the first matching rewrite and the
 * catch-all would otherwise serve the marketing site's index.html here.
 */
export default defineConfig({
  base: '/app/',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      /*
       * The shared chart package, aliased to its SOURCE rather than a built dist.
       *
       * Deliberate: a `file:` dependency would mean a build artifact that can go
       * stale, and the most likely way for that to bite is the web app shipping
       * last week's chart while the Flutter asset has this week's. Pointing at
       * source makes "the chart" one set of files that both clients compile from,
       * and Vite handles it in the same pass with no extra step.
       *
       * The tradeoff is that this project now reads files above its own root, so
       * `server.fs.allow` below has to permit it in dev.
       */
      '@chart': path.resolve(__dirname, '../chart/src/index.ts'),
    },
  },
  build: {
    outDir: 'dist/app',
    emptyOutDir: true,
  },
  server: {
    // Pinned so the origin can be added to Supabase Auth -> URL Configuration ->
    // Redirect URLs. A random port cannot be allow-listed, which would break
    // Google sign-in and the guest upgrade.
    port: 5173,
    strictPort: true,
    fs: {
      // The chart package lives beside this project, not inside it. Without this
      // the dev server refuses to serve those files and every chart import 403s;
      // the production build is unaffected either way.
      allow: [path.resolve(__dirname, '..')],
    },
  },
})
