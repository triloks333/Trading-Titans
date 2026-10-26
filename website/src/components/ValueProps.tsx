import React from 'react';
import { motion } from 'motion/react';
import { Target, Flame, Trophy, GraduationCap, Layers, Coins } from 'lucide-react';

/**
 * Positioning: a gamified way to learn the market, not a plain simulator.
 *
 * Every number here is real, taken from the seeded challenge catalogue in
 * `supabase/migrations/20260805000000_gamification_and_app_flags.sql` — 16
 * challenges across performance, habit, breadth, learning and social, with the
 * reward and XP values quoted below.
 */
const ITEMS = [
  {
    icon: Target,
    title: '16 challenges to clear',
    body: 'First Blood for your first order. Diversifier for holding five symbols. Globetrotter for Indian, US and crypto at once. Each one pays demo cash and XP.',
  },
  {
    icon: Coins,
    title: 'Tasks pay your practice balance',
    body: 'Rewards run from ₹500 for a green day up to ₹25,000 for the Century Club. Earn a bigger balance through skill and daily tasks, or accelerate your practice.',
  },
  {
    icon: Flame,
    title: 'Streaks build the habit',
    body: 'Open the app three days running, then fourteen, then thirty. Trading well is a habit before it is a skill, so the streaks reward showing up.',
  },
  {
    icon: Trophy,
    title: 'XP, Titan levels & leaderboard',
    body: 'Every challenge adds XP, XP builds your Titan level, and the weekly league ranks you against other traders. Progress you can actually see.',
  },
  {
    icon: GraduationCap,
    title: 'Learning is a challenge too',
    body: 'Pass the glossary quiz, run an autopsy on five losing trades, set alerts and watch them trigger. The app pays you to understand what went wrong.',
  },
  {
    icon: Layers,
    title: 'Real markets underneath',
    body: 'Live Indian stocks, US stocks, F&O with real strikes and lot sizes, and crypto. The game is the wrapper; the market data is genuine.',
  },
];

export const ValueProps: React.FC = () => {
  return (
    <section id="features" className="relative bg-black py-24 px-6 md:px-12">
      <div className="max-w-6xl mx-auto">
        <div className="max-w-2xl">
          <span className="text-xs font-bold uppercase tracking-[0.2em] text-[#e8702a]">Learn by playing</span>
          <h2 className="mt-3 text-4xl md:text-5xl font-playfair italic text-white leading-[1.05]" style={{ letterSpacing: '-0.03em' }}>
            Turn learning the market into a game you want to finish
          </h2>
          <p className="mt-4 text-white/70 text-base leading-relaxed">
            Most people quit learning to trade because it is dry and expensive. Here you complete
            tasks, earn virtual money, and spend it practising on real market data.
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
