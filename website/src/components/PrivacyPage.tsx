import React from 'react';

export const PrivacyPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-[#EDEEF5] py-20 px-6 md:px-12 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-4xl mx-auto bg-white border border-[#D0D4DF] rounded-2xl p-8 md:p-12 shadow-lg mt-10">
        
        <div className="border-b border-[#EDEEF5] pb-6 mb-8 text-center md:text-left">
          <span className="text-sm font-bold text-[#2563eb] uppercase tracking-wider">Trading Titans</span>
          <h1 className="text-3xl md:text-4xl font-extrabold text-[#0f172a] tracking-tight mt-2">
            Privacy Policy
          </h1>
          <p className="text-zinc-500 text-xs mt-3">Last Updated: June 11, 2026</p>
        </div>

        <div className="space-y-8 text-[#525E75] text-sm leading-relaxed">
          
          <p>
            At Trading Titans, accessible from the Trading Titans mobile application and thetradingtitans.com, one of our main priorities is the privacy of our visitors. This Privacy Policy document contains types of information that is collected and recorded by Trading Titans and how we use it.
          </p>

          {/* Section 1 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">1. Information We Collect</h2>
            <p>
              When you register and use our Platform, we may collect the following types of information:
            </p>
            <ul className="list-disc pl-5 mt-2 space-y-2">
              <li>
                <strong>Account Information:</strong> Your email address, username, password hash, and profile details that you supply when creating your account.
              </li>
              <li>
                <strong>Transaction Metadata:</strong> When you purchase virtual credit packages, we collect the payment reference IDs (e.g., Razorpay Payment ID, Order ID) to verify and credit the virtual coins to your wallet. <strong>We do not collect or store your card numbers, banking credentials, or UPI PINs</strong>. Those are processed directly by our payment processor (Razorpay).
              </li>
              <li>
                <strong>Game Progress and Portfolios:</strong> Details about your virtual transactions, trade histories, profit/losses, watchlists, and virtual wallet balance.
              </li>
              <li>
                <strong>Usage & Device Data:</strong> We may collect data about the device you use to access our Platform, including device type, operating system version, and system logs.
              </li>
            </ul>
          </section>

          {/* Section 2 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">2. How We Use Your Information</h2>
            <p>
              We use the collected information for various purposes, including to:
            </p>
            <ul className="list-disc pl-5 mt-2 space-y-2">
              <li>Provide, operate, and maintain our virtual paper-trading platform.</li>
              <li>Improve, personalize, and expand the user experience.</li>
              <li>Understand and analyze how you use our application.</li>
              <li>Process and verify payment transactions to credit virtual cash packages.</li>
              <li>Manage referral links and calculate referral commissions.</li>
              <li>Communicate with you for customer support, system alerts, or verification codes.</li>
            </ul>
          </section>

          {/* Section 3 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">3. How Your Data is Secured</h2>
            <p>
              Your data is stored and managed securely using **Supabase Backend Infrastructure** (hosted on AWS/PostgreSQL). We implement industry-standard database encryption, HTTPS protocols, and Row Level Security (RLS) policies to protect against unauthorized access, modification, or exposure of your personal information.
            </p>
          </section>

          {/* Section 4 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">4. Third-Party Service Providers</h2>
            <p>
              We work with trusted third-party services to deliver the Platform's core functionalities:
            </p>
            <ul className="list-disc pl-5 mt-2 space-y-2">
              <li>
                <strong>Supabase:</strong> For cloud database hosting, serverless edge functions, and user authentication.
              </li>
              <li>
                <strong>Razorpay:</strong> To process standard payments and UPI transactions for virtual cash packages.
              </li>
              <li>
                <strong>Market Data Providers:</strong> We use APIs like Yahoo Finance and CoinGecko to fetch public market data. These providers do not receive any of your personal account credentials.
              </li>
            </ul>
          </section>

          {/* Section 5 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">5. Data Sharing and Transfer</h2>
            <p>
              Trading Titans does not sell, rent, or trade your personal data to advertising networks or third-party marketing companies. We only share information when legally required, or to comply with terms of service and protection of our users.
            </p>
          </section>

          {/* Section 6 */}
          <section>
            <h2 className="text-lg font-bold text-[#0f172a] mb-3">6. Your Data Rights</h2>
            <p>
              You have the right to access, edit, or request deletion of your account and personal data at any time. If you wish to delete your account, you can send an email to our support team, and we will purge your user record from our active databases.
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
