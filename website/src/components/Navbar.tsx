import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Menu, X } from 'lucide-react';
import { PLAY_STORE_URL } from '../lib/config';

const LINKS = [
  { label: 'Features', id: 'features', href: '/#features' },
  { label: 'How it works', id: 'how', href: '/#how' },
  { label: 'Blog', id: 'blog', href: '/blog' },
  { label: 'Plans', id: 'plans', href: '/topup' },
  { label: 'About', id: 'about', href: '/about' },
  { label: 'Contact', id: 'contact', href: '/contact' },
];

const handleNavClick = (id: string, href?: string) => {
  if (href && !href.startsWith('/#')) {
    window.location.href = href;
    return;
  }
  if (window.location.pathname !== '/') {
    window.location.href = href || '/';
    return;
  }
  if (id === 'top') {
    window.scrollTo({ top: 0, behavior: 'smooth' });
    return;
  }
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
};

/** Open the Google Play listing. */
const goDownload = () => {
  window.open(PLAY_STORE_URL, '_blank', 'noopener,noreferrer');
};

const WEB_APP_URL = '/app';

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [active, setActive] = useState('home');

  return (
    <header className="fixed top-0 left-0 right-0 z-[100] flex flex-col pointer-events-none">
      {/* Top Corporate Legal Entity Verification Bar (Apple & Regulatory Verification) */}
      <div className="w-full bg-zinc-950/85 backdrop-blur-md border-b border-white/10 text-[11px] sm:text-xs text-white/70 py-1.5 px-4 text-center tracking-wide pointer-events-auto select-none">
        Trading Titans &middot; An Official Software Product of <strong className="text-white font-semibold">Kashivwealth Management LLP</strong>
      </div>

      <nav className="flex items-center justify-between p-3 sm:p-4 px-4 sm:px-6 relative pointer-events-auto">
        {/* Left: logo + wordmark + corporate subtitle */}
        <button
          onClick={() => { handleNavClick('top'); setActive('home'); }}
          className="flex items-center gap-2.5 cursor-pointer select-none text-left"
        >
          <img src="/logo.svg" className="w-8 h-8 rounded-md border border-white/15" alt="Trading Titans" />
          <div className="flex flex-col">
            <span className="text-white text-xl sm:text-2xl font-playfair italic leading-tight">Trading Titans</span>
            <span className="text-[9px] sm:text-[10px] uppercase tracking-wider text-white/60 font-semibold leading-none">by Kashivwealth Management LLP</span>
          </div>
        </button>

        {/* Center pill */}
        <div className="hidden md:flex absolute left-1/2 -translate-x-1/2 bg-white/15 backdrop-blur-md border border-white/25 rounded-full px-2 py-1.5 items-center gap-1">
          {LINKS.map((l) => (
            <button
              key={l.id}
              onClick={() => { handleNavClick(l.id, l.href); setActive(l.id); }}
              className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors cursor-pointer ${
                active === l.id ? 'bg-white/20 text-white' : 'text-white/80 hover:bg-white/20 hover:text-white'
              }`}
            >
              {l.label}
            </button>
          ))}
        </div>

        {/* Right: web app + download */}
        <div className="flex items-center gap-3">
          <a
            href={WEB_APP_URL}
            className="hidden md:block text-white/85 text-sm font-medium px-4 py-2 rounded-full hover:bg-white/15 hover:text-white transition-colors"
          >
            Log in
          </a>
          <button
            onClick={goDownload}
            className="hidden md:block bg-white text-gray-900 text-sm font-semibold px-5 py-2 rounded-full hover:bg-gray-100 transition-colors"
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
              className="md:hidden absolute top-full right-4 mt-2 w-64 bg-zinc-900/95 backdrop-blur-md border border-white/15 rounded-2xl overflow-hidden shadow-xl"
            >
              <div className="p-3 pb-2 border-b border-white/10 bg-white/5">
                <span className="block text-[10px] uppercase tracking-wider text-white/50 font-semibold">Corporate Operator</span>
                <span className="text-xs font-bold text-white">Kashivwealth Management LLP</span>
              </div>
              <div className="flex flex-col p-3 gap-1">
                {LINKS.map((l) => (
                  <button
                    key={l.id}
                    onClick={() => { handleNavClick(l.id, l.href); setIsOpen(false); }}
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
    </header>
  );
};
