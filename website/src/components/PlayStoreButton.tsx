import React from 'react';
import { PLAY_STORE_URL, isPlayStoreLive } from '../lib/config';

/** Official-style "Pre-register on Google Play" button.
 *
 * Reads the link from `src/lib/config.ts` (PLAY_STORE_URL). While that value
 * is empty, the button renders in a disabled "Link coming soon" state so the
 * layout/space is reserved and ready — just paste the URL into the config when
 * the Play listing goes live and this lights up automatically.
 */
const GooglePlayGlyph: React.FC<{ className?: string }> = ({ className }) => (
  <svg viewBox="0 0 512 512" className={className} aria-hidden="true">
    <path fill="#00D8FF" d="M48 24c-7 4-12 12-12 22v420c0 10 5 18 12 22l244-232L48 24z" />
    <path fill="#FFCE00" d="M388 224l-71-40-79 72 79 72 71-40c20-11 20-53 0-64z" />
    <path fill="#00F076" d="M48 24c2-1 5-1 8 0l276 156-44 44L48 24z" />
    <path fill="#FF3A44" d="M288 268l44 44L56 488c-3 1-6 1-8 0l240-220z" />
  </svg>
);

export const PlayStoreButton: React.FC<{ size?: 'lg' | 'md' }> = ({ size = 'lg' }) => {
  const live = isPlayStoreLive();
  const pad = size === 'lg' ? 'px-7 py-4' : 'px-5 py-3';

  const inner = (
    <>
      <GooglePlayGlyph className={size === 'lg' ? 'w-7 h-7' : 'w-6 h-6'} />
      <span className="flex flex-col items-start leading-tight">
        <span className="text-[10px] font-medium uppercase tracking-wider opacity-80">
          {live ? 'Pre-register on' : 'Pre-register now on'}
        </span>
        <span className={size === 'lg' ? 'text-lg font-bold' : 'text-base font-bold'}>
          Google Play
        </span>
      </span>
    </>
  );

  if (!live) {
    return (
      <div
        className={`inline-flex items-center gap-3 ${pad} rounded-2xl bg-white/10 text-white/80 border border-white/15 cursor-not-allowed select-none shadow-sm`}
        title="The Google Play pre-registration link will be added soon."
        aria-disabled="true"
      >
        {inner}
      </div>
    );
  }

  return (
    <a
      href={PLAY_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      className={`inline-flex items-center gap-3 ${pad} rounded-2xl bg-white text-[#1a1a1a] hover:bg-zinc-100 border border-white/20 transition-all shadow-md hover:shadow-lg`}
    >
      {inner}
    </a>
  );
};
