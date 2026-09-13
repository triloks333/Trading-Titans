import React from 'react'
import { NoticePage } from './NoticePage'
import { LAST_UPDATED } from '../lib/legal'

/**
 * Public route: /refund (also /refund-policy, /refunds).
 *
 * Trading Titans is free, so there is nothing to refund. The page is kept rather
 * than removed because the URL may still be referenced from the store listing or
 * older builds, and this states the position plainly instead of 404ing.
 */
export const RefundPage: React.FC = () => (
  <NoticePage
    title="Refund Policy"
    lead="Trading Titans is completely free. There is nothing to buy, so there is nothing to refund."
    points={[
      'There are no subscriptions, paid plans, wallet top-ups or in-app purchases.',
      'We do not collect card details, bank details or UPI information.',
      'Demo cash inside the app is fictional. It cannot be bought, withdrawn, redeemed or exchanged for real money, and no balance represents money you have paid.',
      'If anyone asks you to pay for Trading Titans, for demo cash, or for an account, it is not us. Please report it to our support email.',
    ]}
  >
    <p>
      If we ever introduce optional paid features, we will publish a refund policy
      here and update our{' '}
      <a href="/terms" className="text-[#2563eb] hover:underline">
        Terms &amp; Conditions
      </a>{' '}
      before anything can be charged.
    </p>
    <p className="text-xs text-[#7888A3]">Last updated: {LAST_UPDATED}</p>
  </NoticePage>
)
