import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Menu, X } from 'lucide-react';

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

      {/* Right: Pre-register */}
      <div className="flex items-center gap-3">
        <button
          onClick={() => scrollTo('prereg')}
          className="hidden md:block bg-white text-gray-900 text-sm font-semibold px-6 py-2.5 rounded-full hover:bg-gray-100 transition-colors"
        >
          Pre-register
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
              <button
                onClick={() => { scrollTo('prereg'); setIsOpen(false); }}
                className="mt-1 bg-white text-gray-900 text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-gray-100"
              >
                Pre-register
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};
