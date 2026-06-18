import React from 'react';

export const TermsPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-[#EDEEF5] py-20 px-6 md:px-12 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-4xl mx-auto bg-white border border-[#D0D4DF] rounded-2xl p-8 md:p-12 shadow-lg mt-10">
        
        <div className="border-b border-[#EDEEF5] pb-6 mb-8 text-center md:text-left">
          <span className="text-sm font-bold text-[#2563eb] uppercase tracking-wider">Trading Titans</span>
          <h1 className="text-3xl md:text-4xl font-extrabold text-[#0f172a] tracking-tight mt-2">
            Terms & Conditions
          </h1>
          <p className="text-zinc-500 text-xs mt-3">Last Updated: June 11, 2026</p>
        </div>

        <div className="space-y-8 text-[#525E75] text-sm leading-relaxed">
          
          {/* Important Notice */}
          <div className="bg-[#FFF5F5] border-l-4 border-red-500 p-6 rounded-r-xl">
            <h3 className="font-bold text-red-800 text-base mb-2">IMPORTANT NOTICE</h3>
            <p className="text-red-700 text-xs font-semibold uppercase tracking-wider mb-2">
              Virtual paper-trading simulation game for educational purposes only.
            </p>
            <p className="text-red-700">
              Trading Titans is a simulated virtual training application. Under no circumstances do we facilitate real-world trading, broker connectivity, real financial transactions, real payouts, or provide professional financial advice. All investments and portfolios inside the app are fictional.
            </p>
          </div>

          {/* Section 1 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">1. Agreement to Terms</h2>
            <p>
              By accessing, downloading, or using the Trading Titans mobile application or website (collectively, the "Platform"), you agree to be bound by these Terms & Conditions. If you do not agree, you must immediately cease using the Platform and uninstall our mobile application.
            </p>
          </section>

          {/* Section 2 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">2. Virtual Currency & Game Credits</h2>
            <p>
              The Platform uses fictional currencies (e.g., "Demo Cash", "Coins", "Credits") to facilitate virtual trading activities. 
            </p>
            <ul className="list-disc pl-5 mt-2 space-y-1">
              <li>These credits have <strong>zero real-world value</strong> and cannot be redeemed, refunded, or exchanged for real money.</li>
              <li>Selling or buying virtual accounts, credits, or simulated portfolios outside the Platform's approved mechanics is strictly prohibited and will result in permanent account termination.</li>
            </ul>
          </section>

          {/* Section 3 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">3. Payments & Wallet Top-Ups</h2>
            <p>
              Users may purchase top-up packages to add fictional credits to their virtual game wallet. 
            </p>
            <ul className="list-disc pl-5 mt-2 space-y-1">
              <li>All payments are processed securely through third-party gateways (e.g., Razorpay/UPI).</li>
              <li>Purchases of virtual credits are one-time payments for simulated game features and are **strictly non-refundable** once credited to your account.</li>
              <li>We reserve the right to change packages, pricing, or promotional rewards at any time without prior notice.</li>
            </ul>
          </section>

          {/* Section 4 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">4. Simulated Market Data</h2>
            <p>
              All market quotes, stock lists, futures, options, crypto prices, and charts displayed on the Platform are sourced from third-party APIs (such as Fyers, Zerodha, Yahoo Finance, or CoinGecko) for simulation purposes only. We do not guarantee the completeness, accuracy, or real-time status of this data. You should never use the prices inside Trading Titans to execute or plan real-world trades.
            </p>
          </section>

          {/* Section 5 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">5. Referral System</h2>
            <p>
              We offer a commission reward for users who invite others to join Trading Titans. Commission rates, criteria for payouts, and validation processes are managed at our sole discretion. Any attempt to abuse the referral system using bots, fake accounts, or spamming will lead to revocation of all commissions and immediate ban.
            </p>
          </section>

          {/* Section 6 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">6. Limitation of Liability</h2>
            <p>
              Trading Titans, its founders, and affiliates shall not be liable for any direct, indirect, incidental, or consequential damages resulting from your use or inability to use the Platform, including but not limited to any potential confusion between virtual trading and real-world investing.
            </p>
          </section>

          {/* Section 7 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">7. Modifications to the Service and Terms</h2>
            <p>
              We reserve the right to modify or discontinue the Platform (or any part thereof) with or without notice at any time. We also reserve the right to revise these Terms periodically. Your continued use of the Platform after any revisions constitutes your acceptance of the updated terms.
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
