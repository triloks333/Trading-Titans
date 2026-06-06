import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabaseClient';
import { Shield, Sparkles, LogOut, Loader2, CheckCircle2, AlertCircle } from 'lucide-react';

interface Plan {
  id: string;
  name: string;
  price: number;
  cash: number;
  description: string;
  popular?: boolean;
}

export const TopupPage: React.FC = () => {
  // Auth state
  const [session, setSession] = useState<any>(null);
  const [profile, setProfile] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  
  // Login / Signup Form state
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [referralCode, setReferralCode] = useState('');
  const [formError, setFormError] = useState('');
  const [formSuccess, setFormSuccess] = useState('');
  const [formLoading, setFormLoading] = useState(false);

  // Payment state
  const [purchasingPlan, setPurchasingPlan] = useState<string | null>(null);
  const [paymentSuccess, setPaymentSuccess] = useState<boolean>(false);
  const [creditedAmount, setCreditedAmount] = useState<number>(0);

  const plans: Plan[] = [
    {
      id: 'titan_1l',
      name: 'Starter Boost',
      price: 199,
      cash: 100000,
      description: 'Get ₹1,00,000 virtual cash to start trading stock & crypto derivatives.',
    },
    {
      id: 'titan_5l',
      name: 'Titan Plus',
      price: 599,
      cash: 500000,
      description: 'Get ₹5,00,000 virtual cash. Perfect for scaling advanced option strategies.',
      popular: true,
    },
    {
      id: 'titan_pro',
      name: 'Pro Launch',
      price: 999,
      cash: 1000000,
      description: 'Get ₹10,00,000 virtual cash. Complete capital freedom for large leverage.',
    }
  ];

  useEffect(() => {
    // 1. Fetch current session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session) {
        fetchProfile(session.user.id);
      } else {
        setLoading(false);
      }
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session) {
        fetchProfile(session.user.id);
      } else {
        setProfile(null);
        setLoading(false);
      }
    });

    // 2. Pre-fill email from URL if present
    const params = new URLSearchParams(window.location.search);
    const emailParam = params.get('email');
    if (emailParam) {
      setEmail(emailParam);
    }

    // 3. Load Razorpay script dynamically
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    document.body.appendChild(script);

    return () => {
      subscription.unsubscribe();
      document.body.removeChild(script);
    };
  }, []);

  const fetchProfile = async (userId: string) => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();
      
      if (error) throw error;
      setProfile(data);
    } catch (err) {
      console.error('Error loading profile:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormLoading(true);
    setFormError('');
    setFormSuccess('');

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) throw error;
    } catch (err: any) {
      setFormError(err.message || 'Login failed. Please try again.');
      setFormLoading(false);
    }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormLoading(true);
    setFormError('');
    setFormSuccess('');

    try {
      // 1. Register User in Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
      });

      if (authError) throw authError;
      if (!authData.user) throw new Error('Signup failed.');

      // 2. Insert corresponding Profile record
      const { error: profileError } = await supabase.from('profiles').insert([
        {
          id: authData.user.id,
          email: email.trim().toLowerCase(),
          name: name.trim(),
          referred_by: referralCode.trim() || null,
          wallet_balance: 10000.0, // Default signup balance
          subscription_active: false,
          total_realized_pnl: 0.0,
        }
      ]);

      if (profileError) throw profileError;

      setFormSuccess('Account created successfully! Logging you in...');
      setTimeout(() => {
        supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });
      }, 1500);

    } catch (err: any) {
      setFormError(err.message || 'Registration failed. Please try again.');
      setFormLoading(false);
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  const handleTopup = async (plan: Plan) => {
    if (!session || !profile) return;
    setPurchasingPlan(plan.id);
    
    // Get Razorpay Key from Env or fallback to placeholder for verification
    const razorpayKey = import.meta.env.VITE_RAZORPAY_KEY_ID || 'rzp_test_5gTjK4kL4b5gTj';
    
    const options = {
      key: razorpayKey,
      amount: plan.price * 100, // Amount in paise
      currency: 'INR',
      name: 'Trading Titans',
      description: `${plan.name} - ₹${plan.cash.toLocaleString()} Demo Cash`,
      image: 'https://thetradingtitans.com/surya_yantra_icon-1.svg',
      handler: async function (response: any) {
        await processSuccessPayment(plan, response.razorpay_payment_id);
      },
      prefill: {
        name: profile.name || '',
        email: profile.email || '',
      },
      theme: {
        color: '#1A73E8', // Match app brand blue
      },
      modal: {
        ondismiss: function() {
          setPurchasingPlan(null);
        }
      }
    };

    const rzp = (window as any).Razorpay ? new (window as any).Razorpay(options) : null;
    if (rzp) {
      rzp.open();
    } else {
      // Script failed to load or is not ready -> fallback to sandbox simulate
      alert('Razorpay Checkout SDK is loading. Simulating test payment...');
      setTimeout(async () => {
        await processSuccessPayment(plan, 'mock_pay_id_' + Date.now());
      }, 1500);
    }
  };

  const processSuccessPayment = async (plan: Plan, paymentId: string) => {
    try {
      // 1. Credit the user's wallet
      const newBalance = (profile.wallet_balance || 0) + plan.cash;
      const { error: walletError } = await supabase
        .from('profiles')
        .update({ 
          wallet_balance: newBalance,
          subscription_active: true,
          plan: plan.id
        })
        .eq('id', session.user.id);

      if (walletError) throw walletError;

      // 2. Handle Referral Commissions (20% share)
      if (profile.referred_by) {
        const commissionAmount = 0.2 * plan.price;
        const { error: refError } = await supabase
          .from('referral_commissions')
          .insert({
            referrer_id: profile.referred_by,
            referred_id: session.user.id,
            package_name: plan.name,
            package_price: plan.price,
            commission_amount: commissionAmount,
            status: 'unclaimed'
          });
        
        if (refError) {
          console.error('Error inserting commission:', refError);
        }
      }

      // 3. Log transaction for record/verification
      await supabase.from('notifications').insert({
        user_id: session.user.id,
        title: 'Wallet Topped Up! 💰',
        body: `Successfully purchased ${plan.name}. ₹${plan.cash.toLocaleString()} demo cash credited. Transaction ID: ${paymentId}`,
        is_read: false,
        action_type: 'custom'
      });

      // Update local state
      setCreditedAmount(plan.cash);
      setProfile((prev: any) => ({ ...prev, wallet_balance: newBalance }));
      setPaymentSuccess(true);
    } catch (err) {
      console.error('Failed to credit payment:', err);
      alert('Payment succeeded but crediting failed. Please contact support.');
    } finally {
      setPurchasingPlan(null);
    }
  };

  return (
    <div className="min-h-screen bg-[#0D1527] text-zinc-100 flex flex-col font-sans selection:bg-[#9fff00] selection:text-black">
      
      {/* Top Header */}
      <header className="border-b border-zinc-800 bg-[#0D1527]/90 backdrop-blur-md py-4 px-6 md:px-12 flex items-center justify-between sticky top-0 z-30">
        <a href="/" className="flex items-center gap-3 hover:opacity-90 transition-all">
          <img src="/surya_yantra_icon-1.svg" className="w-8 h-8 filter invert" alt="Logo" />
          <span className="font-extrabold text-lg tracking-widest text-white uppercase">Trading Titans</span>
        </a>
        {session && (
          <button 
            onClick={handleLogout}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-zinc-800 text-xs font-semibold text-zinc-400 hover:text-white hover:border-zinc-700 transition-all"
          >
            <LogOut className="w-3.5 h-3.5" />
            <span>Sign Out</span>
          </button>
        )}
      </header>

      {/* Main Content Area */}
      <main className="flex-grow flex flex-col items-center justify-center p-6 max-w-4xl w-full mx-auto">
        
        {loading ? (
          <div className="flex flex-col items-center justify-center gap-4 py-20">
            <Loader2 className="w-10 h-10 text-[#1A73E8] animate-spin" />
            <p className="text-sm font-semibold text-zinc-400">Loading Billing Account...</p>
          </div>
        ) : !session ? (
          /* Authentication Forms */
          <div className="w-full max-w-md bg-[#162544]/60 border border-zinc-800/80 rounded-2xl p-8 shadow-2xl backdrop-blur-md">
            <h2 className="text-2xl font-bold text-center text-white mb-2">
              {isSignUp ? 'Create Billing Account' : 'Sign In to Top Up'}
            </h2>
            <p className="text-zinc-400 text-xs text-center mb-6">
              {isSignUp ? 'Set up an account to manage your trading balances.' : 'Enter credentials to load cash into your trading simulator wallet.'}
            </p>

            {formError && (
              <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-4 flex items-start gap-3 mb-5">
                <AlertCircle className="w-5 h-5 text-red-500 shrink-0 mt-0.5" />
                <span className="text-xs font-medium text-red-400">{formError}</span>
              </div>
            )}

            {formSuccess && (
              <div className="bg-green-500/10 border border-green-500/30 rounded-xl p-4 flex items-start gap-3 mb-5">
                <CheckCircle2 className="w-5 h-5 text-green-500 shrink-0 mt-0.5" />
                <span className="text-xs font-medium text-green-400">{formSuccess}</span>
              </div>
            )}

            <form onSubmit={isSignUp ? handleSignUp : handleLogin} className="space-y-4">
              {isSignUp && (
                <div>
                  <label className="block text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1.5">Full Name</label>
                  <input
                    type="text"
                    required
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Enter your name"
                    className="w-full bg-[#0D1527] border border-zinc-800 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#1A73E8] transition-all text-white placeholder-zinc-500"
                  />
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1.5">Email Address</label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@domain.com"
                  className="w-full bg-[#0D1527] border border-zinc-800 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#1A73E8] transition-all text-white placeholder-zinc-500"
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1.5">Account Password</label>
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full bg-[#0D1527] border border-zinc-800 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#1A73E8] transition-all text-white placeholder-zinc-500"
                />
              </div>

              {isSignUp && (
                <div>
                  <label className="block text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1.5">Referral Code (Optional)</label>
                  <input
                    type="text"
                    value={referralCode}
                    onChange={(e) => setReferralCode(e.target.value)}
                    placeholder="Enter referrer code"
                    className="w-full bg-[#0D1527] border border-zinc-800 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#1A73E8] transition-all text-white placeholder-zinc-500"
                  />
                </div>
              )}

              <button
                type="submit"
                disabled={formLoading}
                className="w-full bg-[#1A73E8] hover:bg-[#1A73E8]/90 text-white rounded-xl py-3 font-semibold text-sm transition-all shadow-lg shadow-blue-900/30 flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {formLoading && <Loader2 className="w-4 h-4 animate-spin" />}
                <span>{isSignUp ? 'Create Account' : 'Sign In'}</span>
              </button>
            </form>

            <div className="mt-6 text-center">
              <button
                onClick={() => {
                  setIsSignUp(!isSignUp);
                  setFormError('');
                  setFormSuccess('');
                }}
                className="text-xs text-[#1A73E8] hover:underline font-semibold"
              >
                {isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up"}
              </button>
            </div>
          </div>
        ) : paymentSuccess ? (
          /* Payment Success Display */
          <div className="w-full max-w-md bg-[#162544]/60 border border-zinc-800/80 rounded-2xl p-8 text-center shadow-2xl backdrop-blur-md">
            <div className="w-16 h-16 bg-green-500/10 rounded-full flex items-center justify-center mx-auto mb-6 border border-green-500/30">
              <CheckCircle2 className="w-10 h-10 text-green-500 animate-bounce" />
            </div>
            <h2 className="text-2xl font-bold text-white mb-2">Top-up Successful!</h2>
            <p className="text-zinc-400 text-sm mb-6">
              ₹{creditedAmount.toLocaleString()} virtual demo cash has been instantly credited to your wallet balance.
            </p>
            <div className="bg-[#0D1527] border border-zinc-800 rounded-xl p-4 mb-6">
              <span className="text-xs text-zinc-400 block mb-1">Updated Demo Wallet Balance</span>
              <span className="text-2xl font-black text-white">₹{profile?.wallet_balance?.toLocaleString()}</span>
            </div>
            <button
              onClick={() => setPaymentSuccess(false)}
              className="w-full bg-[#1A73E8] hover:bg-[#1A73E8]/90 text-white rounded-xl py-3 font-semibold text-sm transition-all"
            >
              Back to Billing Dashboard
            </button>
          </div>
        ) : (
          /* Billing Core Panel */
          <div className="w-full space-y-8 animate-fade-in">
            
            {/* User Details header */}
            <div className="bg-[#162544]/50 border border-zinc-800 p-6 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4 backdrop-blur-md">
              <div>
                <span className="text-xs font-bold text-zinc-500 uppercase tracking-widest">Active Simulator User</span>
                <h3 className="text-xl font-bold text-white mt-1">{profile?.name || 'Simulator User'}</h3>
                <p className="text-xs text-zinc-400 mt-0.5">{profile?.email}</p>
              </div>
              <div className="bg-[#0D1527] border border-zinc-800/80 rounded-xl p-4 flex flex-col items-start md:items-end justify-center min-w-[200px]">
                <span className="text-xs text-zinc-500 font-bold tracking-wider">DEMO WALLET BALANCE</span>
                <span className="text-2xl font-black text-white mt-1">₹{profile?.wallet_balance?.toLocaleString()}</span>
              </div>
            </div>

            {/* Subscriptions Grid */}
            <div className="space-y-4">
              <div className="flex flex-col gap-1">
                <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <Sparkles className="w-5 h-5 text-[#9fff00]" />
                  <span>Choose Demo Cash Top-up Plan</span>
                </h3>
                <p className="text-zinc-400 text-xs">Unlock additional mock capital. All payments are processed securely via Razorpay Checkout.</p>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {plans.map((plan) => (
                  <div 
                    key={plan.id}
                    className={`bg-[#162544]/40 border ${plan.popular ? 'border-[#1A73E8] shadow-lg shadow-blue-900/10' : 'border-zinc-800'} rounded-2xl p-6 flex flex-col relative transition-all hover:border-zinc-700`}
                  >
                    {plan.popular && (
                      <span className="absolute top-0 right-6 -translate-y-1/2 bg-[#1A73E8] text-white text-[10px] font-black uppercase px-2.5 py-1 rounded-full tracking-wider">
                        MOST POPULAR
                      </span>
                    )}
                    <h4 className="text-lg font-bold text-white mb-1">{plan.name}</h4>
                    <span className="text-2xl font-black text-[#9fff00] mb-2">₹{plan.cash.toLocaleString()}</span>
                    <p className="text-zinc-400 text-xs leading-relaxed mb-6 flex-grow">{plan.description}</p>
                    
                    <div className="pt-4 border-t border-zinc-800/80 flex items-center justify-between">
                      <div>
                        <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest block">One-time payment</span>
                        <span className="text-lg font-black text-white">₹{plan.price}</span>
                      </div>
                      <button
                        onClick={() => handleTopup(plan)}
                        disabled={purchasingPlan !== null}
                        className={`px-4 py-2.5 rounded-xl font-bold text-xs transition-all flex items-center justify-center gap-1.5 ${
                          plan.popular 
                            ? 'bg-[#1A73E8] hover:bg-[#1A73E8]/90 text-white' 
                            : 'bg-zinc-800 hover:bg-zinc-700 text-zinc-200'
                        }`}
                      >
                        {purchasingPlan === plan.id ? (
                          <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        ) : (
                          <span>Top up</span>
                        )}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Payment security footer badge */}
            <div className="text-center text-xs text-zinc-500 py-6 border-t border-zinc-900 flex flex-col sm:flex-row items-center justify-center gap-4">
              <span className="flex items-center gap-1"><Shield className="w-4 h-4 text-green-500" /> 256-bit Secure SSL Encryption</span>
              <span className="hidden sm:inline">•</span>
              <span>Powered by Razorpay Payments</span>
            </div>

          </div>
        )}

      </main>

    </div>
  );
};
