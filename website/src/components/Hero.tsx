import React, { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { ArrowRight, Shield, Zap, Sparkles } from 'lucide-react';

export const Hero: React.FC = () => {
  const [email, setEmail] = useState('');
  const [isSuccess, setIsSuccess] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  
  // Countdown state
  const [timeLeft, setTimeLeft] = useState({
    days: 20,
    hours: 0,
    minutes: 0,
    seconds: 0
  });

  const supabaseUrl = "https://bftvimnhpoiuoyryyiff.supabase.co";
  const supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak";

  useEffect(() => {
    // Set target date 20 days from current date (June 4, 2026) -> June 24, 2026
    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 20);
    targetDate.setHours(0, 0, 0, 0);

    const interval = setInterval(() => {
      const now = new Date().getTime();
      const difference = targetDate.getTime() - now;

      if (difference <= 0) {
        clearInterval(interval);
        setTimeLeft({ days: 0, hours: 0, minutes: 0, seconds: 0 });
      } else {
        const d = Math.floor(difference / (1000 * 60 * 60 * 24));
        const h = Math.floor((difference % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
        const m = Math.floor((difference % (1000 * 60 * 60)) / (1000 * 60));
        const s = Math.floor((difference % (1000 * 60)) / 1000);
        setTimeLeft({ days: d, hours: h, minutes: m, seconds: s });
      }
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const handleJoin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;

    setIsSubmitting(true);
    setErrorMsg('');

    try {
      const response = await fetch(`${supabaseUrl}/rest/v1/waitlist`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': supabaseAnonKey,
          'Authorization': `Bearer ${supabaseAnonKey}`,
          'Prefer': 'return=representation'
        },
        body: JSON.stringify({ email })
      });

      if (response.ok) {
        setIsSuccess(true);
      } else {
        const errJson = await response.json();
        if (errJson.message && errJson.message.includes("duplicate")) {
          setErrorMsg("You have already joined the waitlist!");
        } else {
          setErrorMsg(errJson.message || "Failed to submit. Please try again.");
        }
      }
    } catch (err) {
      setErrorMsg("Connection error. Please check your network.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <section className="relative min-h-screen w-full flex flex-col items-center justify-start overflow-hidden bg-[#EDEEF5] pt-24 md:pt-32 pb-16">
      
      {/* Background Video Wrapper */}
      <div className="absolute top-[15vh] sm:top-[20vh] left-0 w-full h-[85vh] sm:h-[100vh] z-0 pointer-events-none">
        <video 
          autoPlay 
          loop 
          muted 
          playsInline 
          className="w-full h-full object-cover opacity-80 mix-blend-multiply"
        >
          <source 
            src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260603_132049_036591b8-6e92-4760-b94c-a7ea6eef315c.mp4" 
            type="video/mp4" 
          />
        </video>
        <div className="absolute top-0 left-0 w-full h-32 bg-gradient-to-b from-[#EDEEF5] to-transparent"></div>
        <div className="absolute bottom-0 left-0 w-full h-32 bg-gradient-to-t from-[#EDEEF5] to-transparent"></div>
      </div>

      {/* Grid Container for Layout */}
      <div className="max-w-7xl w-full mx-auto px-6 md:px-12 lg:px-16 relative z-10 grid grid-cols-12 gap-x-4 md:gap-x-8 pt-8 md:pt-16">
        <div className="col-span-12 lg:col-span-10 lg:col-start-2 text-center md:text-left space-y-8">
          
          {/* Tagline Badge */}
          <motion.div 
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6 }}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/60 border border-black/5 shadow-sm backdrop-blur-md"
          >
            <span className="w-2 h-2 rounded-full bg-[#9fff00] animate-pulse"></span>
            <span className="text-xs font-extrabold uppercase tracking-widest text-[#1a1a1a]">Going Live on Play Store soon</span>
          </motion.div>

          {/* Main Title Heading */}
          <motion.h1 
            initial={{ opacity: 0, y: 15 }} 
            animate={{ opacity: 1, y: 0 }} 
            transition={{ duration: 0.8 }}
            className="text-4xl md:text-6xl lg:text-7xl font-extrabold tracking-tight leading-none text-[#1a1a1a] select-none"
            style={{ 
              fontFamily: 'var(--font-display), sans-serif',
              textShadow: '0 0 40px rgba(255, 255, 255, 0.95), 0 0 15px rgba(255, 255, 255, 0.9), 0 0 5px rgba(255, 255, 255, 0.6)'
            }}
          >
            rebuild your <br />
            <span className="text-[#8e8e8e]">trading mentality with</span> <br />
            <span className="text-black">trading titans</span> <br />
            <span className="text-[#8e8e8e]">0% risk 100% learning and</span>{' '}
            <span className="w-[42px] md:w-[62px] lg:w-[82px] h-[22px] md:h-[32px] lg:h-[38px] border-[2px] border-[#1a1a1a] rounded-full inline-flex items-center justify-center mx-1 bg-white/40 backdrop-blur-sm">
              <span className="w-2.5 h-2.5 rounded-full bg-black"></span>
            </span>{' '}
            <span className="text-[#8e8e8e]">mental wellbeing.</span>
          </motion.h1>

          {/* Interactive Countdown Timer */}
          <motion.div
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.1 }}
            className="flex flex-col gap-3 max-w-md w-full bg-white/75 backdrop-blur-md border border-white/40 p-6 rounded-2xl shadow-lg"
          >
            <span className="text-xs font-bold uppercase tracking-widest text-zinc-500 text-center md:text-left">Going Live in</span>
            <div className="grid grid-cols-4 gap-4 text-center">
              <div className="bg-black/5 rounded-xl p-3">
                <div className="text-2xl md:text-3xl font-extrabold text-black">{timeLeft.days}</div>
                <div className="text-[10px] uppercase font-bold text-zinc-500">Days</div>
              </div>
              <div className="bg-black/5 rounded-xl p-3">
                <div className="text-2xl md:text-3xl font-extrabold text-black">{timeLeft.hours}</div>
                <div className="text-[10px] uppercase font-bold text-zinc-500">Hrs</div>
              </div>
              <div className="bg-black/5 rounded-xl p-3">
                <div className="text-2xl md:text-3xl font-extrabold text-black">{timeLeft.minutes}</div>
                <div className="text-[10px] uppercase font-bold text-zinc-500">Mins</div>
              </div>
              <div className="bg-black/5 rounded-xl p-3">
                <div className="text-2xl md:text-3xl font-extrabold text-black">{timeLeft.seconds}</div>
                <div className="text-[10px] uppercase font-bold text-zinc-500">Secs</div>
              </div>
            </div>
          </motion.div>

          {/* Search/Waitlist Capsule Form */}
          <motion.div 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.2 }}
            className="max-w-md w-full"
            id="waitlist"
          >
            {!isSuccess ? (
              <form onSubmit={handleJoin} className="bg-white rounded-xl border border-black/10 p-1.5 pl-4 flex items-center shadow-md relative">
                <input 
                  type="email" 
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter email to join waitlist..."
                  className="w-full bg-transparent py-3 text-zinc-900 placeholder-zinc-400 focus:outline-none text-sm font-medium"
                />
                <button 
                  type="submit" 
                  disabled={isSubmitting}
                  className="bg-[#1a1a1a] hover:bg-zinc-800 text-[#9fff00] w-10 h-10 rounded-full flex items-center justify-center transition-all shrink-0 mr-1 shadow-sm disabled:opacity-50"
                >
                  <ArrowRight className="w-5 h-5 text-white" />
                </button>
              </form>
            ) : (
              <div className="bg-black text-[#9fff00] rounded-xl px-5 py-4 text-sm font-semibold text-center border border-zinc-800 shadow-md">
                ✓ You're on the list! Verification sent.
              </div>
            )}
            {errorMsg && (
              <p className="text-xs text-red-500 mt-2 ml-4 font-semibold">{errorMsg}</p>
            )}
          </motion.div>
        </div>
      </div>

      {/* Feature Bento Grid Summary */}
      <div className="max-w-7xl w-full mx-auto px-6 md:px-12 lg:px-16 mt-16 relative z-10 grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white/40 backdrop-blur-md border border-white/30 p-6 rounded-2xl shadow-sm flex items-start gap-4">
          <div className="p-3 rounded-xl bg-black/5 text-[#1a1a1a]"><Shield className="w-6 h-6" /></div>
          <div>
            <h3 className="text-base font-bold text-black">0% Financial Risk</h3>
            <p className="text-sm text-zinc-500 mt-1">Learn trading options, futures, and stock strategies with zero real capital risk in real time.</p>
          </div>
        </div>
        <div className="bg-white/40 backdrop-blur-md border border-white/30 p-6 rounded-2xl shadow-sm flex items-start gap-4">
          <div className="p-3 rounded-xl bg-black/5 text-[#1a1a1a]"><Zap className="w-6 h-6" /></div>
          <div>
            <h3 className="text-base font-bold text-black">100% Immersive Learning</h3>
            <p className="text-sm text-zinc-500 mt-1">Interactive modules, mock trading screens, live option chains, and real execution feedback.</p>
          </div>
        </div>
        <div className="bg-white/40 backdrop-blur-md border border-white/30 p-6 rounded-2xl shadow-sm flex items-start gap-4">
          <div className="p-3 rounded-xl bg-black/5 text-[#1a1a1a]"><Sparkles className="w-6 h-6" /></div>
          <div>
            <h3 className="text-base font-bold text-black">Mental Wellbeing</h3>
            <p className="text-sm text-zinc-500 mt-1">Veda/Surya yantra inspired aesthetics designed to build a calm, disciplined mind for market execution.</p>
          </div>
        </div>
      </div>

      {/* Bottom anchors */}
      <div className="w-full max-w-7xl mx-auto px-6 md:px-12 lg:px-16 mt-12 flex justify-between text-xs text-zinc-500 uppercase tracking-widest font-semibold relative z-10">
        <div>© 2026</div>
        <div>trading titans</div>
      </div>
    </section>
  );
};
