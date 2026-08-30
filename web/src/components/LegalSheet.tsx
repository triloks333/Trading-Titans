import { useEffect } from 'react'
import { X } from 'lucide-react'
import type { LegalDoc } from '@/lib/legal'
import { cn } from '@/lib/format'

/**
 * Modal reader for a policy document.
 *
 * Opens in place rather than navigating away, which matters on the auth screen:
 * sending someone to another page to read the terms would discard whatever they
 * had typed into the form, and they would have to start again just for having
 * checked what they were agreeing to.
 */
export function LegalSheet({
  doc,
  onClose,
}: {
  doc: LegalDoc | null
  onClose: () => void
}) {
  // Escape closes, and the body must not scroll behind the sheet.
  useEffect(() => {
    if (!doc) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKey)
    const previous = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = previous
    }
  }, [doc, onClose])

  if (!doc) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-ink/50 p-4"
      // Clicking the backdrop closes; clicking the panel must not, hence the
      // stopPropagation below.
      onClick={onClose}
      role="presentation"
    >
      <div
        className="flex max-h-[85vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl bg-pure-white"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={doc.title}
      >
        <header className="flex items-start justify-between gap-4 border-b border-birch px-6 py-4">
          <div>
            <h2 className="text-base font-extrabold text-ink">{doc.title}</h2>
            <p className="mt-0.5 text-[11px] text-ink-4">
              Last updated {doc.lastUpdated}
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="rounded-md p-1.5 text-ink-4 transition-colors hover:bg-cream hover:text-ink"
          >
            <X className="h-4 w-4" />
          </button>
        </header>

        <div className="min-h-0 flex-1 overflow-y-auto px-6 py-5">
          {doc.notice && (
            <div className="mb-5 rounded-md border border-brand-mid/40 bg-brand-pale px-4 py-3">
              {doc.noticeTitle && (
                <p className="text-[11px] font-extrabold tracking-wide text-brand-deep">
                  {doc.noticeTitle}
                </p>
              )}
              {doc.notice.split('\n\n').map((p, i) => (
                <p key={i} className={cn('text-xs leading-relaxed text-ink-3', i === 0 ? 'mt-1.5' : 'mt-2')}>
                  {p}
                </p>
              ))}
            </div>
          )}

          <p className="text-xs leading-relaxed text-ink-3">{doc.intro}</p>

          <ol className="mt-5 space-y-5">
            {doc.sections.map((s, i) => (
              <li key={s.heading}>
                <h3 className="text-[13px] font-bold text-ink">
                  {i + 1}. {s.heading}
                </h3>
                {s.paragraphs?.map((p, j) => (
                  <p key={j} className="mt-1.5 text-xs leading-relaxed text-ink-3">
                    {p}
                  </p>
                ))}
                {s.bullets && s.bullets.length > 0 && (
                  <ul className="mt-2 space-y-1.5">
                    {s.bullets.map((b) => {
                      // A short leading "Label:" is emphasised, matching how the
                      // Dart renderer treats these.
                      const idx = b.indexOf(':')
                      const hasLabel = idx > 0 && idx < 30
                      return (
                        <li
                          key={b}
                          className="flex gap-2 text-xs leading-relaxed text-ink-3"
                        >
                          <span aria-hidden="true" className="text-ink-5">
                            •
                          </span>
                          <span>
                            {hasLabel ? (
                              <>
                                <strong className="font-semibold text-ink">
                                  {b.slice(0, idx + 1)}
                                </strong>
                                {b.slice(idx + 1)}
                              </>
                            ) : (
                              b
                            )}
                          </span>
                        </li>
                      )
                    })}
                  </ul>
                )}
              </li>
            ))}
          </ol>
        </div>
      </div>
    </div>
  )
}
