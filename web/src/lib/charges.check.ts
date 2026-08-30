import assert from 'node:assert/strict'
import { calculateCharges, type InstrumentType, type Side } from './charges.ts'

/*
 * Runnable check for the charges preview:  npm run check:charges
 *
 * The fixtures are not invented. Each one is a real executed order read out of
 * production, with the brokerage / stamp duty / tax / total that the server-side
 * engine itself wrote onto the row. So this asserts the thing that actually
 * matters — that the number the browser shows before you confirm is the number
 * the wallet is going to be debited — rather than merely that the arithmetic is
 * self-consistent.
 *
 * All six were priced against charge config `cb6c209d` (_revision
 * 2026-08-27-2026-rates), inlined below so the check needs no network and cannot
 * silently start passing against a different rate card.
 */

const CONFIG_2026: Record<string, number> = {
  gst_rate: 0.18,
  stt_delivery: 0.001,
  dp_charges_flat: 13.5,
  exchange_futures: 0.0000173,
  exchange_options: 0.0003503,
  stt_futures_sell: 0.0005,
  stt_options_sell: 0.0015,
  clearing_fee_rate: 0.000002,
  exchange_delivery: 0.0000297,
  fo_brokerage_flat: 20,
  stt_intraday_sell: 0.00025,
  turnover_tax_rate: 0.000001,
  stamp_duty_futures: 0.00002,
  stamp_duty_options: 0.00003,
  stamp_duty_delivery: 0.00015,
  stamp_duty_intraday: 0.00003,
  equity_brokerage_max: 20,
  equity_brokerage_rate: 0.0005,
  other_broker_fee_flat: 0,
  sebi_regulatory_fee_rate: 0.000001,
}

interface Fixture {
  order: string
  symbol: string
  instrumentType: InstrumentType
  side: Side
  quantity: number
  price: number
  brokerage: number
  stampDuty: number
  taxCharges: number
  totalCharges: number
}

const FIXTURES: Fixture[] = [
  {
    order: 'cf23cde5', symbol: 'CGCL', instrumentType: 'EQUITY', side: 'buy',
    quantity: 2000, price: 257.61,
    brokerage: 20, stampDuty: 77.28, taxCharges: 539.31, totalCharges: 636.59,
  },
  {
    order: '0ba41297', symbol: 'CGCL', instrumentType: 'EQUITY', side: 'buy',
    quantity: 3000, price: 260.4,
    brokerage: 20, stampDuty: 117.18, taxCharges: 815.87, totalCharges: 953.05,
  },
  {
    // Equity SELL: the only case that carries the ₹13.50 DP charge, and the
    // reason the engine's rule (DP on every equity sell) had to be mirrored
    // instead of the mobile preview's (DP only when not intraday).
    order: 'e8831cde', symbol: 'GOLDBEES', instrumentType: 'EQUITY', side: 'sell',
    quantity: 10000, price: 131,
    brokerage: 20, stampDuty: 0, taxCharges: 1365.69, totalCharges: 1399.19,
  },
  {
    order: '53c9f4f5', symbol: 'AEROENTER', instrumentType: 'EQUITY', side: 'sell',
    quantity: 500, price: 146.26,
    brokerage: 20, stampDuty: 0, taxCharges: 79.64, totalCharges: 113.14,
  },
  {
    // Futures: flat ₹20 brokerage, STT on the traded value, sell side only.
    order: 'b1b4adf7', symbol: 'ONGC SEP FUT', instrumentType: 'FUTURE', side: 'sell',
    quantity: 2250, price: 233.60721137647332,
    brokerage: 20, stampDuty: 0, taxCharges: 279.62, totalCharges: 299.62,
  },
  {
    // Options: STT is on the PREMIUM, not the notional. 65 x ₹108.42 is ₹7,047
    // of premium against ₹1.59 crore of notional — charging the notional would
    // have produced ₹23,800 of STT instead of ₹10.57.
    order: '78ed6ae2', symbol: '^NSEI-2026-09-01-24500-CE', instrumentType: 'OPTION', side: 'sell',
    quantity: 65, price: 108.42,
    brokerage: 20, stampDuty: 0, taxCharges: 17.12, totalCharges: 37.12,
  },
]

let failures = 0

for (const f of FIXTURES) {
  const got = calculateCharges({
    instrumentType: f.instrumentType,
    side: f.side,
    quantity: f.quantity,
    price: f.price,
    market: 'stock',
    config: CONFIG_2026,
  })

  const checks: [string, number, number][] = [
    ['brokerage', got.brokerage, f.brokerage],
    ['stampDuty', got.stampDuty, f.stampDuty],
    ['taxCharges', got.taxCharges, f.taxCharges],
    ['totalCharges', got.totalCharges, f.totalCharges],
  ]

  for (const [field, actual, expected] of checks) {
    if (actual !== expected) {
      failures++
      console.error(
        `FAIL ${f.order} ${f.symbol} ${f.side} ${f.instrumentType}: ` +
          `${field} expected ${expected}, got ${actual}`,
      )
    }
  }
  if (failures === 0) {
    console.log(`ok   ${f.order} ${f.symbol.padEnd(26)} ${f.side.padEnd(4)} total=₹${got.totalCharges}`)
  }
}

// Non-Indian markets trade free, because the engine only computes charges when
// market === 'stock'. Getting this wrong would quote a fee that never lands.
for (const market of ['crypto', 'us_stock']) {
  const c = calculateCharges({
    instrumentType: 'EQUITY', side: 'buy', quantity: 10, price: 1000, market,
    config: CONFIG_2026,
  })
  assert.equal(c.totalCharges, 0, `${market} must be free of charges`)
}
console.log('ok   crypto and us_stock incur no charges')

// Degenerate input must not produce a charge. A zero-priced or zero-quantity
// preview is a UI mid-edit state, not a trade.
for (const [q, p] of [[0, 100], [10, 0], [-5, 100], [Number.NaN, 100]]) {
  assert.equal(
    calculateCharges({
      instrumentType: 'EQUITY', side: 'buy', quantity: q, price: p,
      market: 'stock', config: CONFIG_2026,
    }).totalCharges,
    0,
  )
}
console.log('ok   zero / negative / NaN inputs charge nothing')

// GST is on service fees only: STT, stamp duty and DP must be outside its base.
// If STT ever slipped into the GST base, an equity sell would be overcharged by
// 18% of the STT, which on the GOLDBEES fixture is ₹235 — big enough to matter
// and small enough to be missed without an explicit assertion.
{
  const c = calculateCharges({
    instrumentType: 'EQUITY', side: 'sell', quantity: 10000, price: 131,
    market: 'stock', config: CONFIG_2026,
  })
  const serviceBase = c.brokerage + c.exchange + c.clearing + c.sebi + c.turnover + c.otherFee
  assert.ok(
    Math.abs(c.gst - serviceBase * 0.18) < 0.01,
    `GST base drifted: gst=${c.gst}, 18% of services=${(serviceBase * 0.18).toFixed(2)}`,
  )
}
console.log('ok   GST applies to service fees only, not STT / stamp duty / DP')

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed against real engine-computed charges.`)
  process.exit(1)
}
console.log('\nAll charge checks passed.')
