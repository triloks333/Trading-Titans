import React from 'react';
import { PREREG_GIFT_AMOUNT } from '../lib/config';

/** Pre-registration reward Terms & Conditions.
 *
 * This is the page you link in the Google Play Console under the
 * pre-registration reward's "Terms and Conditions URLs" field.
 * Public route: /prereg-terms
 */
export const PreregTermsPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-[#EDEEF5] py-20 px-6 md:px-12 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-4xl mx-auto bg-white border border-[#D0D4DF] rounded-2xl p-8 md:p-12 shadow-lg mt-10">

        <div className="border-b border-[#EDEEF5] pb-6 mb-8 text-center md:text-left">
          <span className="text-sm font-bold text-[#2563eb] uppercase tracking-wider">Trading Titans</span>
          <h1 className="text-3xl md:text-4xl font-extrabold text-[#0f172a] tracking-tight mt-2">
            Pre-registration Reward — Terms & Conditions
          </h1>
          <p className="text-zinc-500 text-xs mt-3">Last Updated: June 29, 2026</p>
        </div>

        <div className="space-y-8 text-[#525E75] text-sm leading-relaxed">

          {/* Important Notice */}
          <div className="bg-[#FFF5F5] border-l-4 border-red-500 p-6 rounded-r-xl">
            <h3 className="font-bold text-red-800 text-base mb-2">IMPORTANT NOTICE</h3>
            <p className="text-red-700 text-xs font-semibold uppercase tracking-wider mb-2">
              The reward is virtual in-app currency for a paper-trading simulation game.
            </p>
            <p className="text-red-700">
              The {PREREG_GIFT_AMOUNT} pre-registration gift is fictional "Demo Cash" used only inside the
              Trading Titans simulation. It has <strong>zero real-world monetary value</strong> and cannot
              be withdrawn, redeemed, refunded, transferred, or exchanged for real money or goods.
            </p>
          </div>

          {/* Section 1 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">1. The Reward</h2>
            <p>
              Users who pre-register for Trading Titans on Google Play and later install and sign in to the
              app at launch are eligible to receive a one-time reward of {PREREG_GIFT_AMOUNT} in virtual
              practice cash ("Demo Cash") credited to their in-app wallet.
            </p>
          </section>

          {/* Section 2 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">2. Eligibility</h2>
            <ul className="list-disc pl-5 mt-2 space-y-1">
              <li>You must have pre-registered for Trading Titans through the official Google Play listing.</li>
              <li>You must install the app and create or sign in to a Trading Titans account at launch.</li>
              <li>One reward per user and per Google account. Duplicate, fraudulent, or automated claims are not eligible.</li>
              <li>The reward is available only while the pre-registration campaign is active and is subject to Google Play's policies.</li>
            </ul>
          </section>

          {/* Section 3 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">3. How the Reward Is Delivered</h2>
            <p>
              The reward is granted automatically once, after you sign in to the app following launch. The
              Demo Cash appears in your virtual wallet and can be used to practice simulated trading within
              the app. Delivery may take a short time to process.
            </p>
          </section>

          {/* Section 4 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">4. No Real-World Value</h2>
            <p>
              All currencies, balances, portfolios, and trades inside Trading Titans are simulated and
              fictional. The pre-registration reward is provided solely to enhance the educational,
              risk-free experience and confers no real money, securities, or financial benefit of any kind.
            </p>
          </section>

          {/* Section 5 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">5. Changes & Cancellation</h2>
            <p>
              We may modify, suspend, or cancel the pre-registration reward, including its amount and
              eligibility criteria, at any time and at our sole discretion, without prior notice. We may
              withhold or revoke the reward where we reasonably suspect abuse, fraud, or violation of these
              terms or our general Terms & Conditions.
            </p>
          </section>

          {/* Section 6 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">6. Sponsor</h2>
            <p>
              This pre-registration reward is offered by Trading Titans and is not sponsored, endorsed, or
              administered by Google. It is governed by these terms together with the Trading Titans{' '}
              <a href="/terms" className="text-[#2563eb] hover:underline">Terms &amp; Conditions</a> and{' '}
              <a href="/privacy" className="text-[#2563eb] hover:underline">Privacy Policy</a>.
            </p>
          </section>

          <div className="pt-6 border-t border-[#EDEEF5] flex justify-between items-center text-xs text-[#7888A3]">
            <span>Trading Titans Support</span>
            <a href="mailto:support@thetradingtitans.com" className="text-[#2563eb] hover:underline">
              support@thetradingtitans.com
            </a>
          </div>

        </div>
      </div>
    </div>
  );
};
