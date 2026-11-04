/*
 * The runnable check behind the live feed. Run with `npm test`.
 *
 * Guards the two rules that are easy to break and invisible when broken: crypto
 * USDT trades must come out in rupees at the INR pair's level (or the candle
 * jumps by the exchange premium), and an option must poll its underlying (or the
 * premium is drawn onto the underlying's candles).
 */

import assert from 'node:assert/strict'
import type { Sample } from '../core/types'

// A WebSocket stand-in that records sends and lets the test play server frames.
class FakeSocket {
  static last: FakeSocket
  sent: string[] = []
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  constructor(public url: string) {
    FakeSocket.last = this
  }
  send(s: string) {
    this.sent.push(s)
  }
  close() {}
  emit(s: string) {
    this.onmessage?.({ data: s })
  }
}
;(globalThis as { WebSocket?: unknown }).WebSocket = FakeSocket

const trade = (p: number, T = 1_793_637_600_000) => JSON.stringify({ e: 'trade', p: String(p), T })

const { streamLive } = await import('./stream')

console.log('crypto: USDT trades scaled to the INR level')
{
  const ticks: Sample[] = []
  const s = streamLive('B-BTC_USDT', 'crypto', (t) => ticks.push(t), 7_800_000)
  const ws = FakeSocket.last
  assert.match(ws.url, /\/btcusdt@trade$/, 'a perpetual streams its coin')

  ws.emit(trade(78_000)) // anchors: 7.8M / 78k = 100 INR per USDT
  ws.emit(trade(78_100))
  assert.equal(ticks[0]!.price, 7_800_000)
  assert.equal(ticks[1]!.price, 7_810_000)
  assert.equal(ticks[1]!.time, 1_793_637_600)

  ws.emit('{"result":null,"id":1}')
  assert.equal(ticks.length, 2, 'non-trade frames are not ticks')
  assert.ok(s.lastSeen() > 0)
  s.stop()
}

console.log('crypto: no anchor, no ticks')
{
  const ticks: Sample[] = []
  const s = streamLive('ETH', 'crypto', (t) => ticks.push(t))
  FakeSocket.last.emit(trade(3_000))
  assert.equal(ticks.length, 0)
  s.stop()
}

console.log('stocks: an option polls its underlying, not the contract')
{
  const urls: string[] = []
  ;(globalThis as { fetch?: unknown }).fetch = async (u: string) => {
    urls.push(u)
    return new Response(JSON.stringify({ price: 2_500 }))
  }
  const ticks: Sample[] = []
  const s = streamLive('RELIANCE-2026-11-27-2500-CE', 'stock', (t) => ticks.push(t))
  await new Promise((r) => setTimeout(r, 50))
  assert.match(urls[0]!, /symbol=RELIANCE&/)
  assert.equal(ticks.length, 1)
  assert.equal(ticks[0]!.price, 2_500)
  s.stop()
}

console.log('stream: all checks passed')
