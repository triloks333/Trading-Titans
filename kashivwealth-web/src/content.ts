/**
 * Copy for the KASHIVWEALTH MANAGEMENT LLP company site.
 *
 * This is the company site, not a product site: both products get equal billing
 * and the framing is "what this company builds and why", with each product
 * section deep enough to stand on its own.
 *
 * Product claims are taken from what actually exists, not invented:
 *
 *   Trading Titans -> `abouttitans.md`, the Flutter app in `app/`, and the live
 *     Play listing. Free, virtual money only, Indian + US equities and crypto.
 *   Kashiv Vault   -> `supabase/migrations/20260728000000_kashivwealth_vault_schema.sql`
 *     and `20260728000008_notes_todos_notifications.sql`. Every feature below
 *     maps to a real table (kv_documents/kv_document_versions -> versions,
 *     expires_at -> expiry alerts, kv_passwords -> credentials, kv_notes/kv_todos,
 *     kv_links/kv_images/kv_signatures, kv_members.role + kv_invites -> roles,
 *     kv_activity -> audit trail, pin_hash/biometric_on -> device lock).
 */

export const COMPANY = 'KASHIVWEALTH MANAGEMENT LLP'
export const COMPANY_SHORT = 'KashivWealth'
export const CONTACT_EMAIL = 'support@thetradingtitans.com'
export const PLAY_URL =
  'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans'

export const TAGLINE = 'Software for the problems people actually have.'

export const INTRO =
  'We are a small software company building practical tools for everyday problems. ' +
  'Learning to invest without risking your savings. Keeping what a business depends ' +
  'on in one place you can trust. Useful software, shipped and maintained.'

/* ── What the company believes ─────────────────────────────────────────────── */

export const PRINCIPLES = [
  {
    icon: 'Target',
    title: 'Solve one real problem',
    body: 'Every product starts from something that genuinely annoys people, not from a market we would like to be in.',
  },
  {
    icon: 'ShieldCheck',
    title: 'Safe by construction',
    body: 'Simulated money in a trading app. Access enforced in the database, not the interface. Safety belongs in the design, not the disclaimer.',
  },
  {
    icon: 'Wallet',
    title: 'Free where it should be',
    body: 'Trading Titans is completely free with no paid plans and no top-ups. You earn a bigger practice balance by playing, not by paying.',
  },
  {
    icon: 'Hammer',
    title: 'Shipped, then maintained',
    body: 'Both products are live systems we keep fixing and extending, not launches we walked away from.',
  },
]

/* ── Products ──────────────────────────────────────────────────────────────── */

export type Product = {
  key: string
  name: string
  kicker: string
  status: string
  live: boolean
  href: string
  summary: string
  /** The problem it exists to fix, in one sentence. */
  problem: string
  features: { icon: string; title: string; body: string }[]
  /** Short factual chips shown under the heading. */
  facts: string[]
  accent: 'gold' | 'teal'
}

export const PRODUCTS: Product[] = [
  {
    key: 'trading-titans',
    name: 'Trading Titans',
    kicker: 'Play the game. Learn the market.',
    status: 'Live on Google Play',
    live: true,
    href: PLAY_URL,
    accent: 'gold',
    summary:
      'Complete tasks to earn virtual money, then use that virtual money to learn how ' +
      'to be better at the stock market. 16 challenges, XP and Titan levels wrapped ' +
      'around real Indian stocks, US stocks, F&O and crypto. Start with \u20b911,000 free.',
    problem:
      'Learning to trade is dry and expensive, so most people quit early or lose money finding out.',
    facts: ['Completely free', '\u20b911,000 to start', '16 challenges & XP'],
    features: [
      {
        icon: 'LineChart',
        title: 'Real markets, simulated stakes',
        body: 'Live prices for Indian stocks, US stocks and crypto. Market, limit and derivative orders that behave like the real thing, settled against virtual cash.',
      },
      {
        icon: 'Trophy',
        title: 'Tasks pay your practice balance',
        body: 'Sixteen challenges across performance, habits, breadth and learning. Rewards run from \u20b9500 for a green day to \u20b925,000 for the Century Club, each adding XP and Titan levels.',
      },
      {
        icon: 'Flame',
        title: 'Streaks build the habit',
        body: 'Three days running, then fourteen, then thirty. Trading well is a habit before it is a skill, so showing up is rewarded.',
      },
      {
        icon: 'Coins',
        title: 'Your currency, your markets',
        body: 'Choose rupees or dollars and every price, balance and P&L figure follows that choice. Pick the markets you follow and your favourite opens first.',
      },
      {
        icon: 'Microscope',
        title: 'Tools that teach',
        body: 'A What-If simulator to replay an earlier entry, a post-trade breakdown of what went right or wrong, and a plain-English glossary on every unfamiliar term.',
      },
      {
        icon: 'Bell',
        title: 'Alerts and notifications',
        body: 'Price alerts, order fills and reward announcements, each with its own sound, so you know what happened without opening the app.',
      },
      {
        icon: 'Users',
        title: 'Compete and invite',
        body: 'A weekly leaderboard ranks traders against each other, and referrals credit demo cash to both sides.',
      },
    ],
  },
  {
    key: 'kashiv-vault',
    name: 'Kashiv Vault',
    kicker: 'Every document and password, one secure place',
    status: 'In development',
    live: false,
    href: '#contact',
    accent: 'teal',
    summary:
      'The vault a company actually needs: contracts with a version history, ' +
      'credentials out of spreadsheets, expiry dates that remind you, and a ' +
      'complete record of who touched what.',
    problem:
      'A company\u2019s memory ends up scattered across inboxes, desktops and a spreadsheet nobody trusts.',
    facts: ['Invite-only access', 'Row-level security', 'Full audit trail'],
    features: [
      {
        icon: 'FileText',
        title: 'Documents that keep their history',
        body: 'Replace a contract next quarter and the old version is still there. Every file keeps a numbered version trail, so "which copy is current?" stops being a question.',
      },
      {
        icon: 'BellRing',
        title: 'Nothing expires quietly',
        body: 'Give a document an expiry date and the vault watches it. Licences, registrations and insurance surface before they lapse, not after.',
      },
      {
        icon: 'KeyRound',
        title: 'Passwords out of spreadsheets',
        body: 'Credentials live in the vault instead of a shared sheet or a chat thread. Star the ones you open daily and they stay at the top.',
      },
      {
        icon: 'ListChecks',
        title: 'Notes and tasks beside the files',
        body: 'Pin the notes that matter and assign tasks with owners and due dates, next to the document they belong to rather than in another app.',
      },
      {
        icon: 'Building2',
        title: 'Company and personal, kept apart',
        body: 'Every folder is scoped either to the company or to you, so your own documents stay yours inside a shared workspace.',
      },
      {
        icon: 'Fingerprint',
        title: 'Locked, and logged',
        body: 'A PIN or fingerprint gate per device, four permission roles, invite-only membership, and an audit trail of every upload, edit and deletion.',
      },
    ],
  },
]

/* ── Company facts ─────────────────────────────────────────────────────────── */

export const STATS = [
  { value: '2', label: 'Products built' },
  { value: '1', label: 'Live on Google Play' },
  { value: '3', label: 'Markets covered' },
  { value: '\u20b90', label: 'Cost to learn' },
]
