import React from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { ShieldCheck, Target, Award, Users } from 'lucide-react';

export const AboutPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-6 md:px-12 max-w-5xl mx-auto">
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-white/20 bg-white/5 text-xs text-white/80 font-medium mb-4">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            Official Corporate &amp; Legal Profile
          </div>
          <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4">
            About <span className="font-playfair italic text-white">Trading Titans</span>
          </h1>
          <p className="text-lg text-white/70 leading-relaxed">
            Trading Titans is a premier financial technology and gamified simulation platform operated by{' '}
            <strong className="text-white">KashivWealth Management LLP</strong>.
          </p>
        </div>

        {/* Legal Identity Card */}
        <div className="bg-zinc-900/80 border border-white/15 rounded-2xl p-8 md:p-10 mb-12 shadow-2xl backdrop-blur-sm">
          <h2 className="text-2xl font-bold text-white mb-6 flex items-center gap-3">
            <ShieldCheck className="w-6 h-6 text-[#e8702a]" />
            Corporate Legal Entity Information
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-sm">
            <div className="bg-white/5 p-4 rounded-xl border border-white/10">
              <span className="block text-xs uppercase tracking-wider text-white/50 mb-1 font-semibold">Legal Company Name</span>
              <span className="text-base font-bold text-white">KashivWealth Management LLP</span>
            </div>
            <div className="bg-white/5 p-4 rounded-xl border border-white/10">
              <span className="block text-xs uppercase tracking-wider text-white/50 mb-1 font-semibold">Brand &amp; Product</span>
              <span className="text-base font-bold text-white">Trading Titans (Web &amp; Mobile App)</span>
            </div>
            <div className="bg-white/5 p-4 rounded-xl border border-white/10">
              <span className="block text-xs uppercase tracking-wider text-white/50 mb-1 font-semibold">Business Nature</span>
              <span className="text-white font-medium">Educational Technology &amp; Market Simulation Software</span>
            </div>
            <div className="bg-white/5 p-4 rounded-xl border border-white/10">
              <span className="block text-xs uppercase tracking-wider text-white/50 mb-1 font-semibold">Official Contact Email</span>
              <a href="mailto:support@thetradingtitans.com" className="text-[#e8702a] hover:underline font-medium">
                support@thetradingtitans.com
              </a>
            </div>
          </div>
        </div>

        {/* Business Mission & Vision */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16">
          <div className="bg-zinc-900/50 border border-white/10 p-6 rounded-2xl">
            <Target className="w-8 h-8 text-[#e8702a] mb-4" />
            <h3 className="text-lg font-bold text-white mb-2">Our Mission</h3>
            <p className="text-white/60 text-sm leading-relaxed">
              To democratise financial literacy by allowing anyone to experience real-market price dynamics, test strategies, and analyse market behaviors in a zero-risk simulated ecosystem.
            </p>
          </div>

          <div className="bg-zinc-900/50 border border-white/10 p-6 rounded-2xl">
            <Award className="w-8 h-8 text-[#e8702a] mb-4" />
            <h3 className="text-lg font-bold text-white mb-2">Simulated Only</h3>
            <p className="text-white/60 text-sm leading-relaxed">
              We operate exclusively as an educational simulation platform. We are not a broker, exchange, or investment adviser, and no actual securities or real money are ever bought, sold, or wagered.
            </p>
          </div>

          <div className="bg-zinc-900/50 border border-white/10 p-6 rounded-2xl">
            <Users className="w-8 h-8 text-[#e8702a] mb-4" />
            <h3 className="text-lg font-bold text-white mb-2">Global Markets</h3>
            <p className="text-white/60 text-sm leading-relaxed">
              Our simulator incorporates equities, derivatives, and crypto across major world exchanges including India (NSE), United States (Nasdaq/NYSE), Italy (Borsa Italiana), and Pakistan (PSX).
            </p>
          </div>
        </div>

        {/* Detailed Business Operations */}
        <div className="prose prose-invert max-w-none text-white/70 space-y-4 text-sm leading-relaxed border-t border-white/10 pt-10">
          <h2 className="text-xl font-bold text-white mb-4">Operations &amp; Platform Transparency</h2>
          <p>
            KashivWealth Management LLP builds software products that bring institutional-grade simulation tools to individual retail learners. Through Trading Titans, users have access to real-time quotes, technical charts, options chains, and order execution matching simulations without requiring real monetary deposits or brokerage accounts.
          </p>
          <p>
            Every user is provided virtual simulated capital upon signup to practise trading responsibly. All metrics, leaderboards, and achievements within the application are strictly virtual game elements designed for educational feedback.
          </p>
          <p>
            For any corporate, regulatory, or partnership inquiries, KashivWealth Management LLP can be reached directly at{' '}
            <a href="mailto:support@thetradingtitans.com" className="text-white underline">
              support@thetradingtitans.com
            </a>.
          </p>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
