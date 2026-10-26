import React from 'react'
import { motion } from 'motion/react'
import { Sparkles } from 'lucide-react'
import { PlayStoreButton } from './PlayStoreButton'
import { GUEST_STARTING_CASH, STARTING_CASH } from '../lib/config'

/**
 * Closing download CTA. Replaces the old PreRegSection: the app is live and free,
 * so the pitch is "download it now", not "pre-register and wait".
 *
 * Keeps the `#prereg` anchor alongside `#download` so any older link, or a
 * bookmark, still lands here.
 */
export const DownloadSection: React.FC = () => {
  return (
    <section
      id="rewards"
      className="relative bg-zinc-950 py-24 px-6 md:px-12 border-t border-white/5"
    >
      <span id="download" className="block relative -top-24" />
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
              <Sparkles className="w-4 h-4 text-[#9fff00]" />
              <span className="text-xs font-bold uppercase tracking-widest text-white">
                16 challenges &middot; XP &middot; Titan levels
              </span>
            </div>

            <h2
              className="mt-6 text-4xl md:text-6xl font-playfair italic text-white leading-[1.02]"
              style={{ letterSpacing: '-0.03em' }}
            >
              Download today. It&apos;s free.
            </h2>
            <p className="mt-4 max-w-xl text-white/75 text-base leading-relaxed">
              Start with {STARTING_CASH} in virtual cash on signup (or {GUEST_STARTING_CASH} as guest), then earn more by clearing
              challenges and keeping your streak alive. Spend it learning on real Indian
              stocks, US stocks, F&amp;O and crypto — with none of your own money at risk.
            </p>

            <div className="mt-10 flex flex-col items-center gap-3">
              <PlayStoreButton />
              <p className="text-[11px] text-white/55 font-medium">
                Simulated market trading only. Demo cash holds zero monetary value.{' '}
                <a
                  href="/terms"
                  className="hover:text-white underline underline-offset-2"
                >
                  Terms apply
                </a>
                .
              </p>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  )
}
