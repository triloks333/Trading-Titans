import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Menu, X } from 'lucide-react';
import { PLAY_STORE_URL } from '../lib/config';

const LINKS = [
  { label: 'Features', id: 'features' },
  { label: 'How it works', id: 'how' },
  { label: 'Rewards', id: 'rewards' },
];

const scrollTo = (id: string) => {
  if (id === 'top') {
    window.scrollTo({ top: 0, behavior: 'smooth' });
    return;
  }
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
};

/** Open the Google Play listing. The app is live, so there is no fallback. */
const goDownload = () => {
  window.open(PLAY_STORE_URL, '_blank', 'noopener,noreferrer');
};

/**
 * The web app, proxied in at /app (see vercel.json).
 *
 * One link covers log in, sign up and dashboard: /app shows the auth screen when
 * there is no session and the dashboard when there is, and its auth screen has
 * both sign-in and registration on it. Three separate buttons would be three
 * routes to the same page.
 *
 * Same tab on purpose — this is our own app, not an outbound link, and a new tab
 * would orphan the back button.
 */
const WEB_APP_URL = '/app';

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [active, setActive] = useState('home');

  return (
    <nav className="fixed top-0 left-0 right-0 z-[100] flex items-center justify-between p-4 sm:p-5">
      {/* Left: logo + wordmark */}
      <button
        onClick={() => { scrollTo('top'); setActive('home'); }}
        className="flex items-center gap-2.5 cursor-pointer select-none"
      >
        <img src="/logo.svg" className="w-7 h-7 rounded-md border border-white/15" alt="Trading Titans" />
        <span className="text-white text-2xl font-playfair italic">Trading Titans</span>
      </button>

      {/* Center pill */}
      <div className="hidden md:flex absolute left-1/2 -translate-x-1/2 bg-white/15 backdrop-blur-md border border-white/25 rounded-full px-2 py-2 items-center gap-1">
        {LINKS.map((l) => (
          <button
            key={l.id}
            onClick={() => { scrollTo(l.id); setActive(l.id); }}
            className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${
              active === l.id ? 'bg-white/20 text-white' : 'text-white/80 hover:bg-white/20 hover:text-white'
            }`}
          >
            {l.label}
          </button>
        ))}
      </div>

      {/* Right: web app + download */}
      <div className="flex items-center gap-3">
        {/* Two actions, not three. "Log in" and "Trade on web" both pointed at
            /app, so the second was a louder duplicate of the first and made the
            bar read as a row of competing buttons. */}
        <a
          href={WEB_APP_URL}
          className="hidden md:block text-white/85 text-sm font-medium px-4 py-2.5 rounded-full hover:bg-white/15 hover:text-white transition-colors"
        >
          Log in
        </a>
        <button
          onClick={goDownload}
          className="hidden md:block bg-white text-gray-900 text-sm font-semibold px-6 py-2.5 rounded-full hover:bg-gray-100 transition-colors"
        >
          Download free
        </button>
        <button
          onClick={() => setIsOpen(!isOpen)}
          className="md:hidden p-2 text-white bg-white/10 backdrop-blur-md border border-white/20 rounded-full"
        >
          {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
      </div>

      {/* Mobile drawer */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.25 }}
            className="md:hidden absolute top-full right-4 mt-2 w-56 bg-zinc-900/95 backdrop-blur-md border border-white/15 rounded-2xl overflow-hidden shadow-xl"
          >
            <div className="flex flex-col p-3 gap-1">
              {LINKS.map((l) => (
                <button
                  key={l.id}
                  onClick={() => { scrollTo(l.id); setIsOpen(false); }}
                  className="text-left px-4 py-2.5 rounded-xl text-sm font-medium text-white/85 hover:bg-white/10"
                >
                  {l.label}
                </button>
              ))}
              <a
                href={WEB_APP_URL}
                onClick={() => setIsOpen(false)}
                className="px-4 py-2.5 rounded-xl text-sm font-medium text-white/85 hover:bg-white/10"
              >
                Log in
              </a>
              <button
                onClick={() => { goDownload(); setIsOpen(false); }}
                className="mt-1 bg-white text-gray-900 text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-gray-100"
              >
                Download free
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};
