/// Terms & Conditions and Privacy Policy shown in the app.
///
/// Written for the app as it actually behaves: **completely free**. There are no
/// paid plans, no wallet top-ups, no payment gateway and nothing to refund, so
/// this deliberately does NOT mirror the website's paid-era text
/// (`website/src/components/TermsPage.tsx` / `PrivacyPage.tsx`), which still
/// describes Razorpay purchases and non-refundable credits. Stating a payment
/// term for something a user cannot buy is worse than saying nothing.
///
/// If monetisation is ever switched back on (`app_flags.monetization_enabled`),
/// the payments and refund clauses have to come back with it.
///
/// ponytail: held as Dart constants, so editing a policy needs an app release.
/// The ceiling is exactly that. Upgrade path is an `app_config` row — the
/// version-gate table already works that way and the app already reads it on
/// every resume — or a WebView onto the live pages. Not worth either until the
/// text changes more often than the app ships.
library;

/// One numbered section of a policy document.
class LegalSection {
  const LegalSection({
    required this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String heading;
  final List<String> paragraphs;

  /// Rendered as a bulleted list under [paragraphs]. A short leading `Label:`
  /// is bolded when displayed.
  final List<String> bullets;
}

/// A whole policy document.
class LegalDoc {
  const LegalDoc({
    required this.title,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
    this.notice,
    this.noticeTitle,
    this.supportEmail = 'support@thetradingtitans.com',
  });

  final String title;
  final String lastUpdated;
  final String intro;
  final List<LegalSection> sections;

  /// Highlighted warning shown above the sections. Terms only.
  final String? notice;
  final String? noticeTitle;
  final String supportEmail;
}

class LegalDocs {
  LegalDocs._();

  static const String lastUpdated = 'August 17, 2026';

  /// Version string recorded against a user's acceptance.
  ///
  /// Deliberately the same value as [lastUpdated]: the documents below are the
  /// thing being accepted, so their revision date IS the version. Keeping a
  /// second, independently-maintained version number would let the two drift and
  /// leave us unable to say which text someone actually agreed to.
  static const String termsVersion = lastUpdated;

  /// Short disclaimer shown at the foot of the sign-in and sign-up screens.
  ///
  /// Purpose-written rather than reusing [terms].notice: that notice runs to four
  /// paragraphs and would dominate an auth screen, and it does not mention data
  /// delays, which is the point users most often misread. This covers the three
  /// things that actually cause confusion — everything is simulated, we are not a
  /// broker, and the prices are not live-accurate.
  ///
  /// Kept here beside the policies so all user-facing legal copy lives in one
  /// file and a reviewer can see the summary and the full text together.
  static const String authDisclaimer =
      'Trading Titans is a virtual trading simulator for learning only. Every '
      'price, balance, profit, reward and prize in this app is simulated and has '
      'no real-world value — nothing can be withdrawn or redeemed.\n\n'
      'We are not a registered broker, exchange or investment adviser, and we '
      'cannot place real trades. Market data comes from third parties and may be '
      'significantly delayed or inaccurate, so never use these prices to make '
      'real investment decisions. Nothing in this app is financial advice.';

  static const LegalDoc terms = LegalDoc(
    title: 'Terms & Conditions',
    lastUpdated: lastUpdated,
    noticeTitle: 'IMPORTANT NOTICE',
    notice:
        'Trading Titans is a free virtual paper-trading simulation for '
        'educational purposes only.\n\n'
        'We do not facilitate real-world trading, broker connectivity, real '
        'financial transactions or payouts, and we do not provide professional '
        'financial advice. Every portfolio, balance and profit figure in the app '
        'is fictional.',
    intro:
        'By accessing, downloading, or using the Trading Titans mobile '
        'application or website (together, the "Platform"), you agree to these '
        'Terms & Conditions.',
    sections: [
      LegalSection(
        heading: '1. Agreement to Terms',
        paragraphs: [
          'By accessing, downloading, or using the Trading Titans mobile '
              'application or website (together, the "Platform"), you agree to '
              'be bound by these Terms & Conditions. If you do not agree, you '
              'must stop using the Platform and uninstall the app.',
        ],
      ),
      LegalSection(
        heading: '2. The App is Free',
        paragraphs: [
          'Trading Titans is free to use. There are no subscriptions, no paid '
              'plans, no wallet top-ups and no in-app purchases.',
        ],
        bullets: [
          'We will never ask you to pay for demo cash, features, rewards or '
              'account upgrades.',
          'We do not collect card details, bank details or UPI information, '
              'because there is nothing to pay for.',
          'If anyone asks you to pay money for Trading Titans, or for demo cash '
              'or an account, it is not us. Please report it to our support '
              'email below.',
          'We may introduce optional paid features in future. If we ever do, we '
              'will update these Terms first and it will be clearly marked '
              'inside the app before anything is charged.',
        ],
      ),
      LegalSection(
        heading: '3. Virtual Currency and Demo Cash',
        paragraphs: [
          'The Platform uses fictional currency (shown as demo cash, coins or '
              'credits) so you can practise trading without risk.',
        ],
        bullets: [
          'Demo cash has zero real-world value. It cannot be withdrawn, '
              'redeemed, transferred or exchanged for real money or any other '
              'thing of value.',
          'Because nothing is ever purchased, there is nothing to refund. No '
              'balance in the app represents money you have paid or money you '
              'are owed.',
          'Selling, buying or transferring accounts, demo cash or simulated '
              'portfolios outside the app is prohibited and may result in '
              'permanent account termination.',
        ],
      ),
      LegalSection(
        heading: '4. Simulated Market Data',
        paragraphs: [
          'Market quotes, stock and crypto lists, futures, options and charts '
              'in the app come from third-party data providers (such as Yahoo '
              'Finance, CoinDCX, CoinGecko, Fyers or Zerodha) and are shown for '
              'simulation only.',
          'We do not guarantee that this data is complete, accurate or '
              'real-time, and it may be delayed. Never use prices shown in '
              'Trading Titans to plan or place real-world trades.',
        ],
      ),
      LegalSection(
        heading: '5. Rewards, Challenges and Referrals',
        paragraphs: [
          'The app offers challenges, XP, levels, streaks and referral rewards. '
              'Every reward is paid in demo cash only and has no real-world '
              'value.',
        ],
        bullets: [
          'Reward amounts, eligibility rules and reward cycles are set at our '
              'discretion and may change at any time.',
          'Using bots, automation, duplicate or fake accounts, or otherwise '
              'manipulating challenges, streaks, leaderboards or referrals will '
              'result in forfeiture of rewards and may result in a ban.',
        ],
      ),
      LegalSection(
        heading: '6. Acceptable Use and Account Integrity',
        paragraphs: [
          'You agree not to interfere with the Platform or exploit it in ways '
              'it was not designed for. This includes exploiting bugs to '
              'inflate balances, tampering with quote or order data, attempting '
              'to access other users\' accounts, and automated scraping or '
              'load-generation against our services. We may suspend or '
              'terminate accounts that do any of these.',
        ],
      ),
      LegalSection(
        heading: '7. Limitation of Liability',
        paragraphs: [
          'The Platform is provided free and as-is. Trading Titans, its '
              'founders and affiliates are not liable for any direct, indirect, '
              'incidental or consequential loss arising from your use of, or '
              'inability to use, the Platform. This includes any decision you '
              'take in real markets, and any confusion between simulated '
              'trading and real-world investing.',
        ],
      ),
      LegalSection(
        heading: '8. Changes to the Service and These Terms',
        paragraphs: [
          'We may change, suspend or discontinue any part of the Platform at '
              'any time. We may also revise these Terms; the date at the top of '
              'this page shows when they last changed. Continuing to use the '
              'Platform after a revision means you accept the updated Terms.',
        ],
      ),
    ],
  );

  static const LegalDoc privacy = LegalDoc(
    title: 'Privacy Policy',
    lastUpdated: lastUpdated,
    intro:
        'Trading Titans is a free virtual trading simulator. This policy '
        'explains what we collect, why, and what you can do about it. We do not '
        'sell your data, and we do not collect payment information at all.',
    sections: [
      LegalSection(
        heading: '1. Information We Collect',
        paragraphs: [
          'When you create an account and use the app, we may collect:',
        ],
        bullets: [
          'Account Information: your email address, display name, and a secure '
              'hash of your password. If you sign in with Google, we receive '
              'your email address and basic profile details from Google, not '
              'your Google password.',
          'Profile and Uploads: a profile photo or a screenshot, only if you '
              'choose to attach one (for example to a support ticket or feature '
              'request).',
          'Simulated Trading Activity: your virtual orders, holdings, trade '
              'history, simulated profit and loss, watchlists, price alerts, '
              'demo wallet balance, challenge progress and XP.',
          'Preferences: your display currency, preferred markets and the region '
              'you told us you trade from.',
          'Device and Usage Data: device model, operating system version, app '
              'version, crash reports and basic in-app events, used to fix bugs '
              'and understand which features are used.',
          'Notification Token: a push token from Google Firebase Cloud '
              'Messaging, so we can send you order and alert notifications.',
        ],
      ),
      LegalSection(
        heading: '2. What We Do Not Collect',
        bullets: [
          'No payment information. The app is free, there are no purchases, and '
              'we never collect card numbers, bank details or UPI IDs.',
          'No real brokerage or demat account credentials. Trading Titans is '
              'not connected to any broker and cannot place real trades.',
          'No contacts, no precise location, no microphone or camera access '
              'beyond a photo you deliberately choose to upload.',
        ],
      ),
      LegalSection(
        heading: '3. How We Use Your Information',
        bullets: [
          'To run your account and your simulated portfolio.',
          'To show prices, execute simulated orders and calculate simulated '
              'profit and loss.',
          'To award challenges, XP, streaks and referral rewards in demo cash.',
          'To send order, price-alert and reward notifications.',
          'To diagnose crashes and improve the app.',
          'To respond to your support requests.',
        ],
      ),
      LegalSection(
        heading: '4. How Your Data is Secured',
        paragraphs: [
          'Your data is stored using Supabase infrastructure (managed '
              'PostgreSQL). We use encrypted connections (HTTPS), encryption at '
              'rest, and Row Level Security policies so that your records are '
              'only readable by your own account.',
        ],
      ),
      LegalSection(
        heading: '5. Third-Party Services',
        paragraphs: ['We rely on a small number of providers:'],
        bullets: [
          'Supabase: database, authentication and server functions.',
          'Google Firebase: crash reporting, basic analytics, push '
              'notifications and remote configuration.',
          'Market Data Providers: Yahoo Finance, CoinDCX, CoinGecko and broker '
              'data APIs supply public market prices. They receive no personal '
              'information about you.',
          'Google Play: distributes the app and handles updates. We do not '
              'receive your Google account password.',
        ],
      ),
      LegalSection(
        heading: '6. Data Sharing',
        paragraphs: [
          'We do not sell, rent or trade your personal data, and we do not '
              'share it with advertising networks or marketing companies. We '
              'disclose information only where the law requires it, or where it '
              'is necessary to protect the safety and integrity of the Platform '
              'and its users.',
        ],
      ),
      LegalSection(
        heading: '7. Data Retention and Your Rights',
        paragraphs: [
          'You can view and edit your profile in the app at any time. You may '
              'ask us to delete your account and personal data by emailing '
              'support; we will remove your user record from our active '
              'databases. Deleting your account removes your simulated '
              'portfolio and history, which cannot be recovered afterwards.',
        ],
      ),
      LegalSection(
        heading: '8. Children',
        paragraphs: [
          'Trading Titans is an educational simulator intended for a general '
              'audience and is not directed at children under 13. If you '
              'believe a child has given us personal information, contact us '
              'and we will remove it.',
        ],
      ),
      LegalSection(
        heading: '9. Changes to This Policy',
        paragraphs: [
          'We may update this policy; the date at the top shows when it last '
              'changed. Material changes will be highlighted in the app.',
        ],
      ),
    ],
  );
}
