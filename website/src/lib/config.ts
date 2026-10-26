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
 * ₹1,100 is the real figure: `initial_bal NUMERIC := 1100.0`
 * in the signup trigger, and `challenge_baseline_capital DEFAULT 1100` which
 * percentage-return challenges are measured against. Guest accounts start with ₹500.
 */
export const STARTING_CASH = '₹1,100';
export const GUEST_STARTING_CASH = '₹500';

/** Legal entity owning and operating the brand and platform. */
export const COMPANY_NAME = 'Kashivwealth Management LLP';
export const BRAND_NAME = 'Trading Titans';
export const SUPPORT_EMAIL = 'support@thetradingtitans.com';
export const OFFICIAL_ENTITY_STATEMENT =
  'Trading Titans is an official software product wholly owned, developed, and operated by Kashivwealth Management LLP.';

/** The one-line pitch. Used in the hero, the closing CTA and the page meta. */
export const MOTTO =
  'Complete tasks to earn virtual money, and use that virtual money to learn how to be better at the stock market.'
