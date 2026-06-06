// Vercel Serverless Function — Verify Razorpay Payment & Credit Wallet
// Uses Supabase service role key to bypass RLS and directly credit the wallet.

import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';

const PLANS = {
  titan_1l:  { price: 199,  cash: 100000,  name: 'Starter Boost' },
  titan_5l:  { price: 599,  cash: 500000,  name: 'Titan Plus' },
  titan_pro: { price: 999,  cash: 1000000, name: 'Pro Launch' },
};

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const {
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
    plan_id,
    user_id,
  } = req.body;

  // ─── 1. Validate inputs ───
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return res.status(400).json({ error: 'Missing payment verification fields' });
  }
  const plan = PLANS[plan_id];
  if (!plan) return res.status(400).json({ error: 'Invalid plan' });
  if (!user_id) return res.status(400).json({ error: 'Missing user_id' });

  const keyId = process.env.RAZORPAY_KEY_ID?.trim();
  const keySecret = process.env.RAZORPAY_KEY_SECRET?.trim();
  const supabaseUrl = (process.env.SUPABASE_URL || 'https://bftvimnhpoiuoyryyiff.supabase.co').trim();
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

  if (!keySecret) return res.status(500).json({ error: 'Payment gateway not configured' });
  if (!supabaseServiceKey) return res.status(500).json({ error: 'Database not configured' });

  try {
    // ─── 2. Verify Razorpay Signature (HMAC SHA256) ───
    const expectedSignature = crypto
      .createHmac('sha256', keySecret)
      .update(razorpay_order_id + '|' + razorpay_payment_id)
      .digest('hex');

    if (expectedSignature !== razorpay_signature) {
      console.error('Signature mismatch');
      return res.status(400).json({ error: 'Payment verification failed — invalid signature' });
    }

    // ─── 3. Confirm payment with Razorpay API ───
    const paymentRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: {
        'Authorization': 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64'),
      },
    });

    if (!paymentRes.ok) return res.status(500).json({ error: 'Could not verify payment with Razorpay' });
    const payment = await paymentRes.json();

    if (payment.status !== 'captured' && payment.status !== 'authorized') {
      return res.status(400).json({ error: `Payment not captured (status: ${payment.status})` });
    }
    if (payment.amount !== plan.price * 100) {
      return res.status(400).json({ error: 'Payment amount mismatch' });
    }

    // ─── 4. Credit wallet using Supabase service role (bypasses RLS) ───
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Check for duplicate payment (idempotency)
    const { data: existingNotif } = await supabase
      .from('notifications')
      .select('id')
      .eq('user_id', user_id)
      .like('body', `%${razorpay_payment_id}%`)
      .maybeSingle();

    if (existingNotif) {
      // Already processed this payment — return success without double-crediting
      const { data: currentProfile } = await supabase
        .from('profiles')
        .select('wallet_balance')
        .eq('id', user_id)
        .single();
      return res.status(200).json({
        success: true,
        credited: plan.cash,
        new_balance: currentProfile?.wallet_balance || 0,
        payment_id: razorpay_payment_id,
        note: 'Already processed',
      });
    }

    // Fetch current balance
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('wallet_balance, referred_by')
      .eq('id', user_id)
      .single();

    if (profileError || !profile) {
      console.error('Profile fetch error:', profileError);
      return res.status(500).json({ error: 'User profile not found' });
    }

    const newBalance = (profile.wallet_balance || 0) + plan.cash;

    // Update wallet
    const { error: updateError } = await supabase
      .from('profiles')
      .update({ wallet_balance: newBalance, subscription_active: true, plan: plan_id })
      .eq('id', user_id);

    if (updateError) {
      console.error('Wallet update error:', updateError);
      return res.status(500).json({ error: 'Payment verified but wallet credit failed. Contact support. ID: ' + razorpay_payment_id });
    }

    // ─── 5. Referral commission (20%) ───
    if (profile.referred_by) {
      await supabase.from('referral_commissions').insert({
        referrer_id: profile.referred_by, referred_id: user_id,
        package_name: plan.name, package_price: plan.price,
        commission_amount: 0.2 * plan.price, status: 'unclaimed',
      }).catch(e => console.error('Referral error:', e));
    }

    // ─── 6. Transaction log (also serves as idempotency check) ───
    await supabase.from('notifications').insert({
      user_id, title: 'Wallet Topped Up! 💰',
      body: `Purchased ${plan.name}. ₹${plan.cash.toLocaleString()} demo cash credited. Razorpay ID: ${razorpay_payment_id}`,
      is_read: false, action_type: 'custom',
    }).catch(e => console.error('Notification error:', e));

    return res.status(200).json({
      success: true,
      credited: plan.cash,
      new_balance: newBalance,
      payment_id: razorpay_payment_id,
    });

  } catch (err) {
    console.error('Verification error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
