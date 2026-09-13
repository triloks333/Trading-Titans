import React from 'react';
import { motion } from 'motion/react';
import { STARTING_CASH } from '../lib/config';

/** The loop the app is built around: earn, practise, learn, repeat. */
const STEPS = [
  {
    n: '01',
    title: `Start with ${STARTING_CASH} free`,
    body: 'Sign up and your virtual wallet is funded straight away. No payment, no plan, nothing to unlock.',
  },
  {
    n: '02',
    title: 'Complete tasks, earn more',
    body: 'Clear challenges, keep a daily streak and hit milestones. Every one credits demo cash and XP to your account.',
  },
  {
    n: '03',
    title: 'Spend it learning the market',
    body: 'Put that balance to work on live Indian stocks, US stocks, F&O and crypto. Real prices, real mechanics, fictional money.',
  },
  {
    n: '04',
    title: 'Review, level up, repeat',
    body: 'Run an autopsy on your losses, climb the Titan levels and the weekly league. Each cycle you understand a bit more.',
  },
];

export const HowItWorks: React.FC = () => {
  return (
    <section id="how" className="relative bg-zinc-950 py-24 px-6 md:px-12 border-y border-white/5">
      <div className="max-w-6xl mx-auto">
        <div className="text-center max-w-2xl mx-auto">
          <span className="text-xs font-bold uppercase tracking-[0.2em] text-[#e8702a]">How it works</span>
          <h2 className="mt-3 text-4xl md:text-5xl font-playfair italic text-white leading-[1.05]" style={{ letterSpacing: '-0.03em' }}>
            Earn it, then trade it
          </h2>
          <p className="mt-4 text-white/70 text-base leading-relaxed">
            A loop that keeps you coming back, and teaches you something every time round.
          </p>
        </div>

        <div className="mt-16 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-8">
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
