// Vercel Serverless Function — Create Razorpay Order
// This runs server-side only. The Razorpay secret key never reaches the browser.

const PLANS = {
  titan_1l:  { price: 199,  cash: 100000,  name: 'Starter Boost' },
  titan_5l:  { price: 599,  cash: 500000,  name: 'Titan Plus' },
  titan_pro: { price: 999,  cash: 1000000, name: 'Pro Launch' },
};

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { plan_id, user_id } = req.body;

  // Validate plan
  const plan = PLANS[plan_id];
  if (!plan) {
    return res.status(400).json({ error: 'Invalid plan selected' });
  }
  if (!user_id) {
    return res.status(400).json({ error: 'User not authenticated' });
  }

  const keyId = process.env.RAZORPAY_KEY_ID?.trim();
  const keySecret = process.env.RAZORPAY_KEY_SECRET?.trim();

  if (!keyId || !keySecret) {
    return res.status(500).json({ error: 'Payment gateway not configured' });
  }

  try {
    // Create Razorpay Order via REST API
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64'),
      },
      body: JSON.stringify({
        amount: plan.price * 100, // Razorpay expects paise
        currency: 'INR',
        receipt: `tt_${plan_id}_${user_id.slice(0, 8)}_${Date.now()}`,
        notes: {
          plan_id,
          plan_name: plan.name,
          user_id,
          cash_amount: plan.cash,
        },
      }),
    });

    if (!response.ok) {
      const errBody = await response.text();
      console.error('Razorpay order creation failed:', errBody);
      return res.status(500).json({ error: 'Failed to create payment order' });
    }

    const order = await response.json();

    return res.status(200).json({
      order_id: order.id,
      amount: order.amount,
      currency: order.currency,
      key_id: keyId, // Public key is safe to send to client
    });
  } catch (err) {
    console.error('Error creating order:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
