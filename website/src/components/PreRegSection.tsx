import React from 'react';
import { motion } from 'motion/react';
import { Gift } from 'lucide-react';
import { PlayStoreButton } from './PlayStoreButton';
import { PREREG_GIFT_AMOUNT } from '../lib/config';

export const PreRegSection: React.FC = () => {
  return (
    <section id="rewards" className="relative bg-zinc-950 py-24 px-6 md:px-12 border-t border-white/5">
      <span id="prereg" className="block relative -top-24" />
      <div className="max-w-5xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 28 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.6 }}
          className="relative overflow-hidden rounded-[2.5rem] border border-white/10 bg-gradient-to-br from-[#e8702a]/20 via-zinc-900 to-black p-8 md:p-14"
        >
          <div className="absolute -top-20 -right-20 w-72 h-72 bg-[#e8702a]/20 blur-[120px] rounded-full pointer-events-none" />

          <div className="relative flex flex-col items-center text-center">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/10 border border-white/20 backdrop-blur-md">
              <Gift className="w-4 h-4 text-[#9fff00]" />
              <span className="text-xs font-bold uppercase tracking-widest text-white">Pre-registration gift</span>
            </div>

            <h2 className="mt-6 text-4xl md:text-6xl font-playfair italic text-white leading-[1.02]" style={{ letterSpacing: '-0.03em' }}>
              Get {PREREG_GIFT_AMOUNT} in virtual cash, free
            </h2>
            <p className="mt-4 max-w-xl text-white/75 text-base leading-relaxed">
              Pre-register on Google Play today. The moment we launch, your wallet is topped up with{' '}
              {PREREG_GIFT_AMOUNT} of practice cash so you can start trading from day one.
            </p>

            {/* Primary CTA */}
            <div className="mt-10 flex flex-col items-center gap-3">
              <PlayStoreButton />
              <a href="/prereg-terms" className="text-[11px] text-white/55 hover:text-white font-semibold underline underline-offset-2">
                Pre-registration reward terms apply
              </a>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};
