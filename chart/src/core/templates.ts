import { INDICATOR_BY_ID, defaultParams } from './registry'

/*
 * Saved indicator sets — "strategies", with a name the user chose.
 *
 * A template is a list of indicator ids with their parameters, plus a name and an
 * optional default flag. Applying one replaces whatever is currently on the chart.
 *
 * WHY SANITISE ON READ
 * A template is data the user saved at some point in the past, and the catalogue
 * moves underneath it. An indicator can be renamed, retired, or have a parameter
 * added; a value can be edited by hand in devtools or corrupted in storage. None
 * of that may throw, because the failure lands on someone opening a chart, and a
 * blank chart with a console error is the worst outcome available. `sanitise`
 * drops what it cannot honour and keeps the rest.
 */

/** One indicator inside a template. */
export interface TemplateEntry {
  id: string
  params: Record<string, number>
}

export interface ChartTemplate {
  /** Stable id, so a rename does not orphan the row. */
  key: string
  name: string
  entries: TemplateEntry[]
  /** Applied automatically when a chart opens. At most one per user. */
  isDefault: boolean
  updatedAt: number
}

export const MAX_NAME_LENGTH = 40

/** Trims and length-caps a user-supplied name. Empty is rejected by the caller. */
export function cleanName(raw: string): string {
  return raw.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH)
}

/**
 * Coerces whatever came out of storage into a usable template.
 *
 * Returns null when there is nothing salvageable — no name, or not a single
 * indicator the catalogue still recognises. A template of zero indicators would
 * present as "apply" doing nothing at all, which reads as broken.
 */
export function sanitise(raw: unknown): ChartTemplate | null {
  if (typeof raw !== 'object' || raw === null) return null
  const o = raw as Record<string, unknown>

  const name = typeof o.name === 'string' ? cleanName(o.name) : ''
  if (!name) return null

  const rawEntries = Array.isArray(o.entries) ? o.entries : []
  const entries: TemplateEntry[] = []
  const seen = new Set<string>()

  for (const e of rawEntries) {
    if (typeof e !== 'object' || e === null) continue
    const entry = e as Record<string, unknown>
    const id = typeof entry.id === 'string' ? entry.id : ''
    const spec = INDICATOR_BY_ID.get(id)
    // An indicator that no longer exists is dropped rather than carried as a
    // dead id that later fails to build.
    if (!spec) continue
    // The same indicator twice would stack two identical panes.
    if (seen.has(id)) continue
    seen.add(id)

    // Start from the defaults so a parameter added since the template was saved
    // has a value, then take only the ones the spec still declares.
    const params = defaultParams(spec)
    const savedParams =
      typeof entry.params === 'object' && entry.params !== null
        ? (entry.params as Record<string, unknown>)
        : {}
    for (const p of spec.params) {
      const v = savedParams[p.key]
      if (typeof v !== 'number' || !Number.isFinite(v)) continue
      // Clamped to the spec's own range. A hand-edited length of 100000 would
      // otherwise spin the whole series through a window that can never fill.
      params[p.key] = Math.min(p.max, Math.max(p.min, v))
    }
    entries.push({ id, params })
  }

  if (entries.length === 0) return null

  return {
    key: typeof o.key === 'string' && o.key ? o.key : newKey(),
    name,
    entries,
    isDefault: o.isDefault === true,
    updatedAt: typeof o.updatedAt === 'number' && Number.isFinite(o.updatedAt) ? o.updatedAt : Date.now(),
  }
}

/**
 * A key that does not need `crypto.randomUUID`.
 *
 * That API is unavailable on insecure origins, and the Flutter WebView loads this
 * bundle from a local asset — which is exactly such an origin. A collision here
 * costs one overwritten template, so time plus randomness is enough.
 */
export function newKey(): string {
  return `t_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
}

/** Sorts for display: the default first, then most recently touched. */
export function forDisplay(templates: ChartTemplate[]): ChartTemplate[] {
  return templates
    .slice()
    .sort((a, b) =>
      a.isDefault === b.isDefault ? b.updatedAt - a.updatedAt : a.isDefault ? -1 : 1,
    )
}

/**
 * Enforces at most one default across the set.
 *
 * Two defaults is not a state the UI can represent — a chart opens with one set of
 * indicators — so the most recently flagged wins and the rest are cleared.
 */
export function withSingleDefault(
  templates: ChartTemplate[],
  defaultKey: string | null,
): ChartTemplate[] {
  return templates.map((t) => ({ ...t, isDefault: t.key === defaultKey }))
}
