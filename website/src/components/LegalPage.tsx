import React from 'react'
import { SUPPORT_EMAIL, type LegalDoc } from '../lib/legal'

/** Bolds a short leading `Label:` so bullets read the way the app renders them. */
const Bullet: React.FC<{ text: string }> = ({ text }) => {
  const colon = text.indexOf(':')
  const hasLabel = colon > 0 && colon <= 30
  return (
    <li>
      {hasLabel ? (
        <>
          <strong className="text-[#0f172a]">{text.slice(0, colon + 1)}</strong>
          {text.slice(colon + 1)}
        </>
      ) : (
        text
      )}
    </li>
  )
}

/**
 * Renders a policy from `src/lib/legal.ts`.
 *
 * One renderer for Terms and Privacy: the two pages previously duplicated the
 * same card/heading markup and each carried its own hand-written copy, which is
 * how the website drifted away from the app in the first place.
 */
export const LegalPage: React.FC<{ doc: LegalDoc }> = ({ doc }) => {
  return (
    <div className="min-h-screen bg-[#EDEEF5] py-20 px-6 md:px-12 font-sans selection:bg-[#9fff00] selection:text-black">
      <div className="max-w-4xl mx-auto bg-white border border-[#D0D4DF] rounded-2xl p-8 md:p-12 shadow-lg mt-10">
        <div className="border-b border-[#EDEEF5] pb-6 mb-8 text-center md:text-left">
          <a
            href="/"
            className="text-sm font-bold text-[#2563eb] uppercase tracking-wider hover:underline"
          >
            Trading Titans
          </a>
          <h1 className="text-3xl md:text-4xl font-extrabold text-[#0f172a] tracking-tight mt-2">
            {doc.title}
          </h1>
          <p className="text-zinc-500 text-xs mt-3">Last Updated: {doc.lastUpdated}</p>
        </div>

        <div className="space-y-8 text-[#525E75] text-sm leading-relaxed">
          {doc.notice && (
            <div className="bg-[#FFF5F5] border-l-4 border-red-500 p-6 rounded-r-xl">
              <h3 className="font-bold text-red-800 text-base mb-2">
                {doc.noticeTitle ?? 'IMPORTANT'}
              </h3>
              {doc.notice.split('\n\n').map((p, i) => (
                <p key={i} className={i === 0 ? 'text-red-700 font-semibold' : 'text-red-700 mt-2'}>
                  {p}
                </p>
              ))}
            </div>
          )}

          <p>{doc.intro}</p>

          {doc.sections.map((s) => (
            <section key={s.heading}>
              <h2 className="text-lg font-bold text-[#0f172a] mb-3">{s.heading}</h2>
              {s.paragraphs?.map((p, i) => (
                <p key={i} className={i > 0 ? 'mt-2' : undefined}>
                  {p}
                </p>
              ))}
              {s.bullets && s.bullets.length > 0 && (
                <ul className="list-disc pl-5 mt-2 space-y-2">
                  {s.bullets.map((b) => (
                    <Bullet key={b} text={b} />
                  ))}
                </ul>
              )}
            </section>
          ))}

          <div className="pt-6 border-t border-[#EDEEF5] flex flex-wrap gap-3 justify-between items-center text-xs text-[#7888A3]">
            <span>Trading Titans Support</span>
            <a href={`mailto:${SUPPORT_EMAIL}`} className="text-[#2563eb] hover:underline">
              {SUPPORT_EMAIL}
            </a>
          </div>
        </div>
      </div>
    </div>
  )
}
