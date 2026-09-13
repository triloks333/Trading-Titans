import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'

/*
 * Two things come out of this package.
 *
 *   npm run dev        the review harness (index.html), served for humans
 *   npm run build:app  a SINGLE self-contained file at ../app/assets/chart.html,
 *                      which the Flutter WebView loads
 *
 * The web app does not build from here at all: `web/vite.config.ts` aliases
 * `@chart` straight at `src/`, so it compiles the same source in its own pass.
 * That is deliberate — a built artifact in the middle is one more thing that can
 * go stale, and the way that bites is the web app shipping last week's chart while
 * the Flutter asset has this week's.
 */

/**
 * Folds the JS and CSS into the HTML and writes one file.
 *
 * Rather than adding `vite-plugin-singlefile` for what is a dozen lines. The
 * requirement is hard: the Flutter app loads this from a local asset, so a
 * `<script src>` pointing at a sibling file would need that file shipped and
 * resolved too, and any miss is a blank chart on a user's phone with no error.
 */
function inlineToAsset(outFile: string): Plugin {
  return {
    name: 'tt-inline-to-asset',
    enforce: 'post',
    apply: 'build',
    generateBundle(_options, bundle) {
      let html = ''
      const scripts: string[] = []
      const styles: string[] = []

      for (const [name, output] of Object.entries(bundle)) {
        if (output.type === 'chunk') scripts.push(output.code)
        else if (name.endsWith('.css')) styles.push(String(output.source))
        else if (name.endsWith('.html')) html = String(output.source)
      }

      if (!html) {
        this.error('no HTML entry in the bundle; check the build input')
        return
      }

      // Drop the emitted references and inline the real thing in their place.
      html = html
        .replace(/<script[^>]*src="[^"]*"[^>]*>\s*<\/script>/g, '')
        .replace(/<link[^>]*rel="stylesheet"[^>]*>/g, '')

      const inlined =
        styles.map((css) => `<style>${css}</style>`).join('') +
        // `type="module"` is kept: the code targets ES2020 and every Android
        // WebView the app supports (minSdk 24 ships Chrome 61+) handles modules.
        scripts.map((js) => `<script type="module">${js}</script>`).join('')

      html = html.replace('</body>', `${inlined}</body>`)

      mkdirSync(dirname(outFile), { recursive: true })
      writeFileSync(outFile, html, 'utf8')

      const kb = (Buffer.byteLength(html, 'utf8') / 1024).toFixed(1)
      this.info(`wrote ${outFile} (${kb} kB, self-contained)`)
    },
  }
}

/**
 * Stamps the asset with the source it was built from.
 *
 * The Flutter build has no way to know whether `app/assets/chart.html` matches the
 * `chart/` source in the same checkout, and a stale asset is invisible: the chart
 * works, it is just an old one. This writes a marker the app can log, so "which
 * chart is in this APK" has an answer.
 */
function buildStamp(): string {
  try {
    const pkg = JSON.parse(readFileSync(resolve(__dirname, 'package.json'), 'utf8'))
    return `${pkg.version}+${new Date().toISOString().slice(0, 16)}`
  } catch {
    return 'unknown'
  }
}

const WEBVIEW_OUT = resolve(__dirname, '../app/assets/chart.html')

export default defineConfig(({ mode }) => {
  const forApp = mode === 'webview'

  return {
    define: { __CHART_BUILD__: JSON.stringify(buildStamp()) },
    plugins: forApp ? [inlineToAsset(WEBVIEW_OUT)] : [],
    server: {
      // Pinned so the URL is stable to hand to a reviewer, matching web/vite.config.ts.
      port: 5180,
      strictPort: true,
      open: false,
    },
    build: {
      target: 'es2020',
      outDir: forApp ? 'dist-webview' : 'dist',
      emptyOutDir: true,
      // One chunk, or there is more than one script to inline and the order starts
      // to matter.
      rollupOptions: {
        input: forApp ? resolve(__dirname, 'webview.html') : resolve(__dirname, 'index.html'),
        output: { inlineDynamicImports: true },
      },
      // Everything inline; nothing may be emitted as a separate request.
      assetsInlineLimit: forApp ? 100_000_000 : 4096,
      cssCodeSplit: false,
      // The harness is reviewed in a browser and wants readable stack traces; the
      // app asset wants to be small.
      minify: forApp ? 'esbuild' : false,
    },
    // The intermediate dist-webview/ only exists so Rollup has somewhere to write
    // before the plugin folds it into one file.
    closeBundle: undefined,
  }
})

/** Removes the intermediate directory once the single file is written. */
process.on('exit', () => {
  try {
    rmSync(resolve(__dirname, 'dist-webview'), { recursive: true, force: true })
  } catch {
    // Nothing to clean, or it is held open. Harmless either way.
  }
})
