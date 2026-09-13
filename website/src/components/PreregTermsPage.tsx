import React from 'react'
import { NoticePage } from './NoticePage'
import { PLAY_STORE_URL, STARTING_CASH } from '../lib/config'

/**
 * Public route: /prereg-terms
 *
 * This URL was given to Google Play as the pre-registration reward's "Terms and
 * Conditions" link. Pre-registration is over and the app is live, so the page now
 * explains that rather than 404ing on a link the store may still hold.
 */
export const PreregTermsPage: React.FC = () => (
  <NoticePage
    title="Pre-registration has ended"
    lead={`Trading Titans is now live on Google Play, and it is free to download. There is no longer anything to pre-register for.`}
    points={[
      `Every new account starts with ${STARTING_CASH} in virtual practice cash — no pre-registration needed.`,
      'The app is completely free. No subscriptions, no paid plans, no in-app purchases.',
      'Demo cash is fictional. It has zero real-world value and cannot be withdrawn, redeemed or exchanged for real money.',
      'Challenges, streaks and referrals award further demo cash inside the app.',
    ]}
  >
    <p>
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="text-[#2563eb] hover:underline font-semibold"
      >
        Download Trading Titans on Google Play
      </a>
    </p>
    <p>
      Your use of the app is governed by our{' '}
      <a href="/terms" className="text-[#2563eb] hover:underline">
        Terms &amp; Conditions
      </a>{' '}
      and{' '}
      <a href="/privacy" className="text-[#2563eb] hover:underline">
        Privacy Policy
      </a>
      .
    </p>
  </NoticePage>
)
