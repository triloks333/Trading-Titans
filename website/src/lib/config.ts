// ─────────────────────────────────────────────────────────────────────────
// Site configuration
//
// Trading Titans is live on Google Play and free to download. The site used to
// run a pre-registration campaign with a "link coming soon" fallback; that is
// over, so the fallback and the `isPlayStoreLive()` guard have been removed
// rather than left as unreachable branches.
// ─────────────────────────────────────────────────────────────────────────
export const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans&pcampaignid=web_share'

/**
 * Virtual practice cash every new account starts with. Demo cash only.
 *
 * ₹11,000 is the real figure, not marketing: `initial_bal NUMERIC := 11000.0`
 * in the signup trigger, and `challenge_baseline_capital DEFAULT 11000` which
 * percentage-return challenges are measured against. The site previously
 * advertised ₹50,000 as a pre-registration gift, which a normal signup never
 * received.
 */
export const STARTING_CASH = '₹11,000'

/** The one-line pitch. Used in the hero, the closing CTA and the page meta. */
export const MOTTO =
  'Complete tasks to earn virtual money, and use that virtual money to learn how to be better at the stock market.'
