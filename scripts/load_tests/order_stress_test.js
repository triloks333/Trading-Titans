// k6 STRESS test for concurrent order placement / settlement races.
//
// Goal: hammer the order path with many virtual users firing at once to surface
// race conditions (double-fills, runaway lots, balance going negative) that the
// deterministic Dart unit tests can't reproduce. This is a destructive-ish test
// against whatever project you point it at — RUN IT AGAINST A DEV/STAGING
// PROJECT OR A BRANCH DATABASE, never production.
//
// Run:
//   k6 run -e SUPABASE_URL=https://<ref>.supabase.co \
//          -e USER_JWT=<a-test-user-access-token> \
//          scripts/load_tests/order_stress_test.js
//
// USER_JWT must be a real signed-in test user's access token (the order RPC is
// auth-gated). Generate one by signing in a throwaway account and copying the
// session access_token.

import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const failedOrders = new Rate('failed_orders');

export const options = {
  scenarios: {
    // Burst: 50 users all submitting at the same instant, repeated.
    concurrent_burst: {
      executor: 'constant-vus',
      vus: 50,
      duration: '1m',
    },
  },
  thresholds: {
    // Under contention we still expect the backend to stay consistent.
    // A high failure rate here is a RED FLAG worth investigating, not a pass.
    failed_orders: ['rate<0.05'],
  },
};

const SUPABASE_URL = __ENV.SUPABASE_URL;
const USER_JWT = __ENV.USER_JWT;

export default function () {
  if (!SUPABASE_URL || !USER_JWT) {
    throw new Error('Set SUPABASE_URL and USER_JWT env vars (see file header).');
  }

  // NOTE: adjust the RPC name + payload to match your actual order function.
  // This targets a hypothetical `place_order` RPC; rename if yours differs.
  const res = http.post(
    `${SUPABASE_URL}/rest/v1/rpc/place_order`,
    JSON.stringify({
      p_symbol: 'NIFTY',
      p_side: 'BUY',
      p_qty: 1,
      p_order_type: 'MARKET',
    }),
    {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${USER_JWT}`,
        apikey: USER_JWT,
      },
    },
  );

  const ok = check(res, {
    'no server error (5xx)': (r) => r.status < 500,
  });
  failedOrders.add(!ok);
}
