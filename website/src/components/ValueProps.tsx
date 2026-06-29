import React from 'react';
import { motion } from 'motion/react';
import { ShieldCheck, LineChart, Layers, Trophy, GraduationCap, Bell } from 'lucide-react';

const ITEMS = [
  {
    icon: ShieldCheck,
    title: '0% real risk',
    body: 'Trade with virtual money on live markets. Build skill and confidence without ever risking real capital.',
  },
  {
    icon: LineChart,
    title: 'Real NSE market data',
    body: 'Live stock prices, real option chains with actual strikes and lot sizes, and authentic candlestick charts.',
  },
  {
    icon: Layers,
    title: 'Stocks, F&O & crypto',
    body: 'Practice equity delivery, intraday, futures, options and crypto — all in one disciplined simulator.',
  },
  {
    icon: Trophy,
    title: 'Compete & climb',
    body: 'Track your P&L, measure your edge and rise up the leaderboard against other traders.',
  },
  {
    icon: GraduationCap,
    title: 'Learn by doing',
    body: 'Guided flows and instant feedback turn every trade into a lesson — the fastest way to actually learn.',
  },
  {
    icon: Bell,
    title: 'Smart alerts',
    body: 'Pending-order reminders, fills and market events keep you in the loop, just like a real trading desk.',
  },
];

export const ValueProps: React.FC = () => {
  return (
    <section id="features" className="relative bg-black py-24 px-6 md:px-12">
      <div className="max-w-6xl mx-auto">
        <div className="max-w-2xl">
          <span className="text-xs font-bold uppercase tracking-[0.2em] text-[#e8702a]">Why Trading Titans</span>
          <h2 className="mt-3 text-4xl md:text-5xl font-playfair italic text-white leading-[1.05]" style={{ letterSpacing: '-0.03em' }}>
            Everything you need to trade like a pro
          </h2>
          <p className="mt-4 text-white/70 text-base leading-relaxed">
            A full-fledged trading floor in your pocket — real data, real mechanics, zero financial risk.
          </p>
        </div>

        <div className="mt-14 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {ITEMS.map((it, i) => (
            <motion.div
              key={it.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-60px' }}
              transition={{ duration: 0.5, delay: i * 0.06 }}
              className="group rounded-3xl border border-white/10 bg-white/[0.03] p-7 hover:bg-white/[0.06] hover:border-white/20 transition-all"
            >
              <div className="w-12 h-12 rounded-2xl bg-[#e8702a]/15 text-[#e8702a] flex items-center justify-center group-hover:scale-105 transition-transform">
                <it.icon className="w-6 h-6" />
              </div>
              <h3 className="mt-5 text-lg font-semibold text-white">{it.title}</h3>
              <p className="mt-2 text-sm text-white/65 leading-relaxed">{it.body}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};
