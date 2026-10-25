import React from 'react';

export const SiteFooter: React.FC = () => {
  return (
    <footer className="bg-black border-t border-white/10 py-12 px-6 md:px-12">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div className="flex items-center gap-2.5">
            <img src="/logo.svg" className="w-8 h-8 rounded-md border border-white/15" alt="Trading Titans" />
            <span className="text-white text-2xl font-playfair italic">Trading Titans</span>
          </div>
          <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
            <a href="/about" className="text-white/70 hover:text-white font-medium">About Us</a>
            <a href="/contact" className="text-white/70 hover:text-white font-medium">Contact</a>
            <a href="/terms" className="text-white/70 hover:text-white font-medium">Terms &amp; Conditions</a>
            <a href="/privacy" className="text-white/70 hover:text-white font-medium">Privacy Policy</a>
            <a href="/refund" className="text-white/70 hover:text-white font-medium">Refund Policy</a>
            <a href="mailto:support@thetradingtitans.com" className="text-white/70 hover:text-white font-medium">support@thetradingtitans.com</a>
          </div>
        </div>

        <div className="mt-10 pt-6 border-t border-white/10 text-center md:text-left">
          <p className="text-xs text-white/70 font-semibold mb-2">
            Trading Titans is a brand operated by KashivWealth Management LLP.
          </p>
          <p className="text-xs text-white/50 leading-relaxed max-w-3xl">
            <strong className="text-white/70">Trading Titans is a virtual paper-trading simulation game for educational purposes only.</strong>{' '}
            We do not provide real financial advice, real trading execution, or real payouts. All currencies,
            balances and portfolios inside the app are fictional and hold no real-world monetary value.
          </p>
          <p className="mt-4 text-xs text-white/40">© {new Date().getFullYear()} KashivWealth Management LLP. All rights reserved.</p>
        </div>
      </div>
    </footer>
  );
};
