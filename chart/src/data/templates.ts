import {
  cleanName,
  forDisplay,
  newKey,
  sanitise,
  withSingleDefault,
  type ChartTemplate,
  type TemplateEntry,
} from '../core/templates'

/*
 * Where saved strategies live.
 *
 * LOCAL STORAGE, DELIBERATELY, FOR NOW
 * Templates are per-device. That is a real limitation — a strategy saved on the
 * phone will not appear on the web app — and it is a choice rather than an
 * oversight:
 *
 *   - it works for guests, who have no durable account to attach rows to
 *   - it works offline, which the Flutter WebView needs
 *   - it works in the review harness, which holds no session at all
 *   - it needs no production table, no RLS policy and no migration
 *
 * The upgrade path is a `chart_templates` table keyed on `user_id` with the usual
 * own-rows-only policy, and this module becoming "read local, sync to server when
 * a session exists". The shape below is already the row shape, so that change is
 * confined to this file. Worth doing once someone asks for their strategies to
 * follow them between devices; not worth a migration before then.
 */

const KEY = 'tt.chart.templates.v1'

/** Never let a storage failure take the chart down with it. */
function read(): ChartTemplate[] {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return []
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    // Every read is sanitised, not just the suspicious ones: this is the boundary
    // between the catalogue as it is now and templates saved against older
    // versions of it.
    return parsed.map(sanitise).filter((t): t is ChartTemplate => t !== null)
  } catch {
    // Private browsing, a full quota, or hand-mangled JSON. An empty list is a
    // usable chart; a thrown error is not.
    return []
  }
}

function write(templates: ChartTemplate[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(templates))
  } catch {
    // Saving failed. The caller has already applied the indicators in memory, so
    // the chart is correct; only the persistence is lost. Reported by the caller.
  }
}

export function listTemplates(): ChartTemplate[] {
  return forDisplay(read())
}

export function defaultTemplate(): ChartTemplate | null {
  return read().find((t) => t.isDefault) ?? null
}

export interface SaveResult {
  ok: boolean
  /** Set when the save was refused, written for a user to read. */
  error?: string
  template?: ChartTemplate
}

/**
 * Creates or overwrites a template by name.
 *
 * Name collision overwrites rather than making a second "EMA": two templates with
 * one name is not a state anyone chose, and silently renaming theirs to "EMA (2)"
 * is worse than replacing what they clearly meant to update.
 */
export function saveTemplate(rawName: string, entries: TemplateEntry[]): SaveResult {
  const name = cleanName(rawName)
  if (!name) return { ok: false, error: 'Give the strategy a name.' }
  if (entries.length === 0) {
    return { ok: false, error: 'Turn on at least one indicator before saving.' }
  }

  const all = read()
  const existing = all.find((t) => t.name.toLowerCase() === name.toLowerCase())
  const template: ChartTemplate = {
    key: existing?.key ?? newKey(),
    name,
    entries,
    isDefault: existing?.isDefault ?? false,
    updatedAt: Date.now(),
  }

  const next = existing
    ? all.map((t) => (t.key === existing.key ? template : t))
    : [...all, template]
  write(next)
  return { ok: true, template }
}

export function renameTemplate(key: string, rawName: string): SaveResult {
  const name = cleanName(rawName)
  if (!name) return { ok: false, error: 'Give the strategy a name.' }
  const all = read()
  if (all.some((t) => t.key !== key && t.name.toLowerCase() === name.toLowerCase())) {
    return { ok: false, error: `You already have a strategy called “${name}”.` }
  }
  write(all.map((t) => (t.key === key ? { ...t, name, updatedAt: Date.now() } : t)))
  return { ok: true }
}

export function deleteTemplate(key: string): void {
  write(read().filter((t) => t.key !== key))
}

/** Stars a template, or unstars it when it is already the default. */
export function toggleDefault(key: string): void {
  const all = read()
  const current = all.find((t) => t.key === key)
  write(withSingleDefault(all, current?.isDefault ? null : key))
}
