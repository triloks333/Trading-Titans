import React from 'react';
import { motion } from 'motion/react';
import { LineChart, ShieldAlert, Compass, Activity, Zap } from 'lucide-react';

export const Features: React.FC = () => {
  const featuresList = [
    {
      icon: <LineChart className="w-6 h-6 text-black" />,
      title: "Real-time F&O & Stock Trading",
      badge: "SIMULATED TRADE",
      description: "Practice executing mock positions across F&O, stocks, and crypto with real market pricing feeds and interactive option chain visualization."
    },
    {
      icon: <Compass className="w-6 h-6 text-black" />,
      title: "What-If Simulator",
      badge: "RISK ANALYSIS",
      description: "A sandbox to test hypothetical price changes and forecast outcomes for stocks and options strategies before placing virtual trades."
    },
    {
      icon: <ShieldAlert className="w-6 h-6 text-black" />,
      title: "Trade Autopsy Insights",
      badge: "POST-TRADE AUDIT",
      description: "Dissect completed trades to record entry reasons, view performance logs, and review customized lessons for profits or losses."
    },
    {
      icon: <Activity className="w-6 h-6 text-black" />,
      title: "Portfolio Analytics",
      badge: "PERFORMANCE METRICS",
      description: "Review comprehensive performance stats, track profit/loss ratios, average hold times, and overall win rate percentage."
    },
    {
      icon: <Zap className="w-6 h-6 text-black" />,
      title: "Demo Capital Top-Ups",
      badge: "VIRTUAL WALLET",
      description: "Get more simulated trading capital to test bigger positions, with virtual wallet top-up packages starting from ₹199 (up to ₹10,00,000)."
    }
  ];

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
            <span className="text-[10px] font-extrabold uppercase tracking-widest text-[#1a1a1a]">Powerful Features</span>
          </motion.div>
          
          <motion.h1 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="text-4xl md:text-6xl font-black tracking-tight leading-none text-black"
            style={{ fontFamily: 'var(--font-display), sans-serif' }}
          >
            designed like a broker. <br />
            <span className="text-zinc-500">structured like a school.</span>
          </motion.h1>
          
          <motion.p 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="text-lg text-zinc-600 max-w-2xl font-medium leading-relaxed"
          >
            Explore a complete suite of mock trading tools crafted to replicate real Indian market environments (NSE/BSE futures, options, and stocks).
          </motion.p>
        </div>

        {/* Features Bento Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {featuresList.map((feat, idx) => (
            <motion.div
              key={idx}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.15 * idx }}
              className="bg-white/70 backdrop-blur-sm border border-white/40 p-6 rounded-3xl shadow-sm hover:shadow-md transition-all duration-300 flex flex-col justify-between"
            >
              <div className="space-y-4">
                <div className="w-10 h-10 rounded-xl bg-black/5 flex items-center justify-center">
                  {feat.icon}
                </div>
                
                <div className="space-y-1">
                  <span className="text-[9px] font-extrabold uppercase tracking-widest text-zinc-400">
                    {feat.badge}
                  </span>
                  <h3 className="text-lg font-extrabold text-black" style={{ fontFamily: 'var(--font-display), sans-serif' }}>
                    {feat.title}
                  </h3>
                </div>

                <p className="text-xs text-zinc-500 leading-relaxed font-medium">
                  {feat.description}
                </p>
              </div>
            </motion.div>
          ))}
        </div>

      </div>
    </motion.div>
  );
};
