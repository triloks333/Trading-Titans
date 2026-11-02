/*
 * Product analytics, from the web app's side.
 *
 * The loader itself lives on the marketing site at /api/analytics (see
 * website/api/analytics.js) and is shared by every page on the domain; this app
 * is rewritten under thetradingtitans.com/app, so index.html can load it from
 * the same origin. All this module does is forward events to it.
 *
 * Fire-and-forget by design: a blocked tracker, a missing GA ID or an ad
 * blocker must never be able to break a trade or a checkout.
 */

type Params = Record<string, unknown>

declare global {
  interface Window {
    ttTrack?: (name: string, params?: Params) => void
  }
}

export function track(name: string, params: Params = {}): void {
  try {
    window.ttTrack?.(name, params)
  } catch {
    // Analytics is never allowed to throw into product code.
  }
}
