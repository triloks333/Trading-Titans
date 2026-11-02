import React from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { PLAY_STORE_URL } from '../lib/config';
import { Layers, ShieldCheck, HelpCircle, Activity, Smartphone } from 'lucide-react';

export const OptionsSimulatorPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-6 md:px-12 max-w-5xl mx-auto">
        {/* Hero Section */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-purple-500/30 bg-purple-500/10 text-xs text-purple-400 font-semibold mb-4">
            <span className="w-2 h-2 rounded-full bg-purple-400 animate-pulse" />
            Nifty &amp; Bank Nifty Derivatives Simulator
          </div>
          <h1 className="text-4xl md:text-6xl font-extrabold tracking-tight mb-6 leading-tight">
            Free Options Trading Simulator for <span className="font-playfair italic text-[#e8702a]">Nifty &amp; Bank Nifty</span>
          </h1>
          <p className="text-lg md:text-xl text-white/75 leading-relaxed mb-8">
            Master Call (CE) and Put (PE) options strategies without risking your capital. Practice with live NSE option chain strikes, real lot sizes, and modeled Greek decay before entering live markets.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a
              href={PLAY_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-3 bg-[#e8702a] hover:bg-[#d2611f] text-white font-semibold text-base px-8 py-3.5 rounded-full transition-all shadow-lg hover:scale-105"
            >
              <Smartphone className="w-5 h-5" />
              Practice Options on App Free
            </a>
            <a
              href="/app"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 bg-white/10 hover:bg-white/15 text-white font-semibold text-base px-8 py-3.5 rounded-full border border-white/20 transition-all"
            >
              Open Web Simulator
            </a>
          </div>
          <p className="text-xs text-white/50 mt-3">Start with ₹1,100 simulated cash &middot; Zero Demat account or margin pledge needed</p>
        </div>

        {/* Core Options Simulator Features */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16">
          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-purple-500/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-purple-500/15 flex items-center justify-center text-purple-400 mb-5">
              <Layers className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">Live NSE Option Chains</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              Explore weekly and monthly expiry contracts for Nifty 50, Bank Nifty, FinNifty, and stock options with In-The-Money (ITM), At-The-Money (ATM), and Out-Of-The-Money (OTM) strikes.
            </p>
          </div>

          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-amber-500/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-amber-500/15 flex items-center justify-center text-amber-400 mb-5">
              <Activity className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">Simulated Greeks &amp; Theta Decay</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              Experience firsthand how Delta, Gamma, Vega, and Theta time decay erode option premiums into expiry. Understand why buying far OTM options leads to 100% loss.
            </p>
          </div>

          <div className="bg-zinc-900/60 border border-white/10 p-7 rounded-2xl hover:border-emerald-500/40 transition-colors">
            <div className="w-12 h-12 rounded-xl bg-emerald-500/15 flex items-center justify-center text-emerald-400 mb-5">
              <ShieldCheck className="w-6 h-6" />
            </div>
            <h3 className="text-xl font-bold mb-2">Safe Testing for 93% Stat</h3>
            <p className="text-sm text-white/70 leading-relaxed">
              SEBI reports show 93% of individual traders lose money in F&amp;O with average losses exceeding ₹1.25 Lakh. Trading Titans is built to let you make rookie mistakes with zero financial damage.
            </p>
          </div>
        </div>

        {/* Common Strategies You Can Test */}
        <div className="bg-zinc-900/70 border border-white/15 rounded-3xl p-8 md:p-10 mb-16 shadow-2xl">
          <div className="max-w-2xl mx-auto text-center mb-8">
            <h2 className="text-2xl md:text-3xl font-bold mb-3">
              Popular <span className="font-playfair italic text-[#e8702a]">F&amp;O Strategies</span> You Can Paper Trade
            </h2>
            <p className="text-sm text-white/60">
              Test direction, volatility, and delta-neutral strategies across live market sessions without capital risk.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-5 rounded-2xl bg-white/5 border border-white/10">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-base text-white">Nifty Long Call / Long Put</span>
                <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-blue-500/20 text-blue-300">Directional</span>
              </div>
              <p className="text-xs text-white/70 leading-relaxed">
                Profit from aggressive intraday momentum breakouts. Understand the impact of implied volatility (IV) crush and rapid theta decay when momentum stalls.
              </p>
            </div>

            <div className="p-5 rounded-2xl bg-white/5 border border-white/10">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-base text-white">Bull Call / Bear Put Spread</span>
                <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300">Hedging</span>
              </div>
              <p className="text-xs text-white/70 leading-relaxed">
                Cap your maximum loss while taking a directional view. See how selling a further OTM leg offsets premium expense and protects your risk profile.
              </p>
            </div>

            <div className="p-5 rounded-2xl bg-white/5 border border-white/10">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-base text-white">Short Straddle &amp; Strangle</span>
                <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/20 text-amber-300">Theta Decay</span>
              </div>
              <p className="text-xs text-white/70 leading-relaxed">
                Practice non-directional options selling on expiry days. Learn how sudden index spikes challenge margin and require strict stop losses.
              </p>
            </div>

            <div className="p-5 rounded-2xl bg-white/5 border border-white/10">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-base text-white">Iron Condor / Iron Butterfly</span>
                <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-purple-500/20 text-purple-300">Defined Risk</span>
              </div>
              <p className="text-xs text-white/70 leading-relaxed">
                Deploy 4-legged options combinations with defined wings to capture range-bound premiums while eliminating catastrophic tail risk.
              </p>
            </div>
          </div>
        </div>

        {/* Options Greeks 101 Table */}
        <div className="bg-zinc-900/60 border border-white/10 rounded-3xl p-8 mb-16">
          <h2 className="text-2xl font-bold mb-4 text-center">Options Greeks Cheat Sheet</h2>
          <p className="text-sm text-white/60 text-center mb-6 max-w-xl mx-auto">
            Understanding the Greeks is essential before risking real money on Zerodha, Groww, or Angel One.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-white/15 text-white/60 text-xs uppercase tracking-wider">
                  <th className="py-3 px-4">Greek</th>
                  <th className="py-3 px-4">What It Measures</th>
                  <th className="py-3 px-4">Practical Impact on Your Trade</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10 text-white/80">
                <tr>
                  <td className="py-3.5 px-4 font-bold text-emerald-400">Delta (&Delta;)</td>
                  <td className="py-3.5 px-4">Rate of premium change per ₹1 move in spot</td>
                  <td className="py-3.5 px-4 text-xs">ATM options have ~0.50 Delta; deep ITM approaches 1.00.</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-bold text-amber-400">Theta (&Theta;)</td>
                  <td className="py-3.5 px-4">Daily premium loss due to time decay</td>
                  <td className="py-3.5 px-4 text-xs">Accelerates drastically in the final 48 hours before Thursday expiry.</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-bold text-blue-400">Gamma (&Gamma;)</td>
                  <td className="py-3.5 px-4">Rate of change of Delta</td>
                  <td className="py-3.5 px-4 text-xs">Causes explosive "Hero or Zero" premium surges on expiry afternoons.</td>
                </tr>
                <tr>
                  <td className="py-3.5 px-4 font-bold text-purple-400">Vega (&nu;)</td>
                  <td className="py-3.5 px-4">Sensitivity to changes in Implied Volatility (IV)</td>
                  <td className="py-3.5 px-4 text-xs">A drop in India VIX can crush option buyer premiums even if spot is flat.</td>
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
              <h3 className="text-lg font-bold text-white mb-2">Can I paper trade Nifty and Bank Nifty weekly options?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Yes. Trading Titans supports real-time option chain quotes for major Indian benchmark indices including Nifty 50 and Bank Nifty across weekly and monthly contracts.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Do I need a Demat account or Aadhaar verification?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                No Demat or KYC verification is required. Since Trading Titans is an educational simulator with virtual cash, you can install the app and begin simulating trades immediately.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Are brokerage and STT calculated in the options simulator?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Yes. To provide realistic simulation rather than deceptive paper profits, Trading Titans accounts for standard Indian exchange turnover charges, Securities Transaction Tax (STT), and GST deductions.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Is the options simulator free?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Yes, Trading Titans is free to download and use with starter virtual cash. Optional Pro subscriptions and Plus packs are available for traders who want advanced analytics, portfolio insights, and higher virtual trading limits.
              </p>
            </div>
          </div>
        </div>

        {/* Bottom CTA */}
        <div className="text-center bg-gradient-to-br from-purple-900/20 via-zinc-900 to-black border border-white/15 p-10 rounded-3xl">
          <h2 className="text-3xl md:text-4xl font-extrabold mb-4">Master Options Trading Without the Heartbreak</h2>
          <p className="text-white/75 max-w-xl mx-auto mb-8 text-sm md:text-base">
            Don't let market makers take your hard-earned salary. Train your instincts on Trading Titans first.
          </p>
          <a
            href={PLAY_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-3 bg-[#e8702a] hover:bg-[#d2611f] text-white font-bold text-base px-9 py-4 rounded-full transition-all shadow-xl hover:scale-105"
          >
            Download Free Android App
          </a>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
