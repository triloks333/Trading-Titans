import React from 'react';
import { motion } from 'motion/react';

const STEPS = [
  {
    n: '01',
    title: 'Create your free account',
    body: 'Sign up in seconds and get a virtual wallet loaded with practice cash to start trading right away.',
  },
  {
    n: '02',
    title: 'Trade real markets, risk-free',
    body: 'Buy and sell stocks, futures, options and crypto on live prices. Watch your positions and P&L move in real time.',
  },
  {
    n: '03',
    title: 'Learn, compete & level up',
    body: 'Review every trade, sharpen your strategy, and climb the leaderboard as your skills grow.',
  },
];

export const HowItWorks: React.FC = () => {
  return (
    <section id="how" className="relative bg-zinc-950 py-24 px-6 md:px-12 border-y border-white/5">
      <div className="max-w-6xl mx-auto">
        <div className="text-center max-w-2xl mx-auto">
          <span className="text-xs font-bold uppercase tracking-[0.2em] text-[#e8702a]">How it works</span>
          <h2 className="mt-3 text-4xl md:text-5xl font-playfair italic text-white leading-[1.05]" style={{ letterSpacing: '-0.03em' }}>
            From zero to confident in three steps
          </h2>
        </div>

        <div className="mt-16 grid grid-cols-1 md:grid-cols-3 gap-8">
          {STEPS.map((s, i) => (
            <motion.div
              key={s.n}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-60px' }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              className="relative"
            >
              <span className="text-6xl font-playfair italic text-white/15">{s.n}</span>
              <h3 className="mt-3 text-xl font-semibold text-white">{s.title}</h3>
              <p className="mt-2 text-sm text-white/65 leading-relaxed">{s.body}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};
