// k6 load test for the market-quote edge function.
//
// Why this exists: the in-repo Dart suite can verify pure logic and widgets,
// but it CANNOT exercise the live HTTP endpoints under concurrency. This script
// does, using k6 (https://k6.io). It is intentionally NOT part of `flutter test`.
//
// Run (no secrets committed — pass them as env vars):
//   k6 run -e SUPABASE_URL=https://<ref>.supabase.co \
//          -e ANON_KEY=<publishable-or-anon-key> \
//          load_tests/quote_load_test.js
//
// Tune load with --vus (concurrent users) and --duration, or edit `options`.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('failed_requests');
const quoteLatency = new Trend('quote_latency_ms');

export const options = {
  // Ramp: warm up, hold steady load, then push a short spike.
  stages: [
    { duration: '30s', target: 20 },  // ramp to 20 concurrent users
    { duration: '1m', target: 20 },   // steady state
    { duration: '30s', target: 100 }, // spike
    { duration: '30s', target: 0 },   // ramp down
  ],
  thresholds: {
    // 95% of quote reads must return under 800ms; <1% may fail.
    quote_latency_ms: ['p(95)<800'],
    failed_requests: ['rate<0.01'],
  },
};

const SUPABASE_URL = __ENV.SUPABASE_URL;
const ANON_KEY = __ENV.ANON_KEY;

// A spread of representative symbols across markets.
const SYMBOLS = [
  { market: 'equity', symbol: 'RELIANCE' },
  { market: 'equity', symbol: 'TCS' },
  { market: 'equity', symbol: 'INFY' },
  { market: 'index', symbol: 'NIFTY' },
  { market: 'index', symbol: 'BANKNIFTY' },
];

export default function () {
  if (!SUPABASE_URL || !ANON_KEY) {
    throw new Error('Set SUPABASE_URL and ANON_KEY env vars (see file header).');
  }

  const pick = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
  const res = http.post(
    `${SUPABASE_URL}/functions/v1/market-quote`,
    JSON.stringify({ market: pick.market, symbol: pick.symbol }),
    {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ANON_KEY}`,
        apikey: ANON_KEY,
      },
    },
  );

  quoteLatency.add(res.timings.duration);
  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
    'has a price field': (r) => {
      try {
        const body = r.json();
        return body && (body.ltp !== undefined || body.price !== undefined);
      } catch (_) {
        return false;
      }
    },
  });
  errorRate.add(!ok);

  sleep(1); // pace each virtual user ~1 req/s
}
