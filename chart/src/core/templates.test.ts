/*
 * Checks for saved strategies.
 *
 * Run with `npm test`. The whole point of `sanitise` is that a template is data
 * from the past being read against a catalogue that has moved on, so these cases
 * are deliberately hostile: retired indicators, parameters that no longer exist,
 * lengths a person typed into devtools, duplicated entries, and outright garbage.
 * Every one of them lands on somebody opening a chart, and a blank chart with a
 * console error is the worst thing that can happen there.
 */

import assert from 'node:assert/strict'
import {
  MAX_NAME_LENGTH,
  cleanName,
  forDisplay,
  newKey,
  sanitise,
  withSingleDefault,
  type ChartTemplate,
} from './templates'
import { INDICATOR_BY_ID } from './registry'

let checks = 0
function check(name: string, fn: () => void) {
  fn()
  checks++
  console.log(`  ok  ${name}`)
}

console.log('cleanName')

check('collapses whitespace and caps the length', () => {
  assert.equal(cleanName('  My   Swing  Setup '), 'My Swing Setup')
  assert.equal(cleanName('x'.repeat(200)).length, MAX_NAME_LENGTH)
  assert.equal(cleanName('   '), '')
})

console.log('sanitise')

check('accepts a well-formed template', () => {
  const t = sanitise({
    key: 't_abc',
    name: 'Trend follow',
    entries: [{ id: 'ema', params: { length: 50 } }],
    isDefault: true,
    updatedAt: 1000,
  })
  assert.equal(t?.name, 'Trend follow')
  assert.equal(t?.entries.length, 1)
  assert.equal(t?.entries[0]!.params.length, 50)
  assert.equal(t?.isDefault, true)
})

check('drops an indicator the catalogue no longer has', () => {
  // The case that matters: someone saved a strategy, we retired an indicator.
  const t = sanitise({
    name: 'Mixed',
    entries: [{ id: 'ema', params: {} }, { id: 'no_such_indicator', params: {} }],
  })
  assert.equal(t?.entries.length, 1)
  assert.equal(t?.entries[0]!.id, 'ema')
})

check('returns null rather than an empty template', () => {
  // "Apply" on a template with nothing in it looks like the button is broken.
  assert.equal(sanitise({ name: 'Gone', entries: [{ id: 'retired' }] }), null)
  assert.equal(sanitise({ name: 'Empty', entries: [] }), null)
})

check('refuses anything without a usable name', () => {
  assert.equal(sanitise({ name: '   ', entries: [{ id: 'ema' }] }), null)
  assert.equal(sanitise({ entries: [{ id: 'ema' }] }), null)
  assert.equal(sanitise(null), null)
  assert.equal(sanitise('a string'), null)
  assert.equal(sanitise(42), null)
})

check('fills in a parameter added since the template was saved', () => {
  // Saved when MACD had no signal period; the default has to appear.
  const t = sanitise({ name: 'Old MACD', entries: [{ id: 'macd', params: { fast: 10 } }] })
  const p = t!.entries[0]!.params
  assert.equal(p.fast, 10)
  assert.equal(p.slow, INDICATOR_BY_ID.get('macd')!.params.find((x) => x.key === 'slow')!.default)
  assert.equal(p.signal, 9)
})

check('clamps a parameter to the spec range', () => {
  // A length of 100000 spins every bar through a window that can never fill.
  const spec = INDICATOR_BY_ID.get('ema')!
  const max = spec.params[0]!.max
  const hi = sanitise({ name: 'Huge', entries: [{ id: 'ema', params: { length: 100000 } }] })
  assert.equal(hi!.entries[0]!.params.length, max)

  const lo = sanitise({ name: 'Tiny', entries: [{ id: 'ema', params: { length: -5 } }] })
  assert.equal(lo!.entries[0]!.params.length, spec.params[0]!.min)
})

check('ignores non-numeric and unknown parameters', () => {
  const t = sanitise({
    name: 'Junk params',
    entries: [{ id: 'ema', params: { length: 'twenty', bogus: 3, other: NaN } }],
  })
  const p = t!.entries[0]!.params
  assert.equal(p.length, 21, 'falls back to the default')
  assert.equal('bogus' in p, false, 'a parameter the spec does not declare is dropped')
})

check('collapses the same indicator listed twice', () => {
  // Two identical entries would stack two identical panes.
  const t = sanitise({ name: 'Dupe', entries: [{ id: 'rsi' }, { id: 'rsi' }] })
  assert.equal(t?.entries.length, 1)
})

check('mints a key when one is missing and keeps a supplied one', () => {
  assert.equal(sanitise({ key: 't_keep', name: 'A', entries: [{ id: 'ema' }] })!.key, 't_keep')
  assert.ok(sanitise({ name: 'B', entries: [{ id: 'ema' }] })!.key.startsWith('t_'))
})

check('survives a malformed entry without throwing', () => {
  const t = sanitise({
    name: 'Rough',
    entries: [null, 'ema', 7, { id: 'ema' }, { nope: true }],
  })
  assert.equal(t?.entries.length, 1)
})

console.log('newKey')

check('keys are unique and need no crypto.randomUUID', () => {
  // randomUUID is unavailable on insecure origins, and the Flutter WebView loads
  // this bundle from a local asset — exactly such an origin.
  const keys = new Set(Array.from({ length: 500 }, () => newKey()))
  assert.equal(keys.size, 500)
})

console.log('ordering and defaults')

const mk = (name: string, updatedAt: number, isDefault = false): ChartTemplate => ({
  key: `k_${name}`,
  name,
  entries: [{ id: 'ema', params: { length: 21 } }],
  isDefault,
  updatedAt,
})

check('the default sorts first, then most recently touched', () => {
  const out = forDisplay([mk('old', 1), mk('new', 3), mk('starred', 2, true)])
  assert.deepEqual(out.map((t) => t.name), ['starred', 'new', 'old'])
})

check('only one template can be the default', () => {
  // Two defaults is not a state the UI can represent: a chart opens with one set.
  const out = withSingleDefault([mk('a', 1, true), mk('b', 2, true)], 'k_b')
  assert.deepEqual(out.map((t) => t.isDefault), [false, true])
})

check('passing null clears every default', () => {
  const out = withSingleDefault([mk('a', 1, true), mk('b', 2)], null)
  assert.equal(out.some((t) => t.isDefault), false)
})

console.log(`\n${checks} checks passed`)
