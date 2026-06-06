import React, { useState, useEffect, useRef } from 'react';
import { supabase } from '../lib/supabaseClient';
import { Shield, Sparkles, LogOut, Loader2, CheckCircle2, AlertCircle, Wallet, ArrowRight, Crown, Zap, Eye, EyeOff } from 'lucide-react';

interface Plan {
  id: string;
  name: string;
  price: number;
  cash: number;
  description: string;
  popular?: boolean;
  icon: React.ReactNode;
  color: string;
  gradient: string;
}

/* ───────────── floating particle background ───────────── */
const FloatingParticles: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    const particles: { x: number; y: number; r: number; dx: number; dy: number; o: number }[] = [];

    const resize = () => { canvas.width = window.innerWidth; canvas.height = window.innerHeight; };
    resize();
    window.addEventListener('resize', resize);

    for (let i = 0; i < 50; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        r: Math.random() * 2 + 0.5,
        dx: (Math.random() - 0.5) * 0.4,
        dy: (Math.random() - 0.5) * 0.4,
        o: Math.random() * 0.3 + 0.05,
      });
    }

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      particles.forEach((p) => {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(239, 159, 39, ${p.o})`;
        ctx.fill();
        p.x += p.dx; p.y += p.dy;
        if (p.x < 0 || p.x > canvas.width) p.dx *= -1;
        if (p.y < 0 || p.y > canvas.height) p.dy *= -1;
      });
      animId = requestAnimationFrame(draw);
    };
    draw();
    return () => { cancelAnimationFrame(animId); window.removeEventListener('resize', resize); };
  }, []);
  return <canvas ref={canvasRef} className="fixed inset-0 z-0 pointer-events-none" />;
};

/* ───────────── main page ───────────── */
export const TopupPage: React.FC = () => {
  const [session, setSession] = useState<any>(null);
  const [profile, setProfile] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [referralCode, setReferralCode] = useState('');
  const [formError, setFormError] = useState('');
  const [formSuccess, setFormSuccess] = useState('');
  const [formLoading, setFormLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [purchasingPlan, setPurchasingPlan] = useState<string | null>(null);
  const [paymentSuccess, setPaymentSuccess] = useState<boolean>(false);
  const [creditedAmount, setCreditedAmount] = useState<number>(0);
  const [hoveredPlan, setHoveredPlan] = useState<string | null>(null);

  const plans: Plan[] = [
    {
      id: 'titan_1l', name: 'Starter Boost', price: 199, cash: 100000,
      description: 'Perfect for beginners. Get ₹1,00,000 virtual cash to explore stock & crypto derivatives trading.',
      icon: <Zap className="w-6 h-6" />, color: '#3B8BF2', gradient: 'from-[#3B8BF2] to-[#1A73E8]',
    },
    {
      id: 'titan_5l', name: 'Titan Plus', price: 599, cash: 500000,
      description: 'Best value for serious traders. ₹5,00,000 virtual cash for scaling advanced option strategies.',
      popular: true,
      icon: <Crown className="w-6 h-6" />, color: '#EF9F27', gradient: 'from-[#EF9F27] to-[#BA7517]',
    },
    {
      id: 'titan_pro', name: 'Pro Launch', price: 999, cash: 1000000,
      description: 'Full capital freedom. ₹10,00,000 virtual cash to master large leverage & multi-leg setups.',
      icon: <Sparkles className="w-6 h-6" />, color: '#8B5CF6', gradient: 'from-[#8B5CF6] to-[#6D28D9]',
    }
  ];

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session) fetchProfile(session.user.id); else setLoading(false);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session) fetchProfile(session.user.id); else { setProfile(null); setLoading(false); }
    });
    const params = new URLSearchParams(window.location.search);
    const emailParam = params.get('email');
    if (emailParam) setEmail(emailParam);

    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    document.body.appendChild(script);

    return () => { subscription.unsubscribe(); document.body.removeChild(script); };
  }, []);

  const fetchProfile = async (userId: string) => {
    setLoading(true);
    try {
      const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).single();
      if (error) throw error;
      setProfile(data);
    } catch (err) { console.error('Error loading profile:', err); }
    finally { setLoading(false); }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault(); setFormLoading(true); setFormError(''); setFormSuccess('');
    try {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
    } catch (err: any) { setFormError(err.message || 'Login failed.'); setFormLoading(false); }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault(); setFormLoading(true); setFormError(''); setFormSuccess('');
    try {
      const { data: authData, error: authError } = await supabase.auth.signUp({ email: email.trim(), password });
      if (authError) throw authError;
      if (!authData.user) throw new Error('Signup failed.');
      const { error: profileError } = await supabase.from('profiles').insert([{
        id: authData.user.id, email: email.trim().toLowerCase(), name: name.trim(),
        referred_by: referralCode.trim() || null, wallet_balance: 10000.0,
        subscription_active: false, total_realized_pnl: 0.0,
      }]);
      if (profileError) throw profileError;
      setFormSuccess('Account created! Logging you in...');
      setTimeout(() => { supabase.auth.signInWithPassword({ email: email.trim(), password }); }, 1500);
    } catch (err: any) { setFormError(err.message || 'Registration failed.'); setFormLoading(false); }
  };

  const handleLogout = async () => { await supabase.auth.signOut(); };

  const handleTopup = async (plan: Plan) => {
    if (!session || !profile) return;
    setPurchasingPlan(plan.id);

    try {
      // ─── Step 1: Create a server-side Razorpay order ───
      const orderRes = await fetch('/api/create-order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan_id: plan.id, user_id: session.user.id }),
      });

      if (!orderRes.ok) {
        const err = await orderRes.json();
        throw new Error(err.error || 'Failed to create payment order');
      }

      const { order_id, key_id } = await orderRes.json();

      // ─── Step 2: Open Razorpay Checkout with the server-created order ───
      const options = {
        key: key_id,
        order_id: order_id, // Links payment to our verified order
        name: 'Trading Titans',
        description: `${plan.name} — ₹${plan.cash.toLocaleString()} Demo Cash`,
        image: 'https://thetradingtitans.com/app-icon.png',
        handler: async function (response: any) {
          // ─── Step 3: Verify payment server-side ───
          await verifyPayment(plan, response);
        },
        prefill: { name: profile.name || '', email: profile.email || '' },
        theme: { color: '#BA7517' },
        modal: {
          ondismiss: function () { setPurchasingPlan(null); },
        },
      };

      const rzp = (window as any).Razorpay ? new (window as any).Razorpay(options) : null;
      if (rzp) {
        rzp.open();
      } else {
        throw new Error('Razorpay Checkout SDK failed to load. Please refresh and try again.');
      }
    } catch (err: any) {
      console.error('Top-up error:', err);
      alert(err.message || 'Something went wrong. Please try again.');
      setPurchasingPlan(null);
    }
  };

  const verifyPayment = async (plan: Plan, razorpayResponse: any) => {
    try {
      // Send the Razorpay response to our server for cryptographic verification
      const verifyRes = await fetch('/api/verify-payment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          razorpay_order_id: razorpayResponse.razorpay_order_id,
          razorpay_payment_id: razorpayResponse.razorpay_payment_id,
          razorpay_signature: razorpayResponse.razorpay_signature,
          plan_id: plan.id,
          user_id: session.user.id,
          access_token: session.access_token, // Pass JWT for server-side Supabase auth
        }),
      });

      const result = await verifyRes.json();

      if (!verifyRes.ok || !result.success) {
        throw new Error(result.error || 'Payment verification failed');
      }

      // Payment verified & wallet credited server-side — update local UI
      setCreditedAmount(result.credited);
      setProfile((prev: any) => ({ ...prev, wallet_balance: result.new_balance }));
      setPaymentSuccess(true);
    } catch (err: any) {
      console.error('Payment verification error:', err);
      alert('Payment was received but verification encountered an issue. Your money is safe — please contact support if the balance is not updated.');
    } finally {
      setPurchasingPlan(null);
    }
  };

  const formatCash = (n: number) => {
    if (n >= 100000) return `₹${(n / 100000).toFixed(n % 100000 === 0 ? 0 : 1)}L`;
    if (n >= 1000) return `₹${(n / 1000).toFixed(0)}K`;
    return `₹${n}`;
  };

  /* ───── styles ───── */
  const pageStyle: React.CSSProperties = {
    minHeight: '100vh',
    background: 'linear-gradient(160deg, #0a0f1c 0%, #0d1527 30%, #111c33 60%, #0d1527 100%)',
    fontFamily: "'Inter', system-ui, -apple-system, sans-serif",
    color: '#f4f7fb',
    position: 'relative',
    overflow: 'hidden',
  };

  const glassCard: React.CSSProperties = {
    background: 'rgba(22, 37, 68, 0.45)',
    backdropFilter: 'blur(24px)',
    WebkitBackdropFilter: 'blur(24px)',
    border: '1px solid rgba(239, 159, 39, 0.12)',
    borderRadius: '24px',
    boxShadow: '0 8px 32px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.05)',
  };

  return (
    <div style={pageStyle}>
      <FloatingParticles />

      {/* Ambient glow blobs */}
      <div style={{ position: 'absolute', top: '-120px', right: '-80px', width: '400px', height: '400px', background: 'radial-gradient(circle, rgba(239,159,39,0.08) 0%, transparent 70%)', borderRadius: '50%', pointerEvents: 'none' }} />
      <div style={{ position: 'absolute', bottom: '-100px', left: '-60px', width: '350px', height: '350px', background: 'radial-gradient(circle, rgba(26,115,232,0.06) 0%, transparent 70%)', borderRadius: '50%', pointerEvents: 'none' }} />

      {/* ─── HEADER ─── */}
      <header style={{
        position: 'sticky', top: 0, zIndex: 50,
        background: 'rgba(13, 21, 39, 0.8)',
        backdropFilter: 'blur(20px)',
        borderBottom: '1px solid rgba(239,159,39,0.08)',
        padding: '16px 24px',
      }}>
        <div style={{ maxWidth: '1200px', margin: '0 auto', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <a href="/" style={{ display: 'flex', alignItems: 'center', gap: '12px', textDecoration: 'none' }}>
            <img src="/app-icon.png" alt="Trading Titans" style={{ width: '40px', height: '40px', borderRadius: '10px' }} />
            <div>
              <span style={{ fontWeight: 800, fontSize: '16px', letterSpacing: '2px', color: '#fff', textTransform: 'uppercase' as const, display: 'block', lineHeight: 1.2 }}>
                Trading Titans
              </span>
              <span style={{ fontSize: '10px', color: '#EF9F27', fontWeight: 600, letterSpacing: '1.5px', textTransform: 'uppercase' as const }}>
                Billing Portal
              </span>
            </div>
          </a>
          {session && (
            <button
              onClick={handleLogout}
              style={{
                display: 'flex', alignItems: 'center', gap: '8px',
                padding: '8px 16px', borderRadius: '12px',
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid rgba(255,255,255,0.08)',
                color: '#91A3B8', fontSize: '13px', fontWeight: 600,
                cursor: 'pointer', transition: 'all 0.2s',
              }}
              onMouseEnter={(e) => { e.currentTarget.style.background = 'rgba(255,255,255,0.08)'; e.currentTarget.style.color = '#fff'; }}
              onMouseLeave={(e) => { e.currentTarget.style.background = 'rgba(255,255,255,0.04)'; e.currentTarget.style.color = '#91A3B8'; }}
            >
              <LogOut style={{ width: '14px', height: '14px' }} />
              <span>Sign Out</span>
            </button>
          )}
        </div>
      </header>

      {/* ─── CONTENT ─── */}
      <main style={{ position: 'relative', zIndex: 10, maxWidth: '1200px', margin: '0 auto', padding: '40px 24px 60px' }}>

        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '20px', paddingTop: '120px' }}>
            <div style={{ width: '56px', height: '56px', borderRadius: '50%', background: 'rgba(239,159,39,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Loader2 style={{ width: '28px', height: '28px', color: '#EF9F27', animation: 'spin 1s linear infinite' }} />
            </div>
            <p style={{ fontSize: '14px', fontWeight: 600, color: '#627D98' }}>Loading your account...</p>
          </div>

        ) : !session ? (
          /* ────── AUTH FORM ────── */
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: '40px' }}>
            {/* Decorative top icon */}
            <div style={{
              width: '72px', height: '72px', borderRadius: '20px',
              background: 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 8px 32px rgba(239,159,39,0.25)',
              marginBottom: '28px',
            }}>
              <img src="/app-icon.png" alt="" style={{ width: '48px', height: '48px', borderRadius: '12px' }} />
            </div>

            <h1 style={{ fontSize: '28px', fontWeight: 800, color: '#fff', marginBottom: '8px', textAlign: 'center' }}>
              {isSignUp ? 'Create Your Account' : 'Welcome Back'}
            </h1>
            <p style={{ fontSize: '14px', color: '#627D98', marginBottom: '32px', textAlign: 'center', maxWidth: '380px', lineHeight: 1.6 }}>
              {isSignUp
                ? 'Sign up to manage your Trading Titans wallet and purchase demo cash top-ups.'
                : 'Sign in to your Trading Titans account to top up your demo wallet balance.'}
            </p>

            <div style={{ ...glassCard, width: '100%', maxWidth: '440px', padding: '32px' }}>
              {formError && (
                <div style={{ background: 'rgba(217,48,37,0.08)', border: '1px solid rgba(217,48,37,0.2)', borderRadius: '14px', padding: '14px 16px', display: 'flex', alignItems: 'flex-start', gap: '12px', marginBottom: '20px' }}>
                  <AlertCircle style={{ width: '18px', height: '18px', color: '#D93025', flexShrink: 0, marginTop: '1px' }} />
                  <span style={{ fontSize: '13px', fontWeight: 500, color: '#ff6b6b' }}>{formError}</span>
                </div>
              )}
              {formSuccess && (
                <div style={{ background: 'rgba(15,157,88,0.08)', border: '1px solid rgba(15,157,88,0.2)', borderRadius: '14px', padding: '14px 16px', display: 'flex', alignItems: 'flex-start', gap: '12px', marginBottom: '20px' }}>
                  <CheckCircle2 style={{ width: '18px', height: '18px', color: '#0F9D58', flexShrink: 0, marginTop: '1px' }} />
                  <span style={{ fontSize: '13px', fontWeight: 500, color: '#4ade80' }}>{formSuccess}</span>
                </div>
              )}

              <form onSubmit={isSignUp ? handleSignUp : handleLogin}>
                {isSignUp && (
                  <div style={{ marginBottom: '18px' }}>
                    <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: '#91A3B8', letterSpacing: '1px', textTransform: 'uppercase' as const, marginBottom: '8px' }}>Full Name</label>
                    <input type="text" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Enter your name"
                      style={{ width: '100%', padding: '14px 16px', borderRadius: '14px', border: '1px solid rgba(255,255,255,0.08)', background: 'rgba(13,21,39,0.6)', color: '#fff', fontSize: '14px', outline: 'none', transition: 'border-color 0.2s', boxSizing: 'border-box' }}
                      onFocus={(e) => e.currentTarget.style.borderColor = 'rgba(239,159,39,0.4)'}
                      onBlur={(e) => e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)'}
                    />
                  </div>
                )}

                <div style={{ marginBottom: '18px' }}>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: '#91A3B8', letterSpacing: '1px', textTransform: 'uppercase' as const, marginBottom: '8px' }}>Email Address</label>
                  <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com"
                    style={{ width: '100%', padding: '14px 16px', borderRadius: '14px', border: '1px solid rgba(255,255,255,0.08)', background: 'rgba(13,21,39,0.6)', color: '#fff', fontSize: '14px', outline: 'none', transition: 'border-color 0.2s', boxSizing: 'border-box' }}
                    onFocus={(e) => e.currentTarget.style.borderColor = 'rgba(239,159,39,0.4)'}
                    onBlur={(e) => e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)'}
                  />
                </div>

                <div style={{ marginBottom: '18px' }}>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: '#91A3B8', letterSpacing: '1px', textTransform: 'uppercase' as const, marginBottom: '8px' }}>Password</label>
                  <div style={{ position: 'relative' }}>
                    <input type={showPassword ? 'text' : 'password'} required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••"
                      style={{ width: '100%', padding: '14px 48px 14px 16px', borderRadius: '14px', border: '1px solid rgba(255,255,255,0.08)', background: 'rgba(13,21,39,0.6)', color: '#fff', fontSize: '14px', outline: 'none', transition: 'border-color 0.2s', boxSizing: 'border-box' }}
                      onFocus={(e) => e.currentTarget.style.borderColor = 'rgba(239,159,39,0.4)'}
                      onBlur={(e) => e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)'}
                    />
                    <button type="button" onClick={() => setShowPassword(!showPassword)}
                      style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', color: '#627D98', cursor: 'pointer', padding: '4px' }}>
                      {showPassword ? <EyeOff style={{ width: '18px', height: '18px' }} /> : <Eye style={{ width: '18px', height: '18px' }} />}
                    </button>
                  </div>
                </div>

                {isSignUp && (
                  <div style={{ marginBottom: '24px' }}>
                    <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: '#91A3B8', letterSpacing: '1px', textTransform: 'uppercase' as const, marginBottom: '8px' }}>Referral Code <span style={{ color: '#627D98', fontWeight: 500, textTransform: 'none' as const }}>(optional)</span></label>
                    <input type="text" value={referralCode} onChange={(e) => setReferralCode(e.target.value)} placeholder="Enter referral code"
                      style={{ width: '100%', padding: '14px 16px', borderRadius: '14px', border: '1px solid rgba(255,255,255,0.08)', background: 'rgba(13,21,39,0.6)', color: '#fff', fontSize: '14px', outline: 'none', transition: 'border-color 0.2s', boxSizing: 'border-box' }}
                      onFocus={(e) => e.currentTarget.style.borderColor = 'rgba(239,159,39,0.4)'}
                      onBlur={(e) => e.currentTarget.style.borderColor = 'rgba(255,255,255,0.08)'}
                    />
                  </div>
                )}

                <button type="submit" disabled={formLoading}
                  style={{
                    width: '100%', padding: '15px', borderRadius: '14px', border: 'none',
                    background: 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)',
                    color: '#fff', fontSize: '15px', fontWeight: 700, cursor: 'pointer',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
                    boxShadow: '0 4px 20px rgba(239,159,39,0.3)',
                    transition: 'all 0.2s', opacity: formLoading ? 0.6 : 1,
                    marginTop: isSignUp ? '0' : '8px',
                  }}
                  onMouseEnter={(e) => { if (!formLoading) e.currentTarget.style.transform = 'translateY(-1px)'; }}
                  onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}
                >
                  {formLoading && <Loader2 style={{ width: '18px', height: '18px', animation: 'spin 1s linear infinite' }} />}
                  <span>{isSignUp ? 'Create Account' : 'Sign In'}</span>
                  {!formLoading && <ArrowRight style={{ width: '18px', height: '18px' }} />}
                </button>
              </form>

              <div style={{ marginTop: '24px', textAlign: 'center' }}>
                <button onClick={() => { setIsSignUp(!isSignUp); setFormError(''); setFormSuccess(''); }}
                  style={{ background: 'none', border: 'none', color: '#EF9F27', fontSize: '13px', fontWeight: 600, cursor: 'pointer', textDecoration: 'none', transition: 'color 0.2s' }}
                  onMouseEnter={(e) => e.currentTarget.style.color = '#FAC775'}
                  onMouseLeave={(e) => e.currentTarget.style.color = '#EF9F27'}
                >
                  {isSignUp ? '← Already have an account? Sign In' : "Don't have an account? Sign Up →"}
                </button>
              </div>
            </div>

            {/* Trust badges */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '24px', marginTop: '32px', flexWrap: 'wrap', justifyContent: 'center' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: '#627D98', fontWeight: 600 }}>
                <Shield style={{ width: '14px', height: '14px', color: '#0F9D58' }} /> Encrypted & Secure
              </span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: '#627D98', fontWeight: 600 }}>
                <Sparkles style={{ width: '14px', height: '14px', color: '#EF9F27' }} /> Powered by Supabase
              </span>
            </div>
          </div>

        ) : paymentSuccess ? (
          /* ────── SUCCESS ────── */
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: '60px' }}>
            <div style={{ ...glassCard, width: '100%', maxWidth: '480px', padding: '48px 32px', textAlign: 'center' }}>
              {/* Success animation ring */}
              <div style={{
                width: '88px', height: '88px', borderRadius: '50%', margin: '0 auto 28px',
                background: 'linear-gradient(135deg, rgba(15,157,88,0.15) 0%, rgba(15,157,88,0.05) 100%)',
                border: '2px solid rgba(15,157,88,0.3)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                animation: 'pulse 2s ease-in-out infinite',
              }}>
                <CheckCircle2 style={{ width: '44px', height: '44px', color: '#0F9D58' }} />
              </div>

              <h2 style={{ fontSize: '26px', fontWeight: 800, color: '#fff', marginBottom: '8px' }}>Top-up Successful! 🎉</h2>
              <p style={{ fontSize: '14px', color: '#627D98', marginBottom: '32px', lineHeight: 1.6 }}>
                ₹{creditedAmount.toLocaleString()} virtual demo cash has been instantly credited to your wallet.
              </p>

              <div style={{
                background: 'rgba(13,21,39,0.6)', borderRadius: '16px',
                border: '1px solid rgba(239,159,39,0.15)',
                padding: '24px', marginBottom: '28px',
              }}>
                <span style={{ fontSize: '11px', fontWeight: 700, color: '#627D98', textTransform: 'uppercase' as const, letterSpacing: '1.5px' }}>Updated Wallet Balance</span>
                <div style={{ fontSize: '36px', fontWeight: 900, color: '#EF9F27', marginTop: '8px', letterSpacing: '-1px' }}>
                  ₹{profile?.wallet_balance?.toLocaleString()}
                </div>
              </div>

              <button onClick={() => setPaymentSuccess(false)}
                style={{
                  width: '100%', padding: '15px', borderRadius: '14px', border: 'none',
                  background: 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)',
                  color: '#fff', fontSize: '15px', fontWeight: 700, cursor: 'pointer',
                  boxShadow: '0 4px 20px rgba(239,159,39,0.3)', transition: 'all 0.2s',
                }}
              >
                Back to Dashboard
              </button>
            </div>
          </div>

        ) : (
          /* ────── BILLING DASHBOARD ────── */
          <div style={{ animation: 'fadeIn 0.5s ease-out' }}>

            {/* User profile + wallet header */}
            <div style={{ ...glassCard, padding: '28px 32px', marginBottom: '36px', display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: '20px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <div style={{
                  width: '52px', height: '52px', borderRadius: '16px',
                  background: 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: '20px', fontWeight: 800, color: '#fff',
                  boxShadow: '0 4px 16px rgba(239,159,39,0.25)',
                }}>
                  {(profile?.name || 'U').charAt(0).toUpperCase()}
                </div>
                <div>
                  <span style={{ fontSize: '11px', fontWeight: 700, color: '#627D98', textTransform: 'uppercase' as const, letterSpacing: '1.5px' }}>Logged in as</span>
                  <h3 style={{ fontSize: '18px', fontWeight: 800, color: '#fff', marginTop: '2px' }}>{profile?.name || 'Trader'}</h3>
                  <p style={{ fontSize: '12px', color: '#627D98', marginTop: '2px' }}>{profile?.email}</p>
                </div>
              </div>

              <div style={{
                background: 'rgba(13,21,39,0.5)', borderRadius: '16px',
                border: '1px solid rgba(239,159,39,0.12)', padding: '18px 28px',
                textAlign: 'right', minWidth: '200px',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px', justifyContent: 'flex-end', marginBottom: '4px' }}>
                  <Wallet style={{ width: '14px', height: '14px', color: '#EF9F27' }} />
                  <span style={{ fontSize: '11px', fontWeight: 700, color: '#627D98', textTransform: 'uppercase' as const, letterSpacing: '1.5px' }}>Demo Wallet</span>
                </div>
                <span style={{ fontSize: '28px', fontWeight: 900, color: '#fff', letterSpacing: '-1px' }}>
                  ₹{profile?.wallet_balance?.toLocaleString()}
                </span>
              </div>
            </div>

            {/* Section title */}
            <div style={{ marginBottom: '24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
                <div style={{ width: '32px', height: '32px', borderRadius: '10px', background: 'rgba(239,159,39,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Sparkles style={{ width: '18px', height: '18px', color: '#EF9F27' }} />
                </div>
                <h2 style={{ fontSize: '20px', fontWeight: 800, color: '#fff' }}>Choose a Top-up Plan</h2>
              </div>
              <p style={{ fontSize: '13px', color: '#627D98', marginLeft: '42px' }}>
                Unlock additional virtual capital. Payments processed securely via Razorpay.
              </p>
            </div>

            {/* ─── Plan Cards Grid ─── */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '20px', marginBottom: '40px' }}>
              {plans.map((plan) => {
                const isHovered = hoveredPlan === plan.id;
                const isPurchasing = purchasingPlan === plan.id;
                return (
                  <div
                    key={plan.id}
                    onMouseEnter={() => setHoveredPlan(plan.id)}
                    onMouseLeave={() => setHoveredPlan(null)}
                    style={{
                      ...glassCard,
                      padding: '0',
                      position: 'relative',
                      overflow: 'hidden',
                      transform: isHovered ? 'translateY(-4px)' : 'translateY(0)',
                      transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
                      borderColor: plan.popular ? 'rgba(239,159,39,0.25)' : (isHovered ? 'rgba(255,255,255,0.12)' : 'rgba(239,159,39,0.08)'),
                      boxShadow: isHovered
                        ? `0 20px 60px rgba(0,0,0,0.4), 0 0 0 1px rgba(239,159,39,0.1)`
                        : '0 8px 32px rgba(0,0,0,0.35)',
                    }}
                  >
                    {/* Top gradient accent bar */}
                    <div style={{ height: '4px', background: `linear-gradient(90deg, ${plan.color}, transparent)` }} />

                    {plan.popular && (
                      <div style={{
                        position: 'absolute', top: '16px', right: '16px',
                        background: 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)',
                        color: '#fff', fontSize: '10px', fontWeight: 800,
                        padding: '5px 12px', borderRadius: '20px',
                        letterSpacing: '1px', textTransform: 'uppercase' as const,
                        boxShadow: '0 4px 12px rgba(239,159,39,0.3)',
                      }}>
                        ★ BEST VALUE
                      </div>
                    )}

                    <div style={{ padding: '28px 24px' }}>
                      {/* Icon + name */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '16px' }}>
                        <div style={{
                          width: '44px', height: '44px', borderRadius: '14px',
                          background: `linear-gradient(135deg, ${plan.color}20, ${plan.color}08)`,
                          border: `1px solid ${plan.color}30`,
                          display: 'flex', alignItems: 'center', justifyContent: 'center',
                          color: plan.color,
                        }}>
                          {plan.icon}
                        </div>
                        <div>
                          <h3 style={{ fontSize: '18px', fontWeight: 800, color: '#fff' }}>{plan.name}</h3>
                        </div>
                      </div>

                      {/* Cash amount */}
                      <div style={{ marginBottom: '12px' }}>
                        <span style={{ fontSize: '36px', fontWeight: 900, color: plan.popular ? '#EF9F27' : '#fff', letterSpacing: '-1.5px' }}>
                          {formatCash(plan.cash)}
                        </span>
                        <span style={{ fontSize: '13px', color: '#627D98', marginLeft: '8px', fontWeight: 500 }}>demo cash</span>
                      </div>

                      <p style={{ fontSize: '13px', color: '#91A3B8', lineHeight: 1.7, marginBottom: '24px', minHeight: '44px' }}>
                        {plan.description}
                      </p>

                      {/* Divider */}
                      <div style={{ height: '1px', background: 'rgba(255,255,255,0.06)', marginBottom: '20px' }} />

                      {/* Price + CTA */}
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <div>
                          <span style={{ fontSize: '10px', fontWeight: 700, color: '#627D98', textTransform: 'uppercase' as const, letterSpacing: '1.5px', display: 'block' }}>One-time</span>
                          <span style={{ fontSize: '24px', fontWeight: 900, color: '#fff' }}>₹{plan.price}</span>
                        </div>
                        <button
                          onClick={() => handleTopup(plan)}
                          disabled={purchasingPlan !== null}
                          style={{
                            padding: '12px 28px', borderRadius: '14px', border: 'none',
                            background: plan.popular
                              ? 'linear-gradient(135deg, #EF9F27 0%, #BA7517 100%)'
                              : 'rgba(255,255,255,0.08)',
                            color: '#fff', fontSize: '14px', fontWeight: 700, cursor: 'pointer',
                            display: 'flex', alignItems: 'center', gap: '8px',
                            boxShadow: plan.popular ? '0 4px 16px rgba(239,159,39,0.25)' : 'none',
                            transition: 'all 0.2s',
                            opacity: purchasingPlan !== null && !isPurchasing ? 0.5 : 1,
                          }}
                          onMouseEnter={(e) => {
                            if (!plan.popular) e.currentTarget.style.background = 'rgba(255,255,255,0.14)';
                          }}
                          onMouseLeave={(e) => {
                            if (!plan.popular) e.currentTarget.style.background = 'rgba(255,255,255,0.08)';
                          }}
                        >
                          {isPurchasing
                            ? <Loader2 style={{ width: '18px', height: '18px', animation: 'spin 1s linear infinite' }} />
                            : <><span>Top Up</span><ArrowRight style={{ width: '16px', height: '16px' }} /></>
                          }
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Trust footer */}
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '28px',
              padding: '20px 0', borderTop: '1px solid rgba(255,255,255,0.04)',
              flexWrap: 'wrap',
            }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: '#627D98', fontWeight: 600 }}>
                <Shield style={{ width: '16px', height: '16px', color: '#0F9D58' }} />
                256-bit SSL Encryption
              </span>
              <span style={{ color: '#2D4676' }}>•</span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: '#627D98', fontWeight: 600 }}>
                <img src="/app-icon.png" alt="" style={{ width: '16px', height: '16px', borderRadius: '4px' }} />
                Powered by Razorpay
              </span>
              <span style={{ color: '#2D4676' }}>•</span>
              <span style={{ fontSize: '12px', color: '#627D98', fontWeight: 600 }}>
                Instant Credit to Wallet
              </span>
            </div>
          </div>
        )}
      </main>

      {/* Global keyframe animations */}
      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes pulse { 0%, 100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.05); opacity: 0.85; } }
        ::placeholder { color: #4a5568 !important; }
        input::placeholder { color: #4a5568 !important; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        @media (max-width: 768px) {
          main > div > div:first-child { flex-direction: column !important; }
        }
      `}</style>
    </div>
  );
};
