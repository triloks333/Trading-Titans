import React from 'react'
import { NoticePage } from './NoticePage'
import { PLAY_STORE_URL } from '../lib/config'

/**
 * Public route: /topup
 *
 * Details the available virtual demo cash packs and VIP subscriptions
 * available in the Trading Titans educational simulator.
 */
export const TopupPage: React.FC = () => (
  <NoticePage
    title="Virtual Top-Ups &amp; Plans"
    lead="Trading Titans is an educational simulator operated by Kashivwealth Management LLP. Core simulation features and starting demo cash (₹1,100) are free."
    points={[
      'Boost Pack: ₹199 for an instant ₹1,00,000 non-expiring virtual demo cash grant.',
      'Plus Pack: ₹599 for an instant ₹5,00,000 non-expiring virtual demo cash grant.',
      'Max Pack: ₹999 for an instant ₹10,00,000 non-expiring virtual demo cash grant.',
      'Pro Subscription: ₹149/mo (or ₹1,199/yr) with PRO badge, advanced analytics, and ₹50,000 monthly virtual demo stipend.',
      'Titan Subscription: ₹799/mo (or ₹5,999/yr) with TITAN badge, 1-on-1 VIP Founder Mentorship, and ₹5,00,000 monthly virtual demo stipend.',
      'Zero Real-World Value: All top-up packs provide fictional demo simulation currency only. Demo cash cannot be redeemed, withdrawn, or exchanged for real money under any circumstances.',
    ]}
  >
    <div className="flex flex-wrap gap-4 pt-2">
      <a
        href="/app"
        className="inline-block bg-[#2563eb] text-white font-semibold text-sm px-6 py-2.5 rounded-xl hover:bg-blue-700 transition-colors shadow"
      >
        View Plans &amp; Top-Ups in Web App
      </a>
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-block bg-zinc-900 text-white font-semibold text-sm px-6 py-2.5 rounded-xl hover:bg-zinc-800 transition-colors border border-zinc-700"
      >
        Get the Android App
      </a>
    </div>
  </NoticePage>
)
