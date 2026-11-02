import React from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { PLAY_STORE_URL } from '../lib/config';
import { TrendingUp, HelpCircle, BarChart3, Award, Smartphone } from 'lucide-react';

export const PaperTradingIndiaPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-6 md:px-12 max-w-5xl mx-auto">
        {/* Hero Section */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-emerald-500/30 bg-emerald-500/10 text-xs text-emerald-400 font-semibold mb-4">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            #1 Paper Trading Platform &middot; India
          </div>
          <h1 className="text-4xl md:text-6xl font-extrabold tracking-tight mb-6 leading-tight">
            Best Paper Trading App in India for <span className="font-playfair italic text-[#e8702a]">NSE, BSE &amp; F&amp;O</span>
          </h1>
          <p className="text-lg md:text-xl text-white/75 leading-relaxed mb-8">
            Practice stock and derivatives trading with real-time Indian market prices and simulated demo cash. Master price action, option chains, and risk management with zero capital at risk.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a
              href={PLAY_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-3 bg-[#e8702a] hover:bg-[#d2611f] text-white font-semibold text-base px-8 py-3.5 rounded-full transition-all shadow-lg hover:scale-105"
            >
              <Smartphone className="w-5 h-5" />
              Download Free Android App
            </a>
            <a
              href="/app"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 bg-white/10 hover:bg-white/15 text-white font-semibold text-base px-8 py-3.5 rounded-full border border-white/20 transition-all"
            >
              Open Web Simulator
            </a>
          </div>
          <p className="text-xs text-white/50 mt-3">Start immediately with ₹1,100 virtual cash &middot; No credit card or Demat account needed</p>
        </div>

        {/* Feature Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16">
          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-emerald-500/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-emerald-500/15 flex items-center justify-center text-emerald-400 mb-5">
              <TrendingUp className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">Live Indian Stock Prices</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              Paper trade heavyweights across Nifty 50, Bank Nifty, and BSE Sensex including Reliance, Tata Motors, HDFC Bank, and TCS with live streaming quotes.
            </p>
          </div>

          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-blue-500/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-blue-500/15 flex items-center justify-center text-blue-400 mb-5">
              <BarChart3 className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">Real Modeled Taxes &amp; Fees</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              Unlike simplistic simulators that inflate returns, Trading Titans models brokerage, STT (Securities Transaction Tax), exchange turnover charges, and GST so your P&amp;L reflects true market conditions.
            </p>
          </div>

          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-[#e8702a]/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-[#e8702a]/15 flex items-center justify-center text-[#e8702a] mb-5">
              <Award className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">16 Trading Challenges &amp; XP</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              Gamified milestone progressions: First Blood, Diversifier, Green Day streaks, and Century Club. Earn more virtual practice cash by mastering disciplined trading habits.
            </p>
          </div>
        </div>

        {/* Comparison Table: Real Demat Account vs Trading Titans Simulator */}
        <div className="bg-zinc-900/70 border border-white/15 rounded-3xl p-8 md:p-10 mb-16 shadow-2xl">
          <h2 className="text-2xl md:text-3xl font-bold text-center mb-8">
            Why Paper Trade on <span className="font-playfair italic text-[#e8702a]">Trading Titans</span> Before Real Money?
          </h2>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-white/15 text-white/60 text-xs uppercase tracking-wider">
                  <th className="py-3 px-4">Feature</th>
                  <th className="py-3 px-4 text-emerald-400">Trading Titans Paper Trading</th>
                  <th className="py-3 px-4 text-red-400">Real Demat Broker</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10 text-white/80">
                <tr>
                  <td className="py-3.5 px-4 font-semibold text-white">Financial Capital Risk</td>
                  <td className="py-3.5 px-4 text-emerald-400 font-medium">₹0 &middot; Fictional Demo Cash</td>
                  <td className="py-3.5 px-4 text-red-400 font-medium">100% Real Money At Risk</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-semibold text-white">KYC / Aadhaar / PAN Required</td>
                  <td className="py-3.5 px-4 text-emerald-400 font-medium">None &middot; Start in 10 seconds</td>
                  <td className="py-3.5 px-4 text-red-400 font-medium">Mandatory verification &amp; wait</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-semibold text-white">SEBI Statistics</td>
                  <td className="py-3.5 px-4 text-emerald-400 font-medium">Learn before becoming a statistic</td>
                  <td className="py-3.5 px-4 text-red-400 font-medium">93% of F&amp;O retail traders lose money</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-semibold text-white">Loss Autopsy Diagnostics</td>
                  <td className="py-3.5 px-4 text-emerald-400 font-medium">Built-in error analysis &amp; learning</td>
                  <td className="py-3.5 px-4 text-red-400 font-medium">Painful loss with no educational review</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-semibold text-white">Multi-Asset Breadth</td>
                  <td className="py-3.5 px-4 text-emerald-400 font-medium">NSE, BSE, US Stocks, F&amp;O &amp; Crypto in 1 app</td>
                  <td className="py-3.5 px-4 text-red-400 font-medium">Separate accounts &amp; margin locks</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        {/* Structured SEO FAQ Section */}
        <div className="max-w-3xl mx-auto mb-16">
          <h2 className="text-3xl font-bold text-center mb-8 flex items-center justify-center gap-3">
            <HelpCircle className="w-8 h-8 text-[#e8702a]" />
            Frequently Asked Questions
          </h2>
          <div className="space-y-4">
            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">What is a paper trading app in India?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                A paper trading app is a risk-free stock market simulator that allows you to buy and sell stocks, options, and futures using simulated demo cash while tracking real-time market price movements. It allows beginner and intermediate traders to test strategies, learn order execution, and build discipline without losing real money.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">How much virtual money do I start with on Trading Titans?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Every newly registered account starts with ₹1,100 free virtual demo cash (or ₹500 in guest mode). As you clear trading challenges, maintain daily streaks, and make disciplined trades, you earn additional virtual cash grants and XP.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Can I paper trade Nifty &amp; Bank Nifty options?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Yes! Trading Titans includes a full F&amp;O simulator with realistic option chains, call and put buying/selling, strike selection, modeled lot sizes, and simulated Greeks to help you understand options behavior before trading on a live broker.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Can I withdraw money earned in paper trading?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                No. Trading Titans is strictly an educational simulation software operated by Kashivwealth Management LLP. All demo balances have zero real-world monetary value and cannot be withdrawn, redeemed, or transferred.
              </p>
            </div>
          </div>
        </div>

        {/* Closing CTA */}
        <div className="text-center bg-gradient-to-br from-[#e8702a]/20 via-zinc-900 to-black border border-white/15 p-10 rounded-3xl">
          <h2 className="text-3xl md:text-4xl font-extrabold mb-4">Start Paper Trading Today</h2>
          <p className="text-white/75 max-w-xl mx-auto mb-8 text-sm md:text-base">
            Join thousands of traders mastering Indian stocks, options, and crypto on Trading Titans without risking a single rupee.
          </p>
          <a
            href={PLAY_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-3 bg-[#e8702a] hover:bg-[#d2611f] text-white font-bold text-base px-9 py-4 rounded-full transition-all shadow-xl hover:scale-105"
          >
            Download Free on Google Play
          </a>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
