import React from 'react'
import { NoticePage } from './NoticePage'
import { PLAY_STORE_URL } from '../lib/config'

/**
 * Public route: /topup
 *
 * This page used to sell virtual-cash packs through Razorpay (Starter Boost,
 * Titan Plus, Pro Launch). Trading Titans is now completely free and paid
 * surfaces are switched off in the app (`app_flags.monetization_enabled` is
 * false), so leaving a live checkout here would contradict the app, the Terms and
 * the store listing — and could take money for something that is free.
 *
 * The route is kept so older links do not 404. If monetisation ever returns, the
 * previous implementation is in git history.
 */
export const TopupPage: React.FC = () => (
  <NoticePage
    title="Top-ups are no longer needed"
    lead="Trading Titans is completely free. Demo cash is included, and there is nothing to purchase."
    points={[
      'The paid boost packs have been withdrawn. No payment is taken anywhere in the app or on this site.',
      'Every account starts with virtual practice cash, and you can earn more by completing challenges, keeping a login streak or referring a friend.',
      'All of it is demo cash: fictional, with zero real-world value, and not withdrawable.',
      'If anyone asks you to pay for demo cash, it is not us. Please report it to our support email.',
    ]}
  >
    <p>
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="text-[#2563eb] hover:underline font-semibold"
      >
        Download Trading Titans free on Google Play
      </a>
    </p>
  </NoticePage>
)
