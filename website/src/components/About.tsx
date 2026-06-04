import React from 'react';
import { motion } from 'motion/react';
import { Target, Award, Heart, CheckCircle2 } from 'lucide-react';

export const About: React.FC = () => {
  return (
    <motion.div 
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.5 }}
      className="min-h-screen w-full bg-[#EDEEF5] pt-28 md:pt-36 pb-20 px-6 md:px-12 lg:px-16"
    >
      <div className="max-w-6xl mx-auto space-y-16">
        
        {/* Header Block */}
        <div className="text-center md:text-left space-y-6">
          <motion.div 
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/60 border border-black/5 shadow-sm"
          >
            <span className="text-[10px] font-extrabold uppercase tracking-widest text-[#1a1a1a]">Our Philosophy</span>
          </motion.div>
          
          <motion.h1 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="text-4xl md:text-6xl font-black tracking-tight leading-none text-black"
            style={{ fontFamily: 'var(--font-display), sans-serif' }}
          >
            redefining trading <br />
            <span className="text-zinc-500">from gamble to discipline.</span>
          </motion.h1>
          
          <motion.p 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="text-lg text-zinc-600 max-w-2xl font-medium leading-relaxed"
          >
            Most retail traders lose money because of psychological biases, greed, and lack of real practice. Trading Titans combines structural market learning with psychological training to build profitable habits.
          </motion.p>
        </div>

        {/* Core Pillars Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          
          {/* Pillar 1 */}
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
            className="bg-white rounded-3xl border border-black/5 p-8 shadow-sm flex flex-col justify-between hover:shadow-md transition-all duration-300 group"
          >
            <div className="space-y-6">
              <div className="w-12 h-12 rounded-2xl bg-black text-[#9fff00] flex items-center justify-center shadow-sm">
                <Target className="w-6 h-6" />
              </div>
              <h3 className="text-xl font-bold text-black" style={{ fontFamily: 'var(--font-display), sans-serif' }}>0% Capital Risk</h3>
              <p className="text-sm text-zinc-500 leading-relaxed">
                Test complex option chains, options trading, and futures strategies in real-time without depositing a single Rupee. Learn to survive before risking real funds.
              </p>
            </div>
            <div className="mt-8 flex items-center gap-2 text-xs font-bold text-zinc-400 group-hover:text-black transition-colors">
              <span>LEARN RESILIENCE</span>
            </div>
          </motion.div>

          {/* Pillar 2 */}
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5 }}
            className="bg-white rounded-3xl border border-black/5 p-8 shadow-sm flex flex-col justify-between hover:shadow-md transition-all duration-300 group"
          >
            <div className="space-y-6">
              <div className="w-12 h-12 rounded-2xl bg-black text-[#9fff00] flex items-center justify-center shadow-sm">
                <Heart className="w-6 h-6" />
              </div>
              <h3 className="text-xl font-bold text-black" style={{ fontFamily: 'var(--font-display), sans-serif' }}>Trade Autopsy</h3>
              <p className="text-sm text-zinc-500 leading-relaxed">
                dissect and review executed trades. Get custom lessons, advice, and insights on your profits or losses to fix execution mistakes and prevent overtrading.
              </p>
            </div>
            <div className="mt-8 flex items-center gap-2 text-xs font-bold text-zinc-400 group-hover:text-black transition-colors">
              <span>DISSECT TRADES</span>
            </div>
          </motion.div>

          {/* Pillar 3 */}
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.6 }}
            className="bg-white rounded-3xl border border-black/5 p-8 shadow-sm flex flex-col justify-between hover:shadow-md transition-all duration-300 group"
          >
            <div className="space-y-6">
              <div className="w-12 h-12 rounded-2xl bg-black text-[#9fff00] flex items-center justify-center shadow-sm">
                <Award className="w-6 h-6" />
              </div>
              <h3 className="text-xl font-bold text-black" style={{ fontFamily: 'var(--font-display), sans-serif' }}>Capital Top-Ups</h3>
              <p className="text-sm text-zinc-500 leading-relaxed">
                Need more mock capital? Easily top up your virtual trading balance with demo funds packages starting from ₹199 to test large-scale futures and options setups.
              </p>
            </div>
            <div className="mt-8 flex items-center gap-2 text-xs font-bold text-zinc-400 group-hover:text-black transition-colors">
              <span>MANAGE CAPITAL</span>
            </div>
          </motion.div>

        </div>

        {/* Detailed Values/Stats Section */}
        <div className="bg-white/40 backdrop-blur-md rounded-3xl border border-white/40 p-8 md:p-12 shadow-sm grid grid-cols-1 md:grid-cols-2 gap-10">
          <div className="space-y-6">
            <h3 className="text-2xl font-black text-black" style={{ fontFamily: 'var(--font-display), sans-serif' }}>Why Practice Simulator Matters</h3>
            <p className="text-sm text-zinc-600 leading-relaxed">
              Paper trading fails when it lacks feedback or execution speed. Trading Titans uses real stock feeds and custom options chains, giving you the real feel of Zerodha or Groww platforms without the drawdown panic.
            </p>
            <div className="grid grid-cols-2 gap-4 pt-2">
              <div className="flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-[#9fff00]" />
                <span className="text-xs font-bold text-zinc-700">Real F&O Chains</span>
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-[#9fff00]" />
                <span className="text-xs font-bold text-zinc-700">Live Mock Execution</span>
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-[#9fff00]" />
                <span className="text-xs font-bold text-zinc-700">Trade Autopsy</span>
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-[#9fff00]" />
                <span className="text-xs font-bold text-zinc-700">Discipline Badges</span>
              </div>
            </div>
          </div>
          <div className="flex items-center justify-center relative min-h-[220px]">
            {/* Visual branding container */}
            <div className="w-48 h-48 rounded-3xl bg-[#BA7517] flex items-center justify-center shadow-lg relative overflow-hidden group">
              <div className="absolute inset-0 bg-gradient-to-tr from-[#6B3A08] to-[#BA7517] opacity-90"></div>
              <img src="/logo.svg" className="w-32 h-32 relative z-10 drop-shadow-md group-hover:scale-105 transition-transform duration-500" alt="Titan Logo" />
            </div>
          </div>
        </div>

      </div>
    </motion.div>
  );
};
