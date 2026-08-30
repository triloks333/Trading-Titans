import assert from 'node:assert/strict'
import {
  buildPositions,
  cashDayPnl,
  totalsOf,
  underlyingOf,
  type TodayActivity,
} from './positions.ts'
import type { Quote } from './types.ts'

/*
 * Runnable check for the portfolio model:  npm run check:positions
 *
 * Each case here corresponds to something the previous inline implementation got
 * wrong, so a regression fails loudly rather than quietly showing a user a number
 * that is not their position.
 */

const q = (symbol: string, market: string, price: number, previousClose = 0): Quote =>
  ({ symbol, market, price, previous_close: previousClose }) as Quote

const holding = (o: Partial<Record<string, unknown>>) =>
  ({
    id: String(o.id ?? '1'),
    symbol: String(o.symbol ?? 'X'),
    name: (o.name as string) ?? null,
    market: (o.market as string) ?? 'stock',
    quantity: Number(o.quantity ?? 0),
    avg_price: Number(o.avg_price ?? 0),
    native_avg_price: (o.native_avg_price as number) ?? null,
    native_currency: (o.native_currency as string) ?? null,
    instrument_type: 'EQUITY',
    created_at: null,
  })

const noActivity = new Map<string, TodayActivity>()

// ── 1. A short position must exist, and must gain when the price falls ────────
{
  const [p] = buildPositions({
    holdings: [holding({ symbol: 'RELIANCE', quantity: -10, avg_price: 1000 })],
    foPositions: [],
    quotes: [q('RELIANCE', 'stock', 900)],
    today: noActivity,
    usdInr: 0,
  })
  assert.ok(p, 'a short holding must produce a position, not be filtered away')
  assert.equal(p.isShort, true)
  // Sold at 1000, now 900: +₹100 a share on 10 shares.
  assert.equal(p.displayPnl, 1000)
  // Capital committed is the margin blocked, and value is margin + P&L, so that
  // wallet + positions reconciles the way it does on mobile.
  assert.equal(p.displayInvested, 10000)
  assert.equal(p.displayValue, 11000)
  console.log('ok   short position exists and profits as the price falls')
}

// A short must LOSE when the price rises — the sign has to be genuinely derived,
// not accidentally right for one direction.
{
  const [p] = buildPositions({
    holdings: [holding({ symbol: 'RELIANCE', quantity: -10, avg_price: 1000 })],
    foPositions: [],
    quotes: [q('RELIANCE', 'stock', 1100)],
    today: noActivity,
    usdInr: 0,
  })
  assert.equal(p.displayPnl, -1000)
  console.log('ok   short position loses as the price rises')
}

// ── 2. A US position must not mix dollars with rupees ────────────────────────
{
  // Bought 10 AAPL at $300 when the rate was 90, so the wallet paid ₹270,000.
  // Now $320 with the rate at 95.
  const [p] = buildPositions({
    holdings: [
      holding({
        symbol: 'AAPL', market: 'us_stock', quantity: 10,
        avg_price: 270_000 / 10, native_avg_price: 300, native_currency: 'USD',
      }),
    ],
    foPositions: [],
    quotes: [q('AAPL', 'us_stock', 320)],
    today: noActivity,
    usdInr: 95,
  })
  assert.equal(p.currency, 'USD')
  assert.equal(p.displayAvgPrice, 300)
  assert.equal(p.displayLtp, 320)
  // In its own currency: $20 a share on 10 shares.
  assert.equal(p.displayPnl, 200)
  assert.equal(p.displayInvested, 3000)
  // The rupee cost basis is what the wallet actually paid, at the fill-day rate —
  // NOT today's rate applied to the dollar basis, which would invent FX P&L that
  // never happened.
  assert.equal(p.investedInr, 270_000)
  // Rupee value converts the dollar value at today's rate: $3,200 x 95.
  assert.equal(p.valueInr, 304_000)
  assert.equal(p.pnlInr, 34_000)
  // Had the naive version run, it would have done 320*10 - 27000*10 and produced
  // a loss of ₹266,800 on a winning position.
  assert.ok(p.pnlInr > 0, 'a winning US position must not read as a loss')
  console.log('ok   US position stays in one currency; rupee basis is what was paid')
}

// With no FX rate, rupee figures are withheld and flagged rather than guessed.
{
  const [p] = buildPositions({
    holdings: [
      holding({
        symbol: 'AAPL', market: 'us_stock', quantity: 10,
        avg_price: 27_000, native_avg_price: 300, native_currency: 'USD',
      }),
    ],
    foPositions: [],
    quotes: [q('AAPL', 'us_stock', 320)],
    today: noActivity,
    usdInr: 0,
  })
  assert.equal(p.inrUnavailable, true)
  assert.equal(p.displayPnl, 200, 'the dollar figure is still exact')
  const t = totalsOf([p])
  assert.equal(t.partial, true, 'totals must admit they exclude something')
  assert.equal(t.valueInr, 0)
  console.log('ok   a missing FX rate is disclosed, not filled in with a guess')
}

// ── 3. F&O positions must appear, and be valued with the shared model ────────
{
  const positions = buildPositions({
    holdings: [],
    foPositions: [
      {
        id: 'f1', symbol: 'ONGC SEP FUT', instrument_type: 'FUTURE',
        option_type: null, strike_price: null,
        expiry_date: new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10),
        lot_size: 2250, net_qty: -1, avg_entry_price: 240, margin_blocked: 81_000,
        created_at: null,
      },
    ],
    quotes: [q('ONGC', 'stock', 233)],
    today: noActivity,
    usdInr: 0,
  })
  assert.equal(positions.length, 1, 'fo_positions must not be ignored')
  const p = positions[0]
  assert.equal(p.kind, 'FUTURE')
  assert.equal(p.units, -2250, 'lots must be expanded by lot size')
  assert.equal(p.isShort, true)
  // Short a future at 240 with the modelled price near 234: a gain.
  assert.ok(p.displayPnl > 0, `expected a gain on a short future, got ${p.displayPnl}`)
  assert.equal(p.displayInvested, 81_000, 'a future commits margin, not notional')
  console.log('ok   F&O positions appear, expand lots, and value with the shared model')
}

// A long option commits its premium, not margin.
{
  const [p] = buildPositions({
    holdings: [],
    foPositions: [
      {
        id: 'f2', symbol: '^NSEI', instrument_type: 'OPTION',
        option_type: 'CE', strike_price: 24500,
        expiry_date: new Date(Date.now() + 3 * 86_400_000).toISOString().slice(0, 10),
        lot_size: 65, net_qty: 1, avg_entry_price: 100, margin_blocked: 0,
        created_at: null,
      },
    ],
    quotes: [q('NIFTY', 'stock', 24_600)],
    today: noActivity,
    usdInr: 0,
  })
  assert.equal(p.kind, 'OPTION')
  assert.equal(p.displayInvested, 6500, 'a long option commits the premium paid')
  assert.match(p.label, /24500 CE/)
  console.log('ok   long option commits premium; label reads as a contract')
}

// ── 4. Day P&L must account for trading done today ───────────────────────────
{
  // Held 100 from yesterday's close of 100, now 110, nothing traded today.
  assert.equal(cashDayPnl(100, 110, 100, undefined), 1000)

  // Bought all 100 today at 105; the move from 100 to 105 was not ours.
  const boughtToday: TodayActivity = {
    bought: 100, soldQty: 0, cashIn: 10_500, cashOut: 0, realizedNet: 0,
  }
  assert.equal(cashDayPnl(100, 110, 100, boughtToday), 500)
  // The naive (ltp - prevClose) * qty would have claimed ₹1,000 — double.

  // Flat after closing out today: day P&L is what was banked, net of charges.
  const closed: TodayActivity = {
    bought: 0, soldQty: 100, cashIn: 0, cashOut: 11_000, realizedNet: 940,
  }
  assert.equal(cashDayPnl(0, 110, 100, closed), 940)

  // No previous close means no honest answer.
  assert.equal(cashDayPnl(100, 110, 0, undefined), 0)
  console.log("ok   day P&L discounts moves that happened before you owned it")
}

// ── 5. Underlying extraction, for the F&O spot lookup ───────────────────────
{
  const cases: [string, string][] = [
    ['^NSEI', 'NIFTY'],
    ['SENSEX', 'SENSEX'],
    ['^BSESN', 'SENSEX'],
    ['ONGC SEP FUT', 'ONGC'],
    ['NSE:HDFCBANK26SEPFUT', 'HDFCBANK'],
    ['^NSEI-2026-09-01-24500-CE', 'NIFTY'],
    ['RELIANCE', 'RELIANCE'],
  ]
  for (const [input, expected] of cases) {
    assert.equal(underlyingOf(input), expected, `underlyingOf(${input})`)
  }
  console.log('ok   F&O symbols resolve to the underlying the spot is cached under')
}

// ── 6. Totals ───────────────────────────────────────────────────────────────
{
  const positions = buildPositions({
    holdings: [
      holding({ id: 'a', symbol: 'A', quantity: 10, avg_price: 100 }),
      holding({ id: 'b', symbol: 'B', quantity: -5, avg_price: 200 }),
    ],
    foPositions: [],
    quotes: [q('A', 'stock', 120), q('B', 'stock', 180)],
    today: noActivity,
    usdInr: 0,
  })
  const t = totalsOf(positions)
  // A: invested 1000, pnl +200. B short: invested 1000, pnl +100.
  assert.equal(t.investedInr, 2000)
  assert.equal(t.pnlInr, 300)
  assert.equal(t.valueInr, 2300)
  assert.equal(t.partial, false)
  assert.ok(Math.abs(t.pnlPct - 15) < 1e-9)
  console.log('ok   totals include shorts and reconcile invested + P&L = value')
}

console.log('\nAll position checks passed.')
