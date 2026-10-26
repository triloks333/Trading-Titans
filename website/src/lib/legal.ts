/**
 * Terms & Conditions and Privacy Policy for the website.
 *
 * Reflects the app's current architecture and features:
 * - Owned and operated by Kashivwealth Management LLP.
 * - Free core educational simulator with starting virtual demo cash (₹1,100 on signup, ₹500 in guest mode).
 * - Optional paid subscriptions (Pro and Titan tiers) and one-time virtual cash top-up packs.
 * - Secure billing via Razorpay, Google Play In-App Billing, and Apple App Store StoreKit.
 * - Auto-renewal terms compliant with Apple App Store Guideline 3.1.2.
 * - Explicit disclaimers: simulated trading only, zero real-world monetary value, no broker connectivity, no financial advice.
 */

export const LAST_UPDATED = 'October 25, 2026';
export const SUPPORT_EMAIL = 'support@thetradingtitans.com';
export const COMPANY_NAME = 'Kashivwealth Management LLP';
export const BRAND_NAME = 'Trading Titans';

export type LegalSection = {
  heading: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type LegalDoc = {
  title: string;
  lastUpdated: string;
  intro: string;
  noticeTitle?: string;
  notice?: string;
  sections: LegalSection[];
};

export const TERMS: LegalDoc = {
  title: 'Terms & Conditions',
  lastUpdated: LAST_UPDATED,
  noticeTitle: 'IMPORTANT NOTICE & ENTITY DISCLOSURE',
  notice:
    'Trading Titans is an educational market simulation platform wholly owned, developed, and operated by Kashivwealth Management LLP, a Limited Liability Partnership registered in India.\n\n' +
    'Trading Titans operates exclusively as an educational simulation game. We do not provide real financial advice, broker connectivity, securities trading, or real monetary payouts. All currencies, balances, portfolios, and profits inside the application are fictional demo units and hold strictly zero real-world monetary value, including balances credited through paid subscriptions or top-up packs.',
  intro:
    'These Terms & Conditions ("Terms") constitute a legally binding agreement between you and Kashivwealth Management LLP ("Company", "we", "us", or "our") regarding your access to and use of Trading Titans (mobile applications, website at thetradingtitans.com, and related simulation services, collectively referred to as the "Platform"). By downloading, accessing, or using the Platform, you acknowledge that you have read, understood, and agree to be bound by these Terms.',
  sections: [
    {
      heading: '1. Agreement to Terms & Corporate Legal Entity',
      paragraphs: [
        'By creating an account, downloading, accessing, or using Trading Titans, you confirm that you have read, understood, and agreed to be bound by these Terms and our Privacy Policy. If you do not agree to these Terms, you must discontinue use and uninstall the application immediately.',
        'Trading Titans is a brand and software product wholly owned, developed, and operated by Kashivwealth Management LLP. All contracts, purchases, services, customer relationships, and data handling associated with Trading Titans are conducted under the direct authority and responsibility of Kashivwealth Management LLP.',
      ],
    },
    {
      heading: '2. Free Core Platform and Optional Paid Subscriptions',
      paragraphs: [
        'Trading Titans is free to download and use. Every registered account receives a free starting virtual balance of ₹1,100 (or ₹500 in instant guest mode) and can earn additional virtual capital by completing educational challenges, daily tasks, and maintaining login streaks. Core simulator features, real-time charts, and educational leaderboards remain accessible at no cost.',
        'To support advanced learners, we offer optional paid subscription plans (Pro and Titan tiers) and optional one-time demo-cash top-up packs. Purchasing a plan or pack is entirely voluntary and is never required to use the Platform.',
        'What a payment buys: A payment buys access to premium educational simulator features, advanced analytical tools, founder mentorship sessions, and simulated non-redeemable demo balances. You are NEVER purchasing real money, securities, financial assets, investment returns, or financial advisory.',
      ],
      bullets: [
        'Pro Subscription: Available on monthly (₹149/mo or $2/mo) and annual (₹1,199/yr or $13/yr) billing cycles. Includes the PRO badge, advanced technical analytics, and a monthly virtual demo stipend of ₹50,000.',
        'Titan Subscription: Available on monthly (₹799/mo or $9/mo) and annual (₹5,999/yr or $64/yr) billing cycles. Includes the TITAN badge, 1-on-1 VIP Founder Mentorship sessions, full options tooling, and a monthly virtual demo stipend of ₹5,00,000.',
        'One-Time Virtual Top-Up Packs: Non-expiring simulated demo cash packages (Boost: ₹199 for ₹1,00,000 demo cash; Plus: ₹599 for ₹5,00,000 demo cash; Max: ₹999 for ₹10,00,000 demo cash).',
        'Taxes & Pricing: Prices are inclusive of all applicable Goods and Services Tax (GST) and statutory taxes. The price displayed at checkout is the final invoice amount.',
        'Payment Gateways: Online payments are processed securely through certified, PCI-DSS compliant third-party payment gateways (including Razorpay, Google Play In-App Billing, and Apple App Store StoreKit). We never handle, store, or receive your raw credit/debit card numbers or UPI PINs.',
        'Auto-Renewal Terms (Apple Guideline 3.1.2 & Standard Subscriptions): Subscriptions automatically renew at the end of each recurring billing period (monthly or annually) at the same regular price unless cancelled. For iOS subscriptions, your Apple ID Account will be charged for renewal within 24 hours prior to the end of the current period.',
        'Managing & Cancelling Subscriptions: You can cancel your subscription at any time. For web/Android subscriptions, manage your subscription from the link in your payment receipt, in-app billing settings, or by emailing support@thetradingtitans.com. For Apple iOS subscriptions, manage or cancel auto-renewal in your Apple ID Account Settings. Cancelling stops future recurring billing while maintaining your paid benefits through the end of the current prepaid billing period.',
      ],
    },
    {
      heading: '3. Cancellations, Refunds & Digital Goods Delivery',
      paragraphs: [
        'Because premium digital features and virtual simulator grants are provisioned immediately and automatically upon payment confirmation, payments for digital services and top-ups are generally non-refundable once delivered. However, we strive to be fair and transparent:',
      ],
      bullets: [
        'Non-Delivery / Technical Failure: If a payment was successfully charged but the corresponding subscription tier or virtual grant failed to activate on your account, we will investigate and either activate the plan immediately or issue a full refund.',
        'Duplicate Charges: If an erroneous duplicate charge occurs for the exact same order or billing period, the duplicate payment will be refunded in full.',
        'Accidental Recurring Renewal: If an annual or monthly renewal was charged unintentionally, contact us within 7 days of the renewal charge. If the subscription benefits during that new period are substantially unused, we will process a full refund for that billing cycle.',
        'Non-Refundable Scenarios: Voluntarily changing your mind after utilizing features, dissatisfaction with simulated trading results, or demo cash that has already been spent within the simulation cannot be refunded.',
        'How to Request a Refund: Email support@thetradingtitans.com from your registered account email with the transaction ID or invoice reference. Our billing team reviews requests within 3 business days, and approved refunds are returned to the original payment source within 5 to 7 business days.',
        'Terminated Accounts: Accounts terminated due to violation of acceptable use, manipulation, or fraudulent behavior forfeit all refund eligibility.',
      ],
    },
    {
      heading: '4. Virtual Currency and Simulated Demo Cash',
      paragraphs: [
        'The Platform uses fictional simulated currency (referred to as demo cash, virtual capital, or credits) solely to enable risk-free practice and education.',
      ],
      bullets: [
        'Strictly Zero Real-World Value: Demo cash has no cash equivalent, no monetary value, and cannot be withdrawn, redeemed, cashed out, transferred, or exchanged for real currency, goods, or real-world services under any circumstances.',
        'Applies to Paid Top-Ups: Purchasing a demo-cash top-up or subscription grant provides a larger virtual playground inside the simulator; it does NOT convert virtual balances into real funds or create any monetary liability against the Company.',
        'No Off-Platform Transfers: Buying, selling, trading, or transferring simulated accounts, virtual balances, or positions outside the official application is strictly prohibited and subject to immediate account termination.',
      ],
    },
    {
      heading: '5. Market Quotes & Simulation Disclaimers',
      paragraphs: [
        'Price quotes, charts, historical data, order books, and derivative options chains shown in Trading Titans are sourced from public and third-party data providers for educational simulation. Quotes may be delayed or approximated.',
        'Trading Titans and Kashivwealth Management LLP do not execute real orders on any financial exchange. Simulated order fills do not reflect real market liquidity, slippage, order priority, or actual market impact. Never use simulated execution to inform real-world capital allocations.',
      ],
    },
    {
      heading: '6. Rewards, Streaks, and Fair Play',
      paragraphs: [
        'Trading Titans offers in-game XP, Titan levels, daily login streaks, challenges, and referral programs. All rewards are awarded in fictional demo cash and game XP only.',
        'Any attempt to exploit software vulnerabilities, use bots, automate gameplay, generate fraudulent referrals, or tamper with quotes will result in immediate forfeiture of rewards and permanent account suspension.',
      ],
    },
    {
      heading: '7. Limitation of Liability & No Financial Advice',
      paragraphs: [
        'Trading Titans and Kashivwealth Management LLP provide the Platform on an "as-is" and "as-available" basis without warranties of any kind. Nothing on the Platform constitutes financial, investment, tax, or legal advice.',
        'To the fullest extent permitted by applicable law, Kashivwealth Management LLP, its partners, designated partners, officers, employees, and affiliates shall not be liable for any indirect, incidental, punitive, or consequential losses, or any real-world trading losses incurred as a result of using the Platform.',
      ],
    },
    {
      heading: '8. Governing Law and Dispute Resolution',
      paragraphs: [
        'These Terms and any dispute arising from or related to the Platform shall be governed by and construed in accordance with the laws of India, without regard to conflict of law principles. The courts having jurisdiction over the registered office of Kashivwealth Management LLP shall have exclusive jurisdiction.',
      ],
    },
    {
      heading: '9. Modifications to Platform and Terms',
      paragraphs: [
        'We reserve the right to amend, update, or replace these Terms at any time to reflect legal, regulatory, or platform changes. The revision date at the top of this page indicates the latest revision. Continued use of the Platform after amendments constitutes acceptance of the revised Terms.',
      ],
    },
  ],
};

export const PRIVACY: LegalDoc = {
  title: 'Privacy Policy',
  lastUpdated: LAST_UPDATED,
  intro:
    'Trading Titans is an educational market simulation platform operated by Kashivwealth Management LLP ("Company", "we", "us", or "our"). This Privacy Policy describes how we collect, store, process, and protect your information when you access or use our applications and website (thetradingtitans.com). We respect your privacy and never sell your personal information.',
  sections: [
    {
      heading: '1. Data Controller & Entity Details',
      paragraphs: [
        'Kashivwealth Management LLP is the data controller responsible for the personal data collected through Trading Titans. If you have questions regarding this Privacy Policy or your personal data rights, you can contact our privacy officer at support@thetradingtitans.com.',
      ],
    },
    {
      heading: '2. Information We Collect',
      paragraphs: ['When you create an account, subscribe to a plan, or use Trading Titans, we may collect:'],
      bullets: [
        'Account Credentials: Your email address, chosen display name, and an encrypted hash of your authentication credentials. If you register via Google Sign-In or Apple Sign-In, we receive the authenticated email and profile name authorized by the provider.',
        'Profile Information: Profile pictures or screenshots you voluntarily upload (such as attachments to support tickets or bug reports).',
        'Simulated Trading Data: Virtual order records, portfolio holdings, performance analytics, challenge milestones, XP points, watchlists, and price alerts.',
        'Billing & Transaction Metadata: When you purchase a subscription or virtual top-up, we collect transactional metadata including the transaction identifier, plan SKU, amount paid, currency, timestamp, and payment status. Raw payment card numbers, CVVs, and UPI PINs are processed directly by certified payment processors (Razorpay, Apple StoreKit, Google Play) and are NEVER received, stored, or accessible on our servers.',
        'Device & Telemetry: Device model, operating system version, client application version, crash logs, and anonymized performance metrics to diagnose technical faults.',
        'Notification Tokens: Push notification tokens (such as Firebase Cloud Messaging or Apple APNs) to deliver price triggers, challenge updates, and order confirmations.',
      ],
    },
    {
      heading: '3. What We Do NOT Collect',
      bullets: [
        'No Raw Payment Credentials: We never collect, process, or store full credit card numbers, bank account passwords, or UPI PINs.',
        'No Real Broker Credentials: We never request or connect to real brokerage, Demat, or bank accounts.',
        'No Intrusive Device Tracking: We do not access contacts, precise GPS location, microphone, or camera without explicit user-initiated actions.',
      ],
    },
    {
      heading: '4. Purpose of Data Processing',
      bullets: [
        'To establish and maintain your user account and simulated portfolio.',
        'To match simulated orders, calculate virtual returns, and deliver market charts.',
        'To process, activate, and manage your paid subscription plans and virtual top-ups.',
        'To award challenge XP, milestone demo cash, and maintain transparent leaderboards.',
        'To dispatch important account security notifications and price alerts.',
        'To provide customer service, resolve billing inquiries, and investigate technical bugs.',
        'To prevent fraud, automated abuse, and enforce our Terms & Conditions.',
      ],
    },
    {
      heading: '5. Third-Party Service Providers',
      paragraphs: [
        'We share minimal necessary data with vetted third-party service providers who assist in operating the Platform under strict confidentiality agreements:',
      ],
      bullets: [
        'Payment Processors: Razorpay, Apple App Store, and Google Play process payment transactions securely in compliance with PCI-DSS standards.',
        'Cloud Infrastructure & Database: Supabase (managed PostgreSQL) provides enterprise cloud hosting, encrypted storage, and authentication.',
        'Hosting & Delivery: Vercel provides web hosting, edge network routing, and SSL termination for thetradingtitans.com.',
        'Analytics & Crash Reporting: Google Firebase and Apple App Analytics provide telemetry for crash prevention and performance diagnostics.',
        'Market Data Providers: Yahoo Finance, CoinDCX, CoinGecko, and broker partner APIs provide market price feeds. No personal user data is ever transmitted to data feed providers.',
      ],
    },
    {
      heading: '6. Data Security and Encryption',
      paragraphs: [
        'We employ industry-standard administrative, technical, and physical safeguards to protect user data. All communications between your device and our servers use Transport Layer Security (TLS/HTTPS). Database records are encrypted at rest with Row Level Security (RLS) policies guaranteeing that users can only access their own private data.',
      ],
    },
    {
      heading: '7. Data Retention & User Rights (Account Deletion)',
      paragraphs: [
        'You have full ownership of your data. You may edit your profile information in the app at any time, or request complete account and data deletion via the in-app Account Settings screen or by emailing support@thetradingtitans.com. Upon account deletion, all personal identifiers, portfolio histories, and simulation data are permanently wiped from active databases.',
      ],
    },
    {
      heading: '8. Children\'s Privacy',
      paragraphs: [
        'Trading Titans is an educational simulation platform intended for a general audience and is not directed at children under the age of 13 (or under 16 where required by local law). We do not knowingly collect personal information from children.',
      ],
    },
    {
      heading: '9. Changes to this Privacy Policy',
      paragraphs: [
        'We may update this Privacy Policy periodically. Significant changes will be announced through an in-app notice or on our website. The revision date at the top of this document indicates when changes take effect.',
      ],
    },
  ],
};
