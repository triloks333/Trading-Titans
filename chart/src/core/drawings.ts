import type { IChartApi, ISeriesApi, SeriesType, UTCTimestamp } from 'lightweight-charts'

import { palette } from './theme'
import type { Seconds, ThemeMode } from './types'

/*
 * Trendlines and horizontal lines, drawn by hand on the chart.
 *
 * WHY AN OVERLAY CANVAS AND NOT A SERIES
 * lightweight-charts has no drawing primitives. The obvious cheat — a two-point
 * LineSeries per trendline — fails on the thing that makes a trendline useful:
 * it would be clipped to the data range, so it could not be extended past the
 * last bar to where price is heading, which is most of the point. It would also
 * take part in autoscaling and drag the price axis around.
 *
 * So drawings live on their own <canvas> above the chart, and are repainted
 * whenever the chart moves. Anchors are stored in DATA space (a timestamp and a
 * price), never in pixels, so a line stays attached to the bars it was drawn
 * against through pan, zoom, timeframe change and resize. Storing pixels is the
 * classic version of this bug: the drawing looks right until the user scrolls.
 *
 * ponytail: two tools, not Zerodha's six. Rectangles and Fibonacci are new maths
 * on this same foundation — coordinate mapping, hit-testing, drag handles and
 * persistence are all here already — but support and resistance is what people
 * actually draw, and two tools that feel right beat six that are fiddly under a
 * thumb. The ceiling is the tool list; the upgrade path is another `kind` and
 * another branch in `pointsOf` and `paint`.
 */

export type DrawingKind = 'trend' | 'horizontal'

export interface DrawingAnchor {
  /** Bar time in SECONDS, matching Candle.time. */
  time: Seconds
  price: number
}

export interface Drawing {
  id: string
  kind: DrawingKind
  /** Two anchors for a trendline; the first only for a horizontal. */
  anchors: DrawingAnchor[]
  colour?: string
}

/** Pixels within which a click counts as hitting a line. Sized for a fingertip. */
const HIT_SLOP = 11

/** Half-width of a drag handle, in pixels. */
const HANDLE = 5

export interface DrawingLayer {
  /** Repaints from the chart's current scales. Cheap; safe to call on every move. */
  redraw(): void
  /** Arms the next drag to create a drawing of this kind. Null cancels. */
  setTool(kind: DrawingKind | null): void
  activeTool(): DrawingKind | null
  list(): readonly Drawing[]
  replaceAll(drawings: Drawing[]): void
  /** Removes the selected drawing, if any. Returns true when one went. */
  deleteSelected(): boolean
  clear(): void
  setMode(mode: ThemeMode): void
  /** Fires whenever the set changes, so the host can persist it. */
  onChange(fn: (drawings: Drawing[]) => void): void
  /**
   * Fires when a tool is armed or disarms itself, so a toolbar can follow.
   *
   * Needed because finishing a line disarms the tool from inside — without this the
   * button would stay lit for a tool that is no longer active.
   */
  onToolChange(fn: (kind: DrawingKind | null) => void): void
  destroy(): void
}

export function createDrawingLayer(
  container: HTMLElement,
  chart: IChartApi,
  priceSeries: () => ISeriesApi<SeriesType> | null,
  initialMode: ThemeMode,
): DrawingLayer {
  let mode = initialMode
  let drawings: Drawing[] = []
  let tool: DrawingKind | null = null
  let selected: string | null = null
  let changed: (d: Drawing[]) => void = () => {}
  let toolChanged: (kind: DrawingKind | null) => void = () => {}

  /**
   * Single place that puts a tool away.
   *
   * Load-bearing: a tool that disarms without releasing pointer capture leaves the
   * overlay swallowing every gesture, and the chart silently stops panning with no
   * way for the user to get it back. Clearing the flag and the pointer state
   * together is the only reason that cannot drift apart.
   */
  function disarm(): void {
    tool = null
    pointerEnabled(selected !== null)
    toolChanged(null)
  }

  /** In-progress creation, or a grab of an existing anchor. */
  let dragging:
    | { type: 'create'; drawing: Drawing }
    | { type: 'move'; id: string; anchorIndex: number }
    | null = null

  const canvas = document.createElement('canvas')
  // Transparent to pointers until a tool is armed or something is selected, so the
  // chart keeps its own pan and pinch. Without this the overlay would swallow
  // every gesture and the chart would stop scrolling the moment drawings shipped.
  // `top:0;left:0` rather than `inset:0`, because the height is set explicitly to
  // the price pane's — see priceePaneHeight. `inset:0` would stretch it back over
  // the study panes and undo that.
  canvas.style.cssText =
    'position:absolute;top:0;left:0;z-index:3;pointer-events:none;touch-action:none'
  container.append(canvas)

  function pointerEnabled(on: boolean): void {
    canvas.style.pointerEvents = on ? 'auto' : 'none'
  }

  // ── Coordinate mapping ────────────────────────────────────────────────────

  function toX(time: Seconds): number | null {
    const x = chart.timeScale().timeToCoordinate((time as number) as UTCTimestamp)
    return x === null ? null : x
  }

  function toY(price: number): number | null {
    const s = priceSeries()
    if (!s) return null
    const y = s.priceToCoordinate(price)
    return y === null ? null : y
  }

  function fromX(x: number): Seconds | null {
    const t = chart.timeScale().coordinateToTime(x)
    return t === null ? null : (t as unknown as Seconds)
  }

  function fromY(y: number): number | null {
    const s = priceSeries()
    if (!s) return null
    const p = s.coordinateToPrice(y)
    return p === null ? null : (p as number)
  }

  /**
   * Screen points for a drawing, or null when it cannot be placed right now.
   *
   * A horizontal line spans the full width by construction, so it survives a pan
   * that takes its anchor bar off screen — which is exactly when a support level
   * matters. A trendline needs both ends; `timeToCoordinate` returns null for a
   * time outside the current range, so each end falls back to an extrapolation
   * from the other rather than the line vanishing mid-drag.
   */
  function pointsOf(d: Drawing): { x1: number; y1: number; x2: number; y2: number } | null {
    const a = d.anchors[0]
    if (!a) return null
    const y1 = toY(a.price)
    if (y1 === null) return null

    if (d.kind === 'horizontal') {
      return { x1: 0, y1, x2: canvas.clientWidth, y2: y1 }
    }

    const b = d.anchors[1]
    if (!b) return null
    const y2 = toY(b.price)
    if (y2 === null) return null
    const xa = toX(a.time)
    const xb = toX(b.time)
    if (xa === null || xb === null) return null
    return { x1: xa, y1, x2: xb, y2 }
  }

  // ── Painting ──────────────────────────────────────────────────────────────

  /**
   * Height of the price pane, which is not the height of the container.
   *
   * With an oscillator on, the chart splits into stacked panes and the price series
   * only occupies the first. An overlay spanning the full height meant a gesture in
   * the RSI pane was handed to `coordinateToPrice` on the price series, which
   * answers with nothing usable — the drawing silently failed to record. It also
   * painted trendlines across the oscillator.
   */
  function priceePaneHeight(): number {
    try {
      const h = chart.panes()[0]?.getHeight()
      if (typeof h === 'number' && h > 0) return h
    } catch {
      // Older/newer lightweight-charts without panes(): fall back to the container,
      // which is correct whenever there are no study panes.
    }
    return container.clientHeight
  }

  function redraw(): void {
    const dpr = window.devicePixelRatio || 1
    const w = container.clientWidth
    const h = priceePaneHeight()
    // Backing store in device pixels, CSS size in layout pixels, or the lines are
    // blurry on every phone made in the last decade.
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr)
      canvas.height = Math.round(h * dpr)
      canvas.style.width = `${w}px`
      canvas.style.height = `${h}px`
    }
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, w, h)

    const col = palette(mode)
    const live = dragging?.type === 'create' ? dragging.drawing : null
    for (const d of live ? [...drawings, live] : drawings) {
      const p = pointsOf(d)
      if (!p) continue
      const isSelected = d.id === selected

      ctx.save()
      ctx.strokeStyle = d.colour ?? col.accent
      ctx.lineWidth = isSelected ? 2.5 : 1.75
      ctx.setLineDash(d.kind === 'horizontal' ? [6, 4] : [])
      ctx.beginPath()
      ctx.moveTo(p.x1, p.y1)
      ctx.lineTo(p.x2, p.y2)
      ctx.stroke()

      // Price label on a horizontal line: a support level with no number on it
      // makes the user read it off the axis by eye.
      if (d.kind === 'horizontal') {
        const label = formatLevel(d.anchors[0]!.price)
        ctx.setLineDash([])
        ctx.font = '600 11px ui-monospace, "SF Mono", monospace'
        const tw = ctx.measureText(label).width
        ctx.fillStyle = d.colour ?? col.accent
        ctx.fillRect(4, p.y1 - 14, tw + 10, 15)
        ctx.fillStyle = '#ffffff'
        ctx.fillText(label, 9, p.y1 - 3)
      }

      if (isSelected) {
        ctx.setLineDash([])
        ctx.fillStyle = d.colour ?? col.accent
        for (const [hx, hy] of handlesOf(d, p)) {
          ctx.beginPath()
          ctx.rect(hx - HANDLE, hy - HANDLE, HANDLE * 2, HANDLE * 2)
          ctx.fill()
        }
      }
      ctx.restore()
    }
  }

  function formatLevel(v: number): string {
    const a = Math.abs(v)
    if (a >= 1000) return v.toFixed(1)
    if (a >= 1) return v.toFixed(2)
    return v.toFixed(4)
  }

  /** Draggable points, in screen space, in anchor order. */
  function handlesOf(
    d: Drawing,
    p: { x1: number; y1: number; x2: number; y2: number },
  ): [number, number][] {
    if (d.kind === 'horizontal') {
      // Middle of the visible span: the anchor bar is often off screen, and a
      // handle you cannot see is a drawing you cannot move.
      return [[(p.x1 + p.x2) / 2, p.y1]]
    }
    return [
      [p.x1, p.y1],
      [p.x2, p.y2],
    ]
  }

  // ── Hit testing ───────────────────────────────────────────────────────────

  /** Perpendicular distance from a point to a segment, in pixels. */
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
    // A degenerate segment is a point; without this guard t is 0/0 = NaN and the
    // drawing becomes impossible to select.
    if (lenSq === 0) return Math.hypot(px - x1, py - y1)
    let t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    t = Math.max(0, Math.min(1, t))
    return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
  }

  function hitTest(x: number, y: number): { id: string; anchorIndex: number | null } | null {
    // Topmost first, so the drawing painted last is the one grabbed.
    for (let i = drawings.length - 1; i >= 0; i--) {
      const d = drawings[i]!
      const p = pointsOf(d)
      if (!p) continue
      const handles = handlesOf(d, p)
      for (let h = 0; h < handles.length; h++) {
        const [hx, hy] = handles[h]!
        if (Math.abs(x - hx) <= HIT_SLOP && Math.abs(y - hy) <= HIT_SLOP) {
          // A horizontal has one handle but its anchor is index 0 either way.
          return { id: d.id, anchorIndex: d.kind === 'horizontal' ? 0 : h }
        }
      }
      if (distanceToSegment(x, y, p.x1, p.y1, p.x2, p.y2) <= HIT_SLOP) {
        return { id: d.id, anchorIndex: null }
      }
    }
    return null
  }

  // ── Pointer handling ──────────────────────────────────────────────────────

  /**
   * Keeps the drag alive if the finger leaves the canvas. Never fatal.
   *
   * `setPointerCapture` throws `InvalidStateError` when the pointer id is not
   * currently active, and an exception here used to abandon the whole gesture —
   * the anchor was set but nothing after it ran. Capture only improves a drag that
   * strays outside the chart; losing it must not lose the drawing.
   */
  function capture(e: PointerEvent): void {
    try {
      canvas.setPointerCapture(e.pointerId)
    } catch {
      // No active pointer with this id. The drag still tracks via pointermove.
    }
  }

  function localPoint(e: PointerEvent): { x: number; y: number } {
    const r = canvas.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }

  function anchorAt(x: number, y: number): DrawingAnchor | null {
    const time = fromX(x)
    const price = fromY(y)
    if (time === null || price === null) return null
    return { time, price }
  }

  function onPointerDown(e: PointerEvent): void {
    const { x, y } = localPoint(e)

    if (tool) {
      const a = anchorAt(x, y)
      if (!a) return
      const d: Drawing = {
        id: `d${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`,
        kind: tool,
        anchors: tool === 'horizontal' ? [a] : [a, { ...a }],
      }
      if (tool === 'horizontal') {
        // One click is the whole gesture: commit immediately rather than making the
        // user drag a line that spans the width no matter what they do.
        drawings = [...drawings, d]
        selected = d.id
        disarm()
        commit()
        redraw()
        return
      }
      dragging = { type: 'create', drawing: d }
      capture(e)
      e.preventDefault()
      return
    }

    const hit = hitTest(x, y)
    selected = hit?.id ?? null
    if (hit && hit.anchorIndex !== null) {
      dragging = { type: 'move', id: hit.id, anchorIndex: hit.anchorIndex }
      capture(e)
      e.preventDefault()
    } else if (!hit) {
      // Nothing here: hand the gesture back so the chart pans as usual.
      pointerEnabled(false)
    }
    redraw()
  }

  function onPointerMove(e: PointerEvent): void {
    if (!dragging) return
    const { x, y } = localPoint(e)
    const a = anchorAt(x, y)
    if (!a) return

    if (dragging.type === 'create') {
      dragging.drawing.anchors[1] = a
    } else {
      // Bound to a local so the narrowing survives the closure below.
      const grab = dragging
      const d = drawings.find((it) => it.id === grab.id)
      if (!d) return
      d.anchors[grab.anchorIndex] = a
    }
    e.preventDefault()
    redraw()
  }

  function onPointerUp(e: PointerEvent): void {
    if (!dragging) return
    if (dragging.type === 'create') {
      const d = dragging.drawing
      const p = pointsOf(d)
      // A tap rather than a drag leaves a zero-length line that is invisible and
      // unselectable. Discard it instead of littering the chart.
      const tooShort = p !== null && Math.hypot(p.x2 - p.x1, p.y2 - p.y1) < HIT_SLOP
      if (!tooShort) {
        drawings = [...drawings, d]
        selected = d.id
      }
      // Disarm before releasing capture, so the overlay hands gestures back to the
      // chart the moment the line is finished rather than staying greedy.
      disarm()
    }
    dragging = null
    try {
      if (canvas.hasPointerCapture(e.pointerId)) canvas.releasePointerCapture(e.pointerId)
    } catch {
      // Capture was never taken, or the pointer is already gone.
    }
    commit()
    redraw()
  }

  canvas.addEventListener('pointerdown', onPointerDown)
  canvas.addEventListener('pointermove', onPointerMove)
  canvas.addEventListener('pointerup', onPointerUp)
  canvas.addEventListener('pointercancel', onPointerUp)

  // Repaint whenever the chart moves under us. Both subscriptions matter: the
  // range one covers pan and zoom, the size one covers rotation and the keyboard
  // opening. Without them a line stays where it was painted while the bars slide
  // out from under it.
  const onRange = () => redraw()
  chart.timeScale().subscribeVisibleLogicalRangeChange(onRange)
  const resize = new ResizeObserver(() => redraw())
  resize.observe(container)

  function commit(): void {
    changed(drawings.map((d) => ({ ...d, anchors: d.anchors.map((a) => ({ ...a })) })))
  }

  return {
    redraw,

    setTool(kind) {
      selected = null
      if (kind === null) {
        disarm()
      } else {
        tool = kind
        // The overlay has to take pointers to receive the drawing gesture.
        pointerEnabled(true)
        toolChanged(kind)
      }
      redraw()
    },

    onToolChange(fn) {
      toolChanged = fn
    },

    activeTool: () => tool,
    list: () => drawings,

    replaceAll(next) {
      drawings = next.map((d) => ({ ...d, anchors: d.anchors.map((a) => ({ ...a })) }))
      selected = null
      redraw()
    },

    deleteSelected() {
      if (!selected) return false
      const before = drawings.length
      drawings = drawings.filter((d) => d.id !== selected)
      selected = null
      if (drawings.length === before) return false
      commit()
      redraw()
      return true
    },

    clear() {
      if (drawings.length === 0) return
      drawings = []
      selected = null
      commit()
      redraw()
    },

    setMode(next) {
      mode = next
      redraw()
    },

    onChange(fn) {
      changed = fn
    },

    destroy() {
      chart.timeScale().unsubscribeVisibleLogicalRangeChange(onRange)
      resize.disconnect()
      canvas.removeEventListener('pointerdown', onPointerDown)
      canvas.removeEventListener('pointermove', onPointerMove)
      canvas.removeEventListener('pointerup', onPointerUp)
      canvas.removeEventListener('pointercancel', onPointerUp)
      canvas.remove()
    },
  }
}

/*
 * Persistence, keyed per instrument and per drawing kind's data space.
 *
 * Same store and same reasoning as saved indicator templates: localStorage, so it
 * works for guests, offline and in the WebView, with no table or RLS to add. A
 * drawing is anchored in time and price, so it is meaningful on any timeframe of
 * the same symbol — which is why the key is the symbol alone and not symbol+period.
 */
const KEY = 'tt.chart.drawings.v1'

type Store = Record<string, Drawing[]>

function readStore(): Store {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return {}
    const parsed: unknown = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? (parsed as Store) : {}
  } catch {
    return {}
  }
}

/** Drops anything that would not draw, rather than trusting stored JSON. */
export function sanitiseDrawings(value: unknown): Drawing[] {
  if (!Array.isArray(value)) return []
  const out: Drawing[] = []
  for (const raw of value) {
    if (!raw || typeof raw !== 'object') continue
    const d = raw as Partial<Drawing>
    if (d.kind !== 'trend' && d.kind !== 'horizontal') continue
    const anchors = Array.isArray(d.anchors) ? d.anchors : []
    const clean = anchors
      .filter(
        (a): a is DrawingAnchor =>
          !!a && Number.isFinite((a as DrawingAnchor).time) &&
          Number.isFinite((a as DrawingAnchor).price),
      )
      .map((a) => ({ time: a.time, price: a.price }))
    // A trendline without both ends cannot be placed; a horizontal needs one.
    if (clean.length < (d.kind === 'trend' ? 2 : 1)) continue
    out.push({
      id: typeof d.id === 'string' && d.id ? d.id : `d${Math.random().toString(36).slice(2, 9)}`,
      kind: d.kind,
      anchors: clean,
      colour: typeof d.colour === 'string' ? d.colour : undefined,
    })
  }
  return out
}

export function loadDrawings(symbol: string): Drawing[] {
  return sanitiseDrawings(readStore()[symbol.toUpperCase()])
}

export function saveDrawings(symbol: string, drawings: Drawing[]): void {
  try {
    const store = readStore()
    const key = symbol.toUpperCase()
    if (drawings.length === 0) delete store[key]
    else store[key] = drawings
    localStorage.setItem(KEY, JSON.stringify(store))
  } catch {
    // Private browsing or a full quota. The drawings are already on the chart; only
    // their persistence is lost, which is not worth interrupting anyone over.
  }
}
