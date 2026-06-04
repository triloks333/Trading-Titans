import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ArrowRight, Globe } from 'lucide-react';

export const Hero: React.FC = () => {
  const [email, setEmail] = useState('');
  const [isSuccess, setIsSuccess] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const supabaseUrl = "https://bftvimnhpoiuoyryyiff.supabase.co";
  const supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak";

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
    <section className="relative min-h-[110vh] sm:min-h-[140vh] w-full flex flex-col items-center justify-start overflow-hidden bg-[#EDEEF5]">
      
      {/* Background Video Wrapper */}
      <div className="absolute top-[15vh] sm:top-[20vh] left-0 w-full h-[95vh] sm:h-[120vh] z-0 pointer-events-none">
        <video 
          autoPlay 
          loop 
          muted 
          playsInline 
          className="w-full h-full object-cover opacity-100"
        >
          <source 
            src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260603_132049_036591b8-6e92-4760-b94c-a7ea6eef315c.mp4" 
            type="video/mp4" 
          />
        </video>
        {/* Soft mask to blend video into #EDEEF5 base */}
        <div className="absolute top-0 left-0 w-full h-24 sm:h-32 bg-gradient-to-b from-[#EDEEF5] to-transparent"></div>
        <div className="absolute bottom-0 left-0 w-full h-32 bg-gradient-to-t from-[#EDEEF5] to-transparent"></div>
      </div>

      {/* Grid Container for Layout */}
      <div className="max-w-7xl w-full mx-auto px-8 md:px-16 lg:px-20 relative z-10 grid grid-cols-12 gap-x-4 md:gap-x-8 pt-[35vh] sm:pt-[45vh]">
        <div className="col-span-12 md:col-span-10 md:col-start-2 text-center md:text-left space-y-8">
          
          {/* Main Title Heading */}
          <motion.h1 
            initial={{ opacity: 0, y: 15 }} 
            animate={{ opacity: 1, y: 0 }} 
            transition={{ duration: 0.8 }}
            className="text-4xl md:text-6xl lg:text-7xl font-extrabold tracking-tight leading-tight text-[#1a1a1a] select-none"
            style={{ fontFamily: 'var(--font-display), sans-serif' }}
          >
            rebuild your <br className="hidden md:inline" />
            <span className="text-[#8e8e8e]">trading mentality with trading titans</span> <br />
            <span className="text-[#8e8e8e]">0% risk 100% learning and</span>{' '}
            {/* Inline Eye Pupil Pill UI Element */}
            <span className="w-[42px] md:w-[62px] lg:w-[82px] h-[22px] md:h-[32px] lg:h-[38px] border-[2px] border-[#1a1a1a] rounded-full inline-flex items-center justify-center mx-1 bg-white/40 backdrop-blur-sm">
              <span className="w-2.5 h-2.5 rounded-full bg-black"></span>
            </span>{' '}
            <span className="text-[#8e8e8e]">your mental wellbeing.</span>
          </motion.h1>

          {/* Search/Waitlist Capsule Form */}
          <motion.div 
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, delay: 0.15 }}
            className="max-w-md w-full"
          >
            {!isSuccess ? (
              <form onSubmit={handleJoin} className="bg-white rounded-xl border border-black/[0.05] p-1 pl-4 flex items-center shadow-sm relative">
                <input 
                  type="email" 
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Ask me anything..."
                  className="w-full bg-transparent py-3 text-zinc-900 placeholder-zinc-400 focus:outline-none text-sm"
                />
                <button 
                  type="submit" 
                  disabled={isSubmitting}
                  className="bg-[#1a1a1a] hover:bg-zinc-800 text-white w-9 h-9 rounded-full flex items-center justify-center transition-all shrink-0 mr-1"
                >
                  <ArrowRight className="w-4 h-4" />
                </button>
              </form>
            ) : (
              <div className="bg-zinc-900 text-[#9fff00] rounded-xl px-5 py-4 text-sm font-semibold text-center border border-zinc-800 shadow-md">
                ✓ You're on the list! Verification sent.
              </div>
            )}
            {errorMsg && (
              <p className="text-xs text-red-500 mt-2 ml-4 font-semibold">{errorMsg}</p>
            )}
          </motion.div>
        </div>
      </div>

      {/* Absolute Middle Right Edge - Glassmorphic Language switcher */}
      <div className="absolute right-6 top-1/2 -translate-y-1/2 z-20 hidden md:flex flex-col gap-3">
        <div className="glass-panel px-3 py-1.5 rounded-full text-xs font-bold flex items-center gap-1.5 text-zinc-900 cursor-pointer shadow-sm glow-border">
          <Globe className="w-3.5 h-3.5" />
          <span>PL</span>
          <span class="text-zinc-400">|</span>
          <span class="text-[#9fff00] font-black">EN</span>
        </div>
      </div>

      {/* Bottom anchors */}
      <div className="absolute bottom-10 left-8 md:left-16 z-20 text-xs text-zinc-500 uppercase tracking-widest font-semibold">
        2024
      </div>
      <div className="absolute bottom-10 right-8 md:right-16 z-20 text-xs text-zinc-500 uppercase tracking-widest font-semibold">
        trading titans tools
      </div>
    </section>
  );
};
