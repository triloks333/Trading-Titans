import React, { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { ArrowRight, Gift } from 'lucide-react';
import { PlayStoreButton } from './PlayStoreButton';
import { PREREG_GIFT_AMOUNT } from '../lib/config';

const SUPABASE_URL = 'https://bftvimnhpoiuoyryyiff.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak';

const TARGET = new Date('2026-06-28T00:00:00+05:30');

export const PreRegSection: React.FC = () => {
  const [email, setEmail] = useState('');
  const [isSuccess, setIsSuccess] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [time, setTime] = useState({ days: 0, hours: 0, minutes: 0, seconds: 0 });

  useEffect(() => {
    const tick = () => {
      const diff = TARGET.getTime() - Date.now();
      if (diff <= 0) return setTime({ days: 0, hours: 0, minutes: 0, seconds: 0 });
      setTime({
        days: Math.floor(diff / 86400000),
        hours: Math.floor((diff % 86400000) / 3600000),
        minutes: Math.floor((diff % 3600000) / 60000),
        seconds: Math.floor((diff % 60000) / 1000),
      });
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  const handleJoin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    setIsSubmitting(true);
    setErrorMsg('');
    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/waitlist`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({ email }),
      });
      if (res.ok) {
        setIsSuccess(true);
      } else {
        const j = await res.json().catch(() => ({}));
        setErrorMsg(j.message?.includes('duplicate') ? "You're already on the list!" : j.message || 'Failed to submit. Please try again.');
      }
    } catch {
      setErrorMsg('Connection error. Please check your network.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const units = [
    { v: time.days, l: 'Days' },
    { v: time.hours, l: 'Hrs' },
    { v: time.minutes, l: 'Mins' },
    { v: time.seconds, l: 'Secs' },
  ];

  return (
    <section id="rewards" className="relative bg-zinc-950 py-24 px-6 md:px-12 border-t border-white/5">
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
              <Gift className="w-4 h-4 text-[#9fff00]" />
              <span className="text-xs font-bold uppercase tracking-widest text-white">Pre-registration gift</span>
            </div>

            <h2 className="mt-6 text-4xl md:text-6xl font-playfair italic text-white leading-[1.02]" style={{ letterSpacing: '-0.03em' }}>
              Get {PREREG_GIFT_AMOUNT} in virtual cash, free
            </h2>
            <p className="mt-4 max-w-xl text-white/75 text-base leading-relaxed">
              Pre-register on Google Play today. The moment we launch, your wallet is topped up with{' '}
              {PREREG_GIFT_AMOUNT} of practice cash so you can start trading from day one.
            </p>

            {/* Countdown */}
            <div className="mt-8 grid grid-cols-4 gap-3 sm:gap-4 max-w-md w-full">
              {units.map((u) => (
                <div key={u.l} className="bg-white/5 border border-white/10 rounded-2xl py-4">
                  <div className="text-2xl md:text-3xl font-extrabold text-white">{u.v}</div>
                  <div className="text-[10px] uppercase font-bold text-white/50 tracking-wider">{u.l}</div>
                </div>
              ))}
            </div>

            {/* Primary CTA */}
            <div className="mt-9 flex flex-col items-center gap-3">
              <PlayStoreButton />
              <a href="/prereg-terms" className="text-[11px] text-white/55 hover:text-white font-semibold underline underline-offset-2">
                Pre-registration reward terms apply
              </a>
            </div>

            {/* Secondary: email capture */}
            <div className="mt-10 w-full max-w-md">
              <span className="block text-xs font-bold uppercase tracking-widest text-white/45 mb-2">Or get notified by email</span>
              {!isSuccess ? (
                <form onSubmit={handleJoin} className="bg-white rounded-xl p-1.5 pl-4 flex items-center shadow-md">
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="Enter your email..."
                    className="w-full bg-transparent py-3 text-zinc-900 placeholder-zinc-400 focus:outline-none text-sm font-medium"
                  />
                  <button
                    type="submit"
                    disabled={isSubmitting}
                    className="bg-[#e8702a] hover:bg-[#d2611f] text-white w-10 h-10 rounded-full flex items-center justify-center transition-all shrink-0 disabled:opacity-50"
                  >
                    <ArrowRight className="w-5 h-5" />
                  </button>
                </form>
              ) : (
                <div className="bg-white/10 text-[#9fff00] rounded-xl px-5 py-4 text-sm font-semibold text-center border border-white/15">
                  ✓ You're on the list! We'll notify you the moment access opens.
                </div>
              )}
              {errorMsg && <p className="text-xs text-red-400 mt-2 font-semibold">{errorMsg}</p>}
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};
