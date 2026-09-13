import React from 'react'
import { SUPPORT_EMAIL } from '../lib/legal'

/**
 * A short standalone notice, styled like the legal pages.
 *
 * Used for routes that are now obsolete but must not 404: the Play Console
 * pre-registration terms URL, the refund policy, and the old top-up page. A
 * dead link on a store listing is worse than a page that explains itself.
 */
export const NoticePage: React.FC<{
  title: string
  lead: string
  points?: string[]
  children?: React.ReactNode
}> = ({ title, lead, points, children }) => (
  <div className="min-h-screen bg-[#EDEEF5] py-20 px-6 md:px-12 font-sans selection:bg-[#9fff00] selection:text-black">
    <div className="max-w-3xl mx-auto bg-white border border-[#D0D4DF] rounded-2xl p-8 md:p-12 shadow-lg mt-10">
      <div className="border-b border-[#EDEEF5] pb-6 mb-8">
        <a
          href="/"
          className="text-sm font-bold text-[#2563eb] uppercase tracking-wider hover:underline"
        >
          Trading Titans
        </a>
        <h1 className="text-3xl md:text-4xl font-extrabold text-[#0f172a] tracking-tight mt-2">
          {title}
        </h1>
      </div>

      <div className="space-y-6 text-[#525E75] text-sm leading-relaxed">
        <div className="bg-[#F0FDF4] border-l-4 border-emerald-500 p-6 rounded-r-xl">
          <p className="text-emerald-800 font-semibold">{lead}</p>
        </div>

        {points && (
          <ul className="list-disc pl-5 space-y-2">
            {points.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
        )}

        {children}

        <div className="pt-6 border-t border-[#EDEEF5] flex flex-wrap gap-4">
          <a
            href="/terms"
            className="text-[#2563eb] hover:underline text-xs font-semibold"
          >
            Terms &amp; Conditions
          </a>
          <a
            href="/privacy"
            className="text-[#2563eb] hover:underline text-xs font-semibold"
          >
            Privacy Policy
          </a>
          <a
            href={`mailto:${SUPPORT_EMAIL}`}
            className="text-[#2563eb] hover:underline text-xs font-semibold"
          >
            {SUPPORT_EMAIL}
          </a>
        </div>
      </div>
    </div>
  </div>
)
