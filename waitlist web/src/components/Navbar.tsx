import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Menu, X, ArrowUpRight } from 'lucide-react';

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <nav className="fixed top-0 left-0 w-full z-50 py-6 md:py-10 bg-gradient-to-b from-[#f1f1f1]/80 to-transparent backdrop-blur-[2px]">
      <div className="grid grid-cols-12 max-w-7xl mx-auto px-6 md:px-12 items-center">
        
        {/* Left: Brand Logo and Title */}
        <div className="col-span-4 md:col-span-3 flex items-center gap-3">
          {/* Clover Geometric SVG */}
          <svg className="w-8 h-8 fill-[#1a1a1a]" viewBox="0 0 24 24">
            <path d="M12 2a4 4 0 00-4 4c0 1.66 1.01 3.08 2.45 3.7A4 4 0 006 12a4 4 0 004 4c0 1.66 1.01 3.08 2.45 3.7A4 4 0 0018 16a4 4 0 00-4-4c0-1.66-1.01-3.08-2.45-3.7A4 4 0 0018 8a4 4 0 00-4-4 4 4 0 00-2-2zM8 8a2 2 0 114 0 2 2 0 01-4 0zm6 8a2 2 0 114 0 2 2 0 01-4 0z"/>
          </svg>
          <span 
            className="text-2xl font-bold tracking-tight text-[#1a1a1a]" 
            style={{ fontFamily: 'var(--font-display), sans-serif' }}
          >
            mėntality
          </span>
        </div>

        {/* Center: Desktop Nav Links */}
        <div className="hidden md:flex col-span-6 justify-center gap-8">
          <a href="#futures" class="text-sm font-medium text-zinc-600 hover:text-black transition-colors lowercase">service</a>
          <a href="#options" class="text-sm font-medium text-zinc-600 hover:text-black transition-colors lowercase">patient resources</a>
          <a href="#about" class="text-sm font-medium text-zinc-600 hover:text-black transition-colors lowercase">about us</a>
          <a href="#education" class="text-sm font-medium text-zinc-600 hover:text-black transition-colors lowercase">education center</a>
        </div>

        {/* Right Actions */}
        <div className="col-span-8 md:col-span-3 flex justify-end items-center gap-4">
          <a href="#help" className="hidden sm:inline-block text-sm font-semibold text-zinc-900 hover:underline">find help</a>
          <button className="bg-[#1a1a1a] hover:bg-zinc-800 text-white text-sm font-medium px-5 py-2.5 rounded-full flex items-center gap-2 transition-all">
            get started <ArrowUpRight className="w-4 h-4" />
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
            <div className="flex flex-col px-6 py-8 gap-5">
              <a href="#futures" onClick={() => setIsOpen(false)} className="text-base text-zinc-700 hover:text-black transition-colors lowercase">service</a>
              <a href="#options" onClick={() => setIsOpen(false)} className="text-base text-zinc-700 hover:text-black transition-colors lowercase">patient resources</a>
              <a href="#about" onClick={() => setIsOpen(false)} className="text-base text-zinc-700 hover:text-black transition-colors lowercase">about us</a>
              <a href="#education" onClick={() => setIsOpen(false)} className="text-base text-zinc-700 hover:text-black transition-colors lowercase">education center</a>
              <hr className="border-zinc-200" />
              <a href="#help" onClick={() => setIsOpen(false)} className="text-base font-semibold text-zinc-900">find help</a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};
