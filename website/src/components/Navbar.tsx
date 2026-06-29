import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Menu, X, ArrowUpRight } from 'lucide-react';

interface NavbarProps {
  currentPage: string;
  onPageChange: (page: 'home' | 'about' | 'features') => void;
}

export const Navbar: React.FC<NavbarProps> = ({ currentPage, onPageChange }) => {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <nav className="fixed top-0 left-0 w-full z-50 py-4 md:py-6 bg-[#EDEEF5]/40 backdrop-blur-md border-b border-black/[0.03]">
      <div className="grid grid-cols-12 max-w-7xl mx-auto px-6 md:px-12 items-center">
        
        {/* Left: Brand Logo and Title */}
        <div 
          onClick={() => onPageChange('home')}
          className="col-span-6 md:col-span-3 flex items-center gap-3 cursor-pointer select-none"
        >
          <img 
            src="/logo.svg" 
            className="w-9 h-9 rounded-lg shadow-sm border border-black/10" 
            alt="Trading Titans Logo" 
          />
          <span 
            className="text-xl font-black tracking-tight text-[#1a1a1a]" 
            style={{ fontFamily: 'var(--font-display), sans-serif' }}
          >
            TRADING TITANS
          </span>
        </div>

        {/* Center: Desktop Nav Links */}
        <div className="hidden md:flex col-span-6 justify-center gap-8">
          <button 
            onClick={() => onPageChange('about')} 
            className={`text-sm font-semibold transition-colors cursor-pointer ${currentPage === 'about' ? 'text-[#1a1a1a]' : 'text-zinc-500 hover:text-black'}`}
          >
            About
          </button>
          <button 
            onClick={() => onPageChange('features')} 
            className={`text-sm font-semibold transition-colors cursor-pointer ${currentPage === 'features' ? 'text-[#1a1a1a]' : 'text-zinc-500 hover:text-black'}`}
          >
            Features
          </button>
        </div>

        {/* Right Actions */}
        <div className="col-span-6 md:col-span-3 flex justify-end items-center gap-4">
          <button 
            onClick={() => {
              onPageChange('home');
              setTimeout(() => {
                const el = document.getElementById('waitlist');
                el?.scrollIntoView({ behavior: 'smooth' });
              }, 100);
            }} 
            className="bg-[#1a1a1a] hover:bg-zinc-800 text-white text-xs md:text-sm font-bold px-5 py-2.5 rounded-full flex items-center gap-1.5 transition-all shadow-sm cursor-pointer"
          >
            Pre-register <ArrowUpRight className="w-4 h-4" />
          </button>
          
          {/* Mobile Menu Icon */}
          <button 
            onClick={() => setIsOpen(!isOpen)} 
            className="md:hidden p-2 text-zinc-900 hover:bg-zinc-200/50 rounded-full transition-all"
          >
            {isOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
          </button>
        </div>
      </div>

      {/* Mobile Menu Drawer */}
      <AnimatePresence>
        {isOpen && (
          <motion.div 
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.3, ease: 'easeInOut' }}
            className="md:hidden w-full bg-white/95 border-b border-zinc-200 backdrop-blur-md overflow-hidden"
          >
            <div className="flex flex-col px-6 py-6 gap-4">
              <button 
                onClick={() => { onPageChange('about'); setIsOpen(false); }} 
                className="text-left text-base font-semibold text-zinc-700 hover:text-black transition-colors"
              >
                About
              </button>
              <button 
                onClick={() => { onPageChange('features'); setIsOpen(false); }} 
                className="text-left text-base font-semibold text-zinc-700 hover:text-black transition-colors"
              >
                Features
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};
