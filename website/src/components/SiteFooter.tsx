import React from 'react';

export const SiteFooter: React.FC = () => {
  return (
    <footer className="bg-black border-t border-white/10 py-12 px-6 md:px-12">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div className="flex items-center gap-3">
            <img src="/logo.svg" className="w-9 h-9 rounded-md border border-white/15" alt="Trading Titans" />
            <div className="flex flex-col">
              <span className="text-white text-2xl font-playfair italic leading-tight">Trading Titans</span>
              <span className="text-[10px] tracking-wider uppercase text-white/60 font-semibold">by Kashivwealth Management LLP</span>
            </div>
          </div>
          <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
            <a href="/paper-trading-app-india" className="text-white/70 hover:text-white font-medium transition-colors">Paper Trading</a>
            <a href="/options-trading-simulator" className="text-white/70 hover:text-white font-medium transition-colors">Options Simulator</a>
            <a href="/brokerage-calculator" className="text-white/70 hover:text-white font-medium transition-colors">Brokerage Calculator</a>
            <a href="/blog" className="text-white/70 hover:text-white font-medium transition-colors">Blog</a>
            <a href="/about" className="text-white/70 hover:text-white font-medium transition-colors">About Us</a>
            <a href="/contact" className="text-white/70 hover:text-white font-medium transition-colors">Contact</a>
            <a href="/terms" className="text-white/70 hover:text-white font-medium transition-colors">Terms &amp; Conditions</a>
            <a href="/privacy" className="text-white/70 hover:text-white font-medium transition-colors">Privacy Policy</a>
            <a href="/refund" className="text-white/70 hover:text-white font-medium transition-colors">Refund Policy</a>
            <a href="/topup" className="text-white/70 hover:text-white font-medium transition-colors">Plans &amp; Top-Ups</a>
            <a href="mailto:support@thetradingtitans.com" className="text-[#e8702a] hover:underline font-medium">support@thetradingtitans.com</a>
          </div>
        </div>

        {/* Apple Developer & Corporate Verification Box */}
        <div className="mt-10 pt-8 border-t border-white/15">
          <div className="bg-white/5 border border-white/10 rounded-2xl p-6 md:p-8 backdrop-blur-sm">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-white/10">
              <div>
                <span className="inline-block text-[10px] uppercase tracking-widest font-bold text-[#e8702a] bg-[#e8702a]/10 px-2.5 py-1 rounded-md mb-2 border border-[#e8702a]/20">
                  Corporate Legal Entity
                </span>
                <h3 className="text-lg md:text-xl font-bold text-white tracking-tight">
                  Kashivwealth Management LLP
                </h3>
                <p className="text-xs text-white/75 mt-1 leading-relaxed max-w-2xl">
                  Trading Titans is an official software brand and educational market simulation platform wholly owned, developed, and operated by <strong className="text-white">Kashivwealth Management LLP</strong> (incorporated in India under the Limited Liability Partnership Act).
                </p>
              </div>
              <div className="shrink-0 text-left md:text-right text-xs text-white/60 space-y-1">
                <div>
                  <span className="block text-white/40 uppercase tracking-wider text-[10px] font-semibold">Official Domain</span>
                  <span className="text-white font-mono font-medium">thetradingtitans.com</span>
                </div>
                <div>
                  <span className="block text-white/40 uppercase tracking-wider text-[10px] font-semibold mt-1.5">Official Entity Verification</span>
                  <a href="mailto:support@thetradingtitans.com" className="text-[#e8702a] hover:underline font-medium">
                    support@thetradingtitans.com
                  </a>
                </div>
              </div>
            </div>

            <p className="text-xs text-white/50 leading-relaxed mt-4">
              <strong className="text-white/75">Educational Simulator Notice:</strong> Trading Titans provides simulated paper-trading for financial education and strategy testing. We do not provide real broker connectivity, investment advisory, securities custody, or real cash payouts. Fictional demo cash balances hold zero real-world monetary value and cannot be withdrawn or redeemed.
            </p>
            <p className="mt-4 text-xs text-white/40">
              &copy; {new Date().getFullYear()} Kashivwealth Management LLP. All rights reserved. Trading Titans is a proprietary trademark and product of Kashivwealth Management LLP.
            </p>
          </div>
        </div>
      </div>
    </footer>
  );
};
