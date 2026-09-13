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

export type DrawingKind = 'trend' | 'horizontal' | 'fib' | 'rect' | 'arc'

export interface DrawingAnchor {
  /** Bar time in SECONDS, matching Candle.time. */
  time: Seconds
  price: number
}

export interface Drawing {
  id: string
  kind: DrawingKind
  /**
   * One anchor for a horizontal, two for everything else.
   *
   * For `fib` and `rect` the two anchors are opposite corners of the box; for
   * `arc` the first is the centre and the second sets the radius.
   */
  anchors: DrawingAnchor[]
  colour?: string
}

/**
 * How many anchors each kind needs to be drawable.
 *
 * One table rather than a scatter of `kind === 'horizontal' ? 1 : 2` checks, so
 * adding a kind cannot leave the creation path and the storage validator
 * disagreeing about whether a drawing is complete — which would store shapes that
 * then silently fail to paint.
 */
const ANCHORS_NEEDED: Record<DrawingKind, number> = {
  horizontal: 1,
  trend: 2,
  fib: 2,
  rect: 2,
  arc: 2,
}

/**
 * Fibonacci retracement levels, as fractions of the anchor span.
 *
 * 0 and 1 included so the two ends are drawn as levels too — a retracement with
 * no line on the swing high and low reads as though those are not part of it.
 * 78.6 is the square root of 61.8 and is the one people add by hand when a chart
 * package omits it.
 */
const FIB_LEVELS = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1] as const

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
      paintShape(ctx, d, p, w)

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

  /** A small filled caption, used for price levels. Returns nothing; paints. */
  function tag(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, fill: string): void {
    ctx.setLineDash([])
    ctx.font = '600 11px ui-monospace, "SF Mono", monospace'
    const tw = ctx.measureText(text).width
    ctx.fillStyle = fill
    ctx.fillRect(x, y - 14, tw + 10, 15)
    ctx.fillStyle = '#ffffff'
    ctx.fillText(text, x + 5, y - 3)
  }

  /**
   * The shape itself, per kind. Stroke style and width are already set.
   *
   * Everything here works off the same bounding segment `pointsOf` returns, which
   * is why adding a kind needs no coordinate work: for the two-anchor kinds
   * (x1,y1) and (x2,y2) are the anchors, and for `rect` and `fib` they are
   * opposite corners of the box those anchors describe.
   */
  function paintShape(
    ctx: CanvasRenderingContext2D,
    d: Drawing,
    p: { x1: number; y1: number; x2: number; y2: number },
    width: number,
  ): void {
    const stroke = ctx.strokeStyle as string

    if (d.kind === 'rect') {
      const x = Math.min(p.x1, p.x2)
      const y = Math.min(p.y1, p.y2)
      const rw = Math.abs(p.x2 - p.x1)
      const rh = Math.abs(p.y2 - p.y1)
      ctx.setLineDash([])
      // A faint wash so the box reads as a zone rather than four unrelated lines,
      // but light enough that the candles inside it stay legible — the point of
      // marking a range is to keep watching what happens inside it.
      ctx.globalAlpha = 0.1
      ctx.fillStyle = stroke
      ctx.fillRect(x, y, rw, rh)
      ctx.globalAlpha = 1
      ctx.strokeRect(x, y, rw, rh)
      return
    }

    if (d.kind === 'fib') {
      // Levels run between the two anchor PRICES, spanning from the left anchor to
      // the right edge: a retracement is read forward in time, so stopping the
      // lines at the second anchor hides the part you are waiting on.
      const left = Math.min(p.x1, p.x2)
      for (const level of FIB_LEVELS) {
        const y = p.y1 + (p.y2 - p.y1) * level
        // 0 and 1 are the swing itself, so they are solid; the retracements between
        // them are dashed, which is how every chart package distinguishes them.
        ctx.setLineDash(level === 0 || level === 1 ? [] : [5, 4])
        ctx.beginPath()
        ctx.moveTo(left, y)
        ctx.lineTo(width, y)
        ctx.stroke()
        // The percentage, not the price: the price is on the axis, and the whole
        // point of a retracement is which ratio the market is sitting on.
        tag(ctx, `${(level * 100).toFixed(1)}%`, left + 4, y, stroke)
      }
      return
    }

    if (d.kind === 'arc') {
      // Centred on the first anchor, radius out to the second, drawn as a
      // semicircle facing the way the second anchor lies.
      //
      // ponytail: a semicircle rather than a full Fibonacci arc set. The ceiling is
      // that it is one arc, not the 38.2/50/61.8 family; the upgrade path is the
      // same loop `fib` already uses, scaling the radius per level. One arc is what
      // "arc" was asked for and it needs no new state.
      const r = Math.hypot(p.x2 - p.x1, p.y2 - p.y1)
      if (r < 1) return
      const facing = Math.atan2(p.y2 - p.y1, p.x2 - p.x1)
      ctx.setLineDash([])
      ctx.beginPath()
      ctx.arc(p.x1, p.y1, r, facing - Math.PI / 2, facing + Math.PI / 2)
      ctx.stroke()
      return
    }

    // trend and horizontal: one straight segment. A horizontal is dashed and
    // carries its price, because a support level with no number on it makes the
    // user read it off the axis by eye.
    ctx.setLineDash(d.kind === 'horizontal' ? [6, 4] : [])
    ctx.beginPath()
    ctx.moveTo(p.x1, p.y1)
    ctx.lineTo(p.x2, p.y2)
    ctx.stroke()
    if (d.kind === 'horizontal') {
      tag(ctx, formatLevel(d.anchors[0]!.price), 4, p.y1, stroke)
    }
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

  /**
   * Distance in pixels from a point to the drawing as it is actually PAINTED.
   *
   * Load-bearing per kind. Measuring every shape against the bounding segment —
   * which is what the single `distanceToSegment` call used to do — would mean a
   * rectangle could only be selected by touching its diagonal, where nothing is
   * drawn, and a fib could only be grabbed on the sloping line between its
   * corners. The shape you can see has to be the shape you can hit.
   */
  function distanceTo(
    d: Drawing,
    p: { x1: number; y1: number; x2: number; y2: number },
    x: number,
    y: number,
    width: number,
  ): number {
    if (d.kind === 'rect') {
      const l = Math.min(p.x1, p.x2)
      const r = Math.max(p.x1, p.x2)
      const t = Math.min(p.y1, p.y2)
      const b = Math.max(p.y1, p.y2)
      // The four edges, not the filled interior: a big zone would otherwise swallow
      // every tap inside it, including taps meant for the chart underneath.
      return Math.min(
        distanceToSegment(x, y, l, t, r, t),
        distanceToSegment(x, y, l, b, r, b),
        distanceToSegment(x, y, l, t, l, b),
        distanceToSegment(x, y, r, t, r, b),
      )
    }

    if (d.kind === 'fib') {
      const left = Math.min(p.x1, p.x2)
      let best = Infinity
      for (const level of FIB_LEVELS) {
        const ly = p.y1 + (p.y2 - p.y1) * level
        best = Math.min(best, distanceToSegment(x, y, left, ly, width, ly))
      }
      return best
    }

    if (d.kind === 'arc') {
      const r = Math.hypot(p.x2 - p.x1, p.y2 - p.y1)
      if (r < 1) return Infinity
      // Radial distance from the circle, then reject the half that is not drawn, so
      // the invisible mirror semicircle is not selectable.
      const dx = x - p.x1
      const dy = y - p.y1
      const facing = Math.atan2(p.y2 - p.y1, p.x2 - p.x1)
      let delta = Math.atan2(dy, dx) - facing
      // Normalise to (-pi, pi] before comparing, or a point either side of the
      // wrap-around reads as being on the far side of the arc.
      while (delta > Math.PI) delta -= 2 * Math.PI
      while (delta < -Math.PI) delta += 2 * Math.PI
      if (Math.abs(delta) > Math.PI / 2) return Infinity
      return Math.abs(Math.hypot(dx, dy) - r)
    }

    return distanceToSegment(x, y, p.x1, p.y1, p.x2, p.y2)
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
      if (distanceTo(d, p, x, y, canvas.clientWidth) <= HIT_SLOP) {
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
        anchors: ANCHORS_NEEDED[tool] === 1 ? [a] : [a, { ...a }],
      }
      if (ANCHORS_NEEDED[tool] === 1) {
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
    // Membership test against the anchor table rather than a list of kinds, so a
    // kind added above cannot be silently rejected on read — which would look like
    // drawings vanishing after a reload.
    if (typeof d.kind !== 'string' || !(d.kind in ANCHORS_NEEDED)) continue
    const kind = d.kind as DrawingKind
    const anchors = Array.isArray(d.anchors) ? d.anchors : []
    const clean = anchors
      .filter(
        (a): a is DrawingAnchor =>
          !!a && Number.isFinite((a as DrawingAnchor).time) &&
          Number.isFinite((a as DrawingAnchor).price),
      )
      .map((a) => ({ time: a.time, price: a.price }))
    // Anything short of its anchors cannot be placed: a trendline, fib, rect or arc
    // needs both, a horizontal needs one.
    if (clean.length < ANCHORS_NEEDED[kind]) continue
    out.push({
      id: typeof d.id === 'string' && d.id ? d.id : `d${Math.random().toString(36).slice(2, 9)}`,
      kind,
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
