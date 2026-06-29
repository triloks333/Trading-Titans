// ─────────────────────────────────────────────────────────────────────────
// Site configuration
//
// 👉 When your Google Play pre-registration listing is live, paste its URL
//    below (e.g. "https://play.google.com/store/apps/details?id=com.kwm.tradingtitans").
//    Leave it as an empty string until then — the site will automatically show
//    a "Link coming soon" state on the Pre-register button.
// ─────────────────────────────────────────────────────────────────────────
export const PLAY_STORE_URL = '';

/** Amount of virtual practice cash gifted to pre-registration users. */
export const PREREG_GIFT_AMOUNT = '₹50,000';

/** Whether the Play Store link has been configured yet. */
export const isPlayStoreLive = (): boolean => PLAY_STORE_URL.trim().length > 0;
