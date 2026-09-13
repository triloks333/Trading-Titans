import assert from 'node:assert/strict'

import { sanitiseDrawings } from './drawings'
import type { Drawing } from './drawings'

/*
 * Drawing maths and the storage boundary.
 *
 * The geometry is duplicated here rather than exported from drawings.ts on purpose:
 * `distanceToSegment` is private to a module that touches `document` on import, so
 * pulling it out to test it would mean either a DOM shim in the test or widening the
 * public surface for a helper nobody else should call. The formula below is the same
 * one, and if the two ever disagree the assertions stop describing the shipped
 * behaviour — which is the honest cost of this shortcut.
 *
 * ponytail: a copied formula, tested. The ceiling is drift between the two;
 * the upgrade path is a geometry module both import once there is a second caller.
 */
function distanceToSegment(
  px: number,
  py: number,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
): number {
  const dx = x2 - x1
  const dy = y2 - y1
  const lenSq = dx * dx + dy * dy
  if (lenSq === 0) return Math.hypot(px - x1, py - y1)
  let t = ((px - x1) * dx + (py - y1) * dy) / lenSq
  t = Math.max(0, Math.min(1, t))
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
}

let checks = 0
function check(name: string, fn: () => void): void {
  fn()
  checks++
  console.log(`  ok  ${name}`)
}

console.log('hit testing')

check('a point on the line has zero distance, and perpendicular offset is exact', () => {
  // Horizontal segment from (0,100) to (100,100).
  assert.equal(distanceToSegment(50, 100, 0, 100, 100, 100), 0)
  assert.equal(distanceToSegment(50, 111, 0, 100, 100, 100), 11)
})

check('distance clamps to the ends rather than the infinite line', () => {
  // Beyond the right end: the nearest point is the endpoint, not the projection.
  // Without the clamp a trendline would be grabbable anywhere along its infinite
  // extension, including far off screen.
  assert.equal(distanceToSegment(160, 100, 0, 100, 100, 100), 60)
  assert.equal(distanceToSegment(-40, 100, 0, 100, 100, 100), 40)
})

check('a zero-length segment does not divide by zero', () => {
  // Two identical anchors happen when a tap is registered as a drag. NaN here would
  // make the drawing permanently unselectable, so it could never be deleted.
  const d = distanceToSegment(3, 4, 10, 10, 10, 10)
  assert.ok(Number.isFinite(d), 'distance must stay finite')
  assert.equal(d, Math.hypot(7, 6))
})

check('a diagonal is measured perpendicular, not by axis', () => {
  // (0,0) to (10,10); the point (10,0) is 5*sqrt(2) away perpendicular, not 10.
  const d = distanceToSegment(10, 0, 0, 0, 10, 10)
  assert.ok(Math.abs(d - Math.sqrt(50)) < 1e-9, `expected ~7.07, got ${d}`)
})

console.log('stored drawings')

check('a trendline missing its second anchor is dropped', () => {
  // It cannot be placed, so keeping it would leave an invisible entry that still
  // counts towards "you have drawings on this chart".
  const out = sanitiseDrawings([{ id: 'a', kind: 'trend', anchors: [{ time: 1, price: 2 }] }])
  assert.equal(out.length, 0)
})

check('a horizontal needs only one anchor', () => {
  const out = sanitiseDrawings([{ id: 'h', kind: 'horizontal', anchors: [{ time: 1, price: 2 }] }])
  assert.equal(out.length, 1)
  assert.equal(out[0]!.kind, 'horizontal')
})

check('every kind requires exactly the anchors it needs', () => {
  // Table-driven against ANCHORS_NEEDED in drawings.ts. A kind added to the union
  // but forgotten in that table would either be dropped on read — drawings
  // vanishing after a reload — or stored with too few anchors and then silently
  // failing to paint, which looks identical to the storage being broken.
  const needed: Record<string, number> = {
    horizontal: 1,
    trend: 2,
    fib: 2,
    rect: 2,
    arc: 2,
  }
  const one = [{ time: 10, price: 100 }]
  const two = [{ time: 10, price: 100 }, { time: 20, price: 200 }]

  for (const [kind, n] of Object.entries(needed)) {
    assert.equal(
      sanitiseDrawings([{ id: 'a', kind, anchors: two }]).length,
      1,
      `${kind} should survive with two anchors`,
    )
    assert.equal(
      sanitiseDrawings([{ id: 'a', kind, anchors: one }]).length,
      n === 1 ? 1 : 0,
      `${kind} needs ${n} anchor(s)`,
    )
    assert.equal(
      sanitiseDrawings([{ id: 'a', kind, anchors: [] }]).length,
      0,
      `${kind} with no anchors cannot be placed`,
    )
  }
})

check('the kind is matched exactly, not fuzzily', () => {
  // 'fib' is a real kind; 'fibonacci' is not, and must not be coerced into one.
  // Storage can hold a name from any past or future build.
  const two = [{ time: 10, price: 100 }, { time: 20, price: 200 }]
  assert.equal(sanitiseDrawings([{ id: 'a', kind: 'fib', anchors: two }]).length, 1)
  for (const wrong of ['fibonacci', 'Fib', 'FIB', 'rectangle', 'circle', 'arcs', '']) {
    assert.equal(
      sanitiseDrawings([{ id: 'a', kind: wrong, anchors: two }]).length,
      0,
      `'${wrong}' must not be accepted`,
    )
  }
})

check('unknown kinds and non-finite anchors are dropped', () => {
  const out = sanitiseDrawings([
    { id: 'x', kind: 'fibonacci', anchors: [{ time: 1, price: 2 }, { time: 3, price: 4 }] },
    { id: 'y', kind: 'trend', anchors: [{ time: Number.NaN, price: 2 }, { time: 3, price: 4 }] },
    { id: 'z', kind: 'trend', anchors: [{ time: 1, price: Number.POSITIVE_INFINITY }] },
  ])
  assert.equal(out.length, 0)
})

check('malformed storage never throws', () => {
  // This is read on every chart open, so a hand-mangled value or an older shape
  // must degrade to "no drawings" rather than taking the chart down.
  for (const bad of [null, undefined, 42, 'nope', {}, [null], [{}], [{ kind: 'trend' }]]) {
    assert.deepEqual(sanitiseDrawings(bad), [])
  }
})

check('a valid pair survives intact and is copied, not aliased', () => {
  const input: Drawing[] = [
    { id: 'keep', kind: 'trend', anchors: [{ time: 10, price: 100 }, { time: 20, price: 200 }] },
  ]
  const out = sanitiseDrawings(input)
  assert.equal(out.length, 1)
  assert.equal(out[0]!.id, 'keep')
  assert.deepEqual(out[0]!.anchors, [{ time: 10, price: 100 }, { time: 20, price: 200 }])
  out[0]!.anchors[0]!.price = 999
  assert.equal(input[0]!.anchors[0]!.price, 100, 'sanitise must not mutate its input')
})

console.log(`\n${checks} checks passed`)
