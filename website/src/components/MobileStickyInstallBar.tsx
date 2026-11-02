import React, { useState, useEffect } from 'react';
import { X, Star, Download } from 'lucide-react';
import { PLAY_STORE_URL } from '../lib/config';

export const MobileStickyInstallBar: React.FC = () => {
  const [dismissed, setDismissed] = useState(true);

  useEffect(() => {
    // Only show if not previously dismissed in this session
    const isDismissed = sessionStorage.getItem('tt_sticky_dismissed');
    if (!isDismissed) {
      setDismissed(false);
    }
  }, []);

  const handleDismiss = () => {
    sessionStorage.setItem('tt_sticky_dismissed', '1');
    setDismissed(true);
  };

  if (dismissed) return null;

  return (
    <aside aria-label="App download prompt" className="md:hidden fixed bottom-3 left-3 right-3 z-50 animate-in fade-in slide-in-from-bottom-4 duration-300">
      <div className="bg-zinc-950/95 backdrop-blur-xl border border-white/20 rounded-2xl p-3 shadow-2xl flex items-center justify-between gap-3 text-white">
        <div className="flex items-center gap-2.5 min-w-0">
          <img
            src="/logo.svg"
            alt="Trading Titans App"
            className="w-10 h-10 rounded-xl border border-white/20 shrink-0 bg-black"
          />
          <div className="min-w-0">
            <div className="text-xs font-bold truncate">Trading Titans</div>
            <div className="flex items-center gap-1 text-[11px] text-emerald-400 font-medium">
              <span className="flex items-center text-amber-400">
                <Star className="w-3 h-3 fill-amber-400 text-amber-400 inline" />
                <span className="ml-0.5 font-bold">4.7</span>
              </span>
              <span className="text-white/40">&middot;</span>
              <span className="text-white/70 truncate">₹1,100 Demo Cash</span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          <a
            href={PLAY_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="bg-[#e8702a] hover:bg-[#d2611f] text-white text-xs font-bold px-3.5 py-2 rounded-xl flex items-center gap-1.5 shadow-md active:scale-95 transition-all"
          >
            <Download className="w-3.5 h-3.5" />
            Install Free
          </a>
          <button
            onClick={handleDismiss}
            aria-label="Dismiss download prompt"
            className="p-1.5 text-white/50 hover:text-white rounded-lg hover:bg-white/10"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>
    </aside>
  );
};
