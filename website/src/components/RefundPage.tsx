import React from 'react'
import { NoticePage } from './NoticePage'
import { LAST_UPDATED, SUPPORT_EMAIL } from '../lib/legal'

/**
 * Public route: /refund (also /refund-policy, /refunds).
 *
 * Outlines our fair refund & cancellation policy for digital goods,
 * subscriptions (Pro & Titan), and one-time top-ups operated by Kashivwealth Management LLP.
 */
export const RefundPage: React.FC = () => (
  <NoticePage
    title="Cancellation &amp; Refund Policy"
    lead="Trading Titans is operated by Kashivwealth Management LLP. Digital services, simulator subscriptions, and virtual demo cash grants are provisioned immediately upon purchase."
    points={[
      'Technical Failure / Non-Delivery: If an authorized payment succeeds but your plan or demo cash fails to credit to your account, we will activate it immediately upon verification or issue a 100% full refund.',
      'Duplicate Charges: Erroneous duplicate charges for the same order or billing period are refunded in full.',
      'Accidental Renewals: If an auto-renewal occurs unintentionally, contact us within 7 days. If the new period is substantially unused, we will process a complete refund for that billing cycle.',
      'Subscriptions Cancellation: You can cancel monthly or annual subscriptions anytime via your receipt link, in-app billing settings, or Apple ID subscriptions settings. You will retain access until the end of the paid billing period without future charges.',
      'Digital Goods & Demo Cash: Because virtual cash is fictional simulation currency delivered immediately, spent virtual balances or dissatisfaction with simulated market results are non-refundable.',
      'Refund Processing Time: Approved refunds are returned directly to the original payment source (credit/debit card, UPI, or App Store account) within 5 to 7 business days.',
    ]}
  >
    <p>
      To submit a refund request or billing inquiry, please email us directly at{' '}
      <a href={`mailto:${SUPPORT_EMAIL}`} className="text-[#2563eb] hover:underline font-semibold">
        {SUPPORT_EMAIL}
      </a>{' '}
      with your registered email and payment transaction reference ID.
    </p>
    <p>
      For full details, please review our{' '}
      <a href="/terms" className="text-[#2563eb] hover:underline">
        Terms &amp; Conditions
      </a>{' '}
      and{' '}
      <a href="/privacy" className="text-[#2563eb] hover:underline">
        Privacy Policy
      </a>
      .
    </p>
    <p className="text-xs text-[#7888A3]">Last updated: {LAST_UPDATED}</p>
  </NoticePage>
)
