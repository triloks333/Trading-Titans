/*
 * Consent copy and the version recorded against it.
 *
 * The web app creates accounts by three routes (email registration, Google, and
 * guest), so without a consent gate here it was simply the softer path to an
 * account than the Android app, which has required acceptance since 1.1.8. That
 * makes this a compliance hole rather than a missing nicety.
 *
 * ponytail: the policy text is held as constants, mirroring app/lib/core/legal.dart
 * rather than being fetched. The ceiling is that a policy edit now needs a change
 * in two places — three, counting the marketing site. The upgrade path is an
 * `app_config` row holding the documents, which the mobile app already reads on
 * every resume for the version gate; do that the first time the text actually
 * changes. What must NOT drift is TERMS_VERSION, because that is the value stored
 * against a user's acceptance and the whole point of storing it is being able to
 * say which text they agreed to.
 */

/**
 * Must equal `LegalDocs.termsVersion` in app/lib/core/legal.dart, which is itself
 * the documents' revision date. Both clients record this same string through the
 * `accept_terms` RPC, so a mismatch would make it impossible to tell whether two
 * users accepted the same text.
 */
export const TERMS_VERSION = 'August 17, 2026'

export const LEGAL_LAST_UPDATED = TERMS_VERSION
export const SUPPORT_EMAIL = 'support@thetradingtitans.com'

/**
 * The standing notice at the foot of the auth screen, separate from the checkbox.
 *
 * Verbatim from `LegalDocs.authDisclaimer`. It is deliberately not the full Terms
 * notice, which runs to four paragraphs and would swamp the page; it covers the
 * three things users actually misread — that everything is simulated, that we are
 * not a broker, and that the prices are not live-accurate.
 */
export const AUTH_DISCLAIMER =
  'Trading Titans is a virtual trading simulator for learning only. Every ' +
  'price, balance, profit, reward and prize in this app is simulated and has ' +
  'no real-world value — nothing can be withdrawn or redeemed.\n\n' +
  'We are not a registered broker, exchange or investment adviser, and we ' +
  'cannot place real trades. Market data comes from third parties and may be ' +
  'significantly delayed or inaccurate, so never use these prices to make ' +
  'real investment decisions. Nothing in this app is financial advice.'

export interface LegalSection {
  heading: string
  paragraphs?: string[]
  bullets?: string[]
}

export interface LegalDoc {
  title: string
  lastUpdated: string
  intro: string
  noticeTitle?: string
  notice?: string
  sections: LegalSection[]
}

/*
 * Written for the product as it actually behaves: free, with no paid plans, no
 * top-ups and no payment gateway. It deliberately does NOT reuse
 * website/src/components/TermsPage.tsx, which still describes Razorpay purchases
 * and non-refundable credits — stating a payment term for something a user cannot
 * buy is worse than saying nothing. Same decision the Dart copy records.
 */
export const TERMS: LegalDoc = {
  title: 'Terms & Conditions',
  lastUpdated: LEGAL_LAST_UPDATED,
  noticeTitle: 'IMPORTANT NOTICE',
  notice:
    'Trading Titans is a free virtual paper-trading simulation for educational ' +
    'purposes only.\n\n' +
    'We do not facilitate real-world trading, broker connectivity, real financial ' +
    'transactions or payouts, and we do not provide professional financial advice. ' +
    'Every portfolio, balance and profit figure in the app is fictional.',
  intro:
    'By creating an account or using Trading Titans you agree to these terms. ' +
    'Please read them; they describe what this product is and, more importantly, ' +
    'what it is not.',
  sections: [
    {
      heading: 'What the service is',
      paragraphs: [
        'Trading Titans simulates a trading account. Prices are sourced from third ' +
          'parties and orders are matched by our own engine against those prices.',
      ],
      bullets: [
        'Simulated only: no order ever reaches an exchange.',
        'No real money: balances, profits, rewards and prizes have no cash value.',
        'Not a broker: we are not a registered broker, exchange, or adviser.',
        'Free: there is nothing to buy, so there is nothing to refund.',
      ],
    },
    {
      heading: 'Market data',
      paragraphs: [
        'Prices, and especially derivative premiums, may be delayed, estimated or ' +
          'inaccurate. Option premiums are modelled from the underlying price rather ' +
          'than quoted from an options feed, so they can differ from the exchange.',
        'Never rely on anything shown here for a real investment decision.',
      ],
    },
    {
      heading: 'Your account',
      bullets: [
        'One account per person. Do not share credentials.',
        'You are responsible for activity under your account.',
        'We may reset simulated balances, or suspend accounts that abuse the service.',
      ],
    },
    {
      heading: 'Rewards and competitions',
      paragraphs: [
        'Challenges and leaderboards award simulated cash and experience points. ' +
          'These are features of the simulation and are not redeemable for anything ' +
          'of value.',
      ],
    },
    {
      heading: 'Liability',
      paragraphs: [
        'The service is provided as-is. We do not warrant that prices are accurate ' +
          'or that the service will be uninterrupted, and we are not liable for any ' +
          'decision taken on the basis of information shown in the app.',
      ],
    },
    {
      heading: 'Changes',
      paragraphs: [
        'We may update these terms. The revision date above changes when we do, and ' +
          'we record which revision you accepted so we can ask again if it matters.',
      ],
    },
  ],
}

export const PRIVACY: LegalDoc = {
  title: 'Privacy Policy',
  lastUpdated: LEGAL_LAST_UPDATED,
  intro:
    'This policy explains what we collect and why. We collect what the product ' +
    'needs to work, and not more.',
  sections: [
    {
      heading: 'What we collect',
      bullets: [
        'Account: your email address and the display name you choose.',
        'Trading activity: your simulated orders, positions and balance history.',
        'Device: notification tokens, so we can tell you when an order fills.',
        'Consent: the date and revision of the terms you accepted.',
      ],
    },
    {
      heading: 'What we do not collect',
      bullets: [
        'No payment details, because there is nothing to pay for.',
        'No bank, demat or broker credentials. We never ask for them, and you ' +
          'should never give them to us.',
        'No PAN, Aadhaar or KYC documents.',
      ],
    },
    {
      heading: 'How it is used',
      paragraphs: [
        'To run your account, price your simulated trades, rank leaderboards, and ' +
          'send you notifications you have opted into. We do not sell your data.',
      ],
    },
    {
      heading: 'Where it lives',
      paragraphs: [
        'Data is stored with our hosting and database providers. Access is ' +
          'restricted per-user by database row-level security, so one account ' +
          'cannot read another\u2019s positions or balance.',
      ],
    },
    {
      heading: 'Your choices',
      bullets: [
        'You can request deletion of your account and its data.',
        'You can turn notifications off on your device at any time.',
        `Questions: ${SUPPORT_EMAIL}`,
      ],
    },
  ],
}
