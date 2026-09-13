/*
 * The one runnable check behind remembered chart settings.
 *
 * Run with `npm test`. Assert-based, no framework. localStorage is stubbed with a
 * plain Map — eight lines, and it is the only reason this module needs a stub at
 * all, so a jsdom dependency would be a poor trade.
 *
 * The behaviour worth guarding is the MERGE. `savePrefs({ period })` writing a
 * fresh object would silently wipe the saved style, and that failure is invisible
 * until someone sets a line chart, changes timeframe, and finds themselves back on
 * candles with no idea why.
 */

import assert from 'node:assert/strict'

// Minimal localStorage. Only the three methods prefs.ts touches.
const store = new Map<string, string>()
;(globalThis as { localStorage?: unknown }).localStorage = {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => void store.set(k, v),
  removeItem: (k: string) => void store.delete(k),
}

const { loadPrefs, savePrefs } = await import('./prefs')

let checks = 0
function check(name: string, fn: () => void) {
  store.clear()
  fn()
  checks++
  console.log(`  ok  ${name}`)
}

console.log('chart prefs')

check('nothing stored reads as no preference, not as a default', () => {
  // Asserting the FIELDS, not the object shape: the no-value path returns {} and
  // the parsed path returns { period: undefined, style: undefined }, which
  // deepStrictEqual treats as different objects. Callers only ever read the two
  // fields, so that is what is worth pinning.
  //
  // Absent rather than defaulted matters: main.ts falls back to DEFAULT_PERIOD
  // itself, and a default invented here would be a second copy of it to drift.
  const p = loadPrefs()
  assert.equal(p.period, undefined)
  assert.equal(p.style, undefined)
})

check('a saved period and style come back', () => {
  savePrefs({ period: '15m', style: 'line' })
  const p = loadPrefs()
  assert.equal(p.period, '15m')
  assert.equal(p.style, 'line')
})

check('saving one setting does not wipe the other', () => {
  // THE REGRESSION THIS EXISTS FOR.
  savePrefs({ style: 'line' })
  savePrefs({ period: '30m' })
  const p = loadPrefs()
  assert.equal(p.style, 'line', 'style was clobbered by saving the period')
  assert.equal(p.period, '30m')

  savePrefs({ style: 'candles' })
  assert.equal(loadPrefs().period, '30m', 'period was clobbered by saving the style')
})

check('an unknown style is dropped rather than handed to the chart', () => {
  // A style from a newer build, or a typo. buildPriceSeries would be asked for a
  // series type that does not exist.
  store.set('tt.chart.prefs.v1', JSON.stringify({ style: 'heikin-ashi' }))
  assert.equal(loadPrefs().style, undefined)

  store.set('tt.chart.prefs.v1', JSON.stringify({ style: 42 }))
  assert.equal(loadPrefs().style, undefined)
})

check('a retired period id is returned as-is for periodFor to reject', () => {
  // Deliberately NOT validated here. periodFor is the single validator, and
  // main.ts normalises through it — duplicating the period list in this module is
  // how the two would drift. '3M' is the real one that went away.
  store.set('tt.chart.prefs.v1', JSON.stringify({ period: '3M' }))
  assert.equal(loadPrefs().period, '3M')
})

check('an empty or non-string period is dropped', () => {
  store.set('tt.chart.prefs.v1', JSON.stringify({ period: '' }))
  assert.equal(loadPrefs().period, undefined)

  store.set('tt.chart.prefs.v1', JSON.stringify({ period: 15 }))
  assert.equal(loadPrefs().period, undefined)
})

check('malformed storage never throws', () => {
  for (const junk of ['not json', '[1,2,3]', 'null', '"a string"', '42']) {
    store.set('tt.chart.prefs.v1', junk)
    const p = loadPrefs()
    assert.equal(p.period, undefined, `junk: ${junk}`)
    assert.equal(p.style, undefined, `junk: ${junk}`)
  }
})

check('a storage that refuses to write does not throw', () => {
  // Private browsing and a full quota both throw from setItem. The setting is
  // already applied in memory, so losing only its persistence is the right outcome.
  const original = (globalThis as { localStorage: { setItem: unknown } }).localStorage.setItem
  ;(globalThis as { localStorage: { setItem: unknown } }).localStorage.setItem = () => {
    throw new Error('QuotaExceededError')
  }
  assert.doesNotThrow(() => savePrefs({ period: '1h' }))
  ;(globalThis as { localStorage: { setItem: unknown } }).localStorage.setItem = original
})

console.log(`${checks} checks passed`)
