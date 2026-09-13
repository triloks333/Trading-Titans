import { INDICATORS, defaultParams, type IndicatorSpec } from '../core/registry'
import { periodsFor } from '../core/periods'
import {
  deleteTemplate,
  listTemplates,
  saveTemplate,
  toggleDefault,
} from '../data/templates'
import type { TemplateEntry } from '../core/templates'
import type { Market } from '../core/types'

/*
 * The chart's own controls, built for a thumb.
 *
 * WHY THESE ARE NOT FLUTTER WIDGETS
 * The obvious alternative was a Dart period selector and a Dart indicator sheet.
 * That would mean the catalogue existing twice — nineteen indicators, their groups,
 * their parameter names and ranges — in TypeScript and again in Dart, kept in step
 * by hand. This codebase has already paid for that mistake: the price list lived in
 * Dart, TS and SQL, and the two copies that were not the database were wrong. One
 * catalogue, one picker.
 *
 * So Flutter hosts the WebView and passes the symbol; everything a user touches on
 * the chart is rendered here from the same registry the web app reads.
 *
 * Sizes below are deliberate: 44px minimum hit targets, 16px type in inputs so iOS
 * does not zoom on focus, and a sheet that scrolls rather than a menu that runs off
 * the bottom of a phone.
 */

export interface ControlsHost {
  /** Current market, so the period list matches what the provider will serve. */
  market(): Market
  onPeriod(id: string): void
  onIndicators(entries: TemplateEntry[]): void
  onStyle(style: 'candles' | 'line'): void
  currentPeriod(): string
}

const active = new Map<string, Record<string, number>>()

export function activeEntries(): TemplateEntry[] {
  const out: TemplateEntry[] = []
  for (const spec of INDICATORS) {
    const params = active.get(spec.id)
    if (params) out.push({ id: spec.id, params: { ...params } })
  }
  return out
}

export function setActiveEntries(entries: TemplateEntry[]): void {
  active.clear()
  for (const e of entries) active.set(e.id, { ...e.params })
}

export function mountControls(root: HTMLElement, host: ControlsHost): { refresh(): void } {
  root.innerHTML = `
    <div class="tt-bar">
      <div class="tt-periods" id="ttPeriods"></div>
      <button class="tt-btn" id="ttStyle" aria-label="Chart style">Line</button>
      <button class="tt-btn" id="ttInd" aria-label="Indicators">
        <span>Indicators</span><span class="tt-badge" id="ttIndCount"></span>
      </button>
    </div>
    <div class="tt-sheet" id="ttSheet" hidden>
      <div class="tt-sheet-head">
        <b>Indicators</b>
        <button class="tt-btn tt-ghost" id="ttClose" aria-label="Close">Done</button>
      </div>
      <div class="tt-sheet-body">
        <div class="tt-strategies">
          <div class="tt-save">
            <input id="ttName" placeholder="Name this strategy" maxlength="40" />
            <button class="tt-btn" id="ttSave">Save</button>
          </div>
          <div class="tt-msg" id="ttMsg"></div>
          <div id="ttTemplates"></div>
        </div>
        <div id="ttPicker"></div>
      </div>
    </div>
  `

  const $ = <T extends HTMLElement>(id: string) => root.querySelector<T>(`#${id}`)!
  const sheet = $<HTMLDivElement>('ttSheet')
  const msg = $<HTMLDivElement>('ttMsg')
  const nameBox = $<HTMLInputElement>('ttName')
  let style: 'candles' | 'line' = 'candles'

  function say(text: string, ok: boolean) {
    msg.textContent = text
    msg.className = `tt-msg ${ok ? 'ok' : 'bad'}`
  }

  function renderPeriods() {
    const box = $<HTMLDivElement>('ttPeriods')
    box.innerHTML = ''
    for (const p of periodsFor(host.market())) {
      const b = document.createElement('button')
      b.className = `tt-chip${p.id === host.currentPeriod() ? ' on' : ''}`
      b.textContent = p.label
      b.onclick = () => {
        host.onPeriod(p.id)
        renderPeriods()
      }
      box.append(b)
    }
  }

  function renderCount() {
    const badge = $<HTMLSpanElement>('ttIndCount')
    badge.textContent = active.size ? String(active.size) : ''
    $<HTMLButtonElement>('ttInd').classList.toggle('on', active.size > 0)
  }

  function pushIndicators() {
    renderCount()
    host.onIndicators(activeEntries())
  }

  function renderPicker() {
    const box = $<HTMLDivElement>('ttPicker')
    const groups = new Map<string, IndicatorSpec[]>()
    for (const spec of INDICATORS) {
      const list = groups.get(spec.group) ?? []
      list.push(spec)
      groups.set(spec.group, list)
    }

    box.innerHTML = ''
    for (const [group, specs] of groups) {
      const h = document.createElement('h4')
      h.textContent = group
      box.append(h)
      for (const spec of specs) {
        const params = active.get(spec.id)
        const row = document.createElement('div')
        row.className = 'tt-row'

        const label = document.createElement('label')
        const cb = document.createElement('input')
        cb.type = 'checkbox'
        cb.checked = !!params
        cb.onchange = () => {
          if (cb.checked) active.set(spec.id, defaultParams(spec))
          else active.delete(spec.id)
          renderPicker()
          pushIndicators()
        }
        const text = document.createElement('span')
        text.textContent = spec.name
        label.append(cb, text)
        row.append(label)

        // Parameter boxes only for what is on: nineteen indicators' worth of
        // inputs at once is a wall nobody scrolls through on a phone.
        if (params) {
          const ps = document.createElement('span')
          ps.className = 'tt-params'
          for (const p of spec.params) {
            const input = document.createElement('input')
            input.type = 'number'
            input.inputMode = 'decimal'
            input.value = String(params[p.key] ?? p.default)
            input.min = String(p.min)
            input.max = String(p.max)
            input.step = p.kind === 'multiplier' ? '0.1' : '1'
            input.title = p.label
            input.onchange = () => {
              const raw = Number(input.value)
              const v = Number.isFinite(raw) ? Math.min(p.max, Math.max(p.min, raw)) : p.default
              input.value = String(v)
              active.set(spec.id, { ...params, [p.key]: v })
              pushIndicators()
            }
            ps.append(input)
          }
          row.append(ps)
        }
        box.append(row)
      }
    }
  }

  function renderTemplates() {
    const box = $<HTMLDivElement>('ttTemplates')
    const templates = listTemplates()
    box.innerHTML = ''
    if (templates.length === 0) {
      const p = document.createElement('p')
      p.className = 'tt-empty'
      p.textContent = 'Turn on some indicators, name the set, and save it.'
      box.append(p)
      return
    }
    for (const t of templates) {
      const row = document.createElement('div')
      row.className = 'tt-tpl'

      const apply = document.createElement('button')
      apply.className = 'tt-tpl-name'
      apply.textContent = t.name
      apply.onclick = () => {
        setActiveEntries(t.entries)
        nameBox.value = t.name
        say(`Applied “${t.name}”.`, true)
        renderPicker()
        pushIndicators()
      }

      const count = document.createElement('span')
      count.className = 'tt-count'
      count.textContent = String(t.entries.length)

      const star = document.createElement('button')
      star.className = `tt-icon${t.isDefault ? ' on' : ''}`
      star.textContent = t.isDefault ? '★' : '☆'
      star.setAttribute('aria-label', t.isDefault ? 'Default strategy' : 'Make default')
      star.onclick = () => {
        toggleDefault(t.key)
        renderTemplates()
      }

      const del = document.createElement('button')
      del.className = 'tt-icon'
      del.textContent = '✕'
      del.setAttribute('aria-label', `Delete ${t.name}`)
      del.onclick = () => {
        // Confirmed: no undo, and the row is one tap from Apply.
        if (!confirm(`Delete “${t.name}”?`)) return
        deleteTemplate(t.key)
        renderTemplates()
      }

      row.append(apply, count, star, del)
      box.append(row)
    }
  }

  $<HTMLButtonElement>('ttInd').onclick = () => {
    sheet.hidden = !sheet.hidden
  }
  $<HTMLButtonElement>('ttClose').onclick = () => {
    sheet.hidden = true
  }
  $<HTMLButtonElement>('ttStyle').onclick = () => {
    style = style === 'candles' ? 'line' : 'candles'
    $<HTMLButtonElement>('ttStyle').textContent = style === 'candles' ? 'Line' : 'Candles'
    host.onStyle(style)
  }
  $<HTMLButtonElement>('ttSave').onclick = () => {
    const res = saveTemplate(nameBox.value, activeEntries())
    if (!res.ok) {
      say(res.error ?? 'Could not save that.', false)
      return
    }
    say(`Saved “${res.template!.name}”.`, true)
    renderTemplates()
  }
  nameBox.onkeydown = (e) => {
    if (e.key === 'Enter') $<HTMLButtonElement>('ttSave').click()
  }

  renderPeriods()
  renderPicker()
  renderTemplates()
  renderCount()

  return {
    refresh() {
      renderPeriods()
      renderPicker()
      renderCount()
    },
  }
}
