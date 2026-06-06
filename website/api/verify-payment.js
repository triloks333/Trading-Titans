// Vercel Serverless Function — Verify Razorpay Payment & Credit Wallet
// This runs server-side only. Verifies the cryptographic signature before crediting.

import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';

const PLANS = {
  titan_1l:  { price: 199,  cash: 100000,  name: 'Starter Boost' },
  titan_5l:  { price: 599,  cash: 500000,  name: 'Titan Plus' },
  titan_pro: { price: 999,  cash: 1000000, name: 'Pro Launch' },
};

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const {
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
    plan_id,
    user_id,
    access_token,  // Supabase JWT from the client session
  } = req.body;

  // ─── 1. Validate inputs ───
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return res.status(400).json({ error: 'Missing payment verification fields' });
  }
  const plan = PLANS[plan_id];
  if (!plan) {
    return res.status(400).json({ error: 'Invalid plan' });
  }
  if (!user_id || !access_token) {
    return res.status(400).json({ error: 'Missing user authentication' });
  }

  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  const supabaseUrl = process.env.SUPABASE_URL || 'https://bftvimnhpoiuoyryyiff.supabase.co';
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak';

  if (!keySecret) {
    return res.status(500).json({ error: 'Payment gateway not configured' });
  }

  try {
    // ─── 2. Verify Razorpay Signature (HMAC SHA256) ───
    const body = razorpay_order_id + '|' + razorpay_payment_id;
    const expectedSignature = crypto
      .createHmac('sha256', keySecret)
      .update(body)
      .digest('hex');

    if (expectedSignature !== razorpay_signature) {
      console.error('Signature mismatch:', { expected: expectedSignature, received: razorpay_signature });
      return res.status(400).json({ error: 'Payment verification failed — invalid signature' });
    }

    // ─── 3. Double-check payment status with Razorpay API ───
    const paymentRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: {
        'Authorization': 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64'),
      },
    });

    if (!paymentRes.ok) {
      return res.status(500).json({ error: 'Could not verify payment with Razorpay' });
    }

    const payment = await paymentRes.json();

    // Razorpay auto-captures on checkout — check for captured or authorized
    if (payment.status !== 'captured' && payment.status !== 'authorized') {
      return res.status(400).json({ error: `Payment status is "${payment.status}", not captured` });
    }

    const expectedAmount = plan.price * 100; // paise
    if (payment.amount !== expectedAmount) {
      return res.status(400).json({ error: 'Payment amount mismatch' });
    }

    // ─── 4. Credit User Wallet via Supabase (authenticated as the user) ───
    // Use the user's own JWT so RLS policy "Users can update their own profile" works
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${access_token}`,
        },
      },
    });

    // Fetch current profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('wallet_balance, referred_by, email, name')
      .eq('id', user_id)
      .single();

    if (profileError || !profile) {
      console.error('Profile fetch error:', profileError);
      return res.status(500).json({ error: 'Could not fetch user profile' });
    }

    const newBalance = (profile.wallet_balance || 0) + plan.cash;

    // Update wallet
    const { error: updateError } = await supabase
      .from('profiles')
      .update({
        wallet_balance: newBalance,
        subscription_active: true,
        plan: plan_id,
      })
      .eq('id', user_id);

    if (updateError) {
      console.error('Wallet update error:', updateError);
      return res.status(500).json({ error: 'Payment verified but wallet credit failed. Contact support with payment ID: ' + razorpay_payment_id });
    }

    // ─── 5. Handle Referral Commission (20% share) ───
    if (profile.referred_by) {
      const commissionAmount = 0.2 * plan.price;
      await supabase.from('referral_commissions').insert({
        referrer_id: profile.referred_by,
        referred_id: user_id,
        package_name: plan.name,
        package_price: plan.price,
        commission_amount: commissionAmount,
        status: 'unclaimed',
      }).catch(err => console.error('Referral commission error:', err));
    }

    // ─── 6. Log Transaction as Notification ───
    await supabase.from('notifications').insert({
      user_id: user_id,
      title: 'Wallet Topped Up! 💰',
      body: `Purchased ${plan.name}. ₹${plan.cash.toLocaleString()} demo cash credited. Razorpay ID: ${razorpay_payment_id}`,
      is_read: false,
      action_type: 'custom',
    }).catch(err => console.error('Notification insert error:', err));

    // ─── 7. Return success ───
    return res.status(200).json({
      success: true,
      credited: plan.cash,
      new_balance: newBalance,
      payment_id: razorpay_payment_id,
    });

  } catch (err) {
    console.error('Payment verification error:', err);
    return res.status(500).json({ error: 'Internal server error during payment verification' });
  }
}
