import { motion } from 'motion/react'
import type { ReactNode } from 'react'
import {
  ArrowDown,
  ArrowRight,
  Bell,
  BellRing,
  Building2,
  Check,
  Coins,
  FileText,
  Fingerprint,
  Flame,
  Hammer,
  KeyRound,
  LineChart,
  ListChecks,
  Mail,
  Microscope,
  Play,
  ShieldCheck,
  Target,
  Trophy,
  Users,
  Wallet,
  type LucideIcon,
} from 'lucide-react'

/**
 * Only the icons actually used, listed explicitly.
 *
 * `import * as Icons from 'lucide-react'` defeats tree-shaking and pulled the
 * whole icon set in: the bundle was 975 kB (266 kB gzipped) for a static
 * landing page. Naming them keeps it to what is rendered. Adding an icon to
 * content.ts means adding it here too — the console warns if it is missing.
 */
const ICONS: Record<string, LucideIcon> = {
  ArrowDown,
  ArrowRight,
  Bell,
  BellRing,
  Building2,
  Check,
  Coins,
  FileText,
  Fingerprint,
  Flame,
  Hammer,
  KeyRound,
  LineChart,
  ListChecks,
  Mail,
  Microscope,
  Play,
  ShieldCheck,
  Target,
  Trophy,
  Users,
  Wallet,
}

/** Per-product accent, so a section can be tinted without prop-drilling colours. */
export type Accent = 'gold' | 'teal'

export const ACCENT: Record<Accent, { hex: string; text: string; border: string; bg: string }> = {
  gold: {
    hex: '#e3b341',
    text: 'text-[#e3b341]',
    border: 'border-[#e3b341]/25',
    bg: 'bg-[#e3b341]/6',
  },
  teal: {
    hex: '#2dd4bf',
    text: 'text-[#2dd4bf]',
    border: 'border-[#2dd4bf]/25',
    bg: 'bg-[#2dd4bf]/6',
  },
}

/** Looks an icon up by name so content.ts can stay plain data. */
export function Icon({
  name,
  className = 'h-5 w-5',
}: {
  name: string
  className?: string
}) {
  const Cmp = ICONS[name]
  if (!Cmp) {
    // Loud in dev, silent in production: a missing icon is a content/UI mismatch,
    // not something a visitor should see a broken box for.
    if (import.meta.env.DEV) console.warn(`Icon "${name}" is not in ICONS`)
    return null
  }
  return <Cmp className={className} strokeWidth={1.6} aria-hidden="true" />
}

/** Fades a block in once as it enters the viewport. */
export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode
  delay?: number
  className?: string
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 22 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{ duration: 0.6, delay, ease: [0.16, 1, 0.3, 1] }}
    >
      {children}
    </motion.div>
  )
}

export function Section({
  id,
  children,
  className = '',
}: {
  id?: string
  children: ReactNode
  className?: string
}) {
  return (
    <section id={id} className={`px-6 py-24 md:px-10 md:py-32 ${className}`}>
      <div className="mx-auto max-w-6xl">{children}</div>
    </section>
  )
}

export function Eyebrow({
  children,
  accent = 'gold',
}: {
  children: ReactNode
  accent?: Accent
}) {
  const a = ACCENT[accent]
  return (
    <div className="mb-4 flex items-center gap-2">
      <span className="h-px w-8" style={{ background: a.hex }} />
      <span
        className="text-[11px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: a.hex }}
      >
        {children}
      </span>
    </div>
  )
}

export function Heading({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <h2
      className={`font-display text-3xl font-extrabold leading-[1.1] tracking-tight text-white md:text-5xl ${className}`}
    >
      {children}
    </h2>
  )
}

export function Card({
  children,
  className = '',
  accent = 'gold',
}: {
  children: ReactNode
  className?: string
  accent?: Accent
}) {
  return (
    <div
      className={`group relative rounded-2xl border border-[#1b2427] bg-[#0b1012] p-6 transition-colors duration-300 ${
        accent === 'gold' ? 'hover:border-[#e3b341]/40' : 'hover:border-[#2dd4bf]/40'
      } ${className}`}
    >
      {children}
    </div>
  )
}

export function Chip({
  children,
  accent = 'gold',
}: {
  children: ReactNode
  accent?: Accent
}) {
  const a = ACCENT[accent]
  return (
    <span
      className={`rounded-full border ${a.border} ${a.bg} px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider`}
      style={{ color: a.hex }}
    >
      {children}
    </span>
  )
}
