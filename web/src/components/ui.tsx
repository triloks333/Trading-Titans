import { cva, type VariantProps } from 'class-variance-authority'
import type { ReactNode, ButtonHTMLAttributes, InputHTMLAttributes } from 'react'
import { cn } from '@/lib/format'

/*
 * Primitives in the shadcn/ui idiom — class-variance-authority for variants,
 * tailwind-merge for override-safe class composition. Kept local rather than
 * pulled from the registry so the palette in index.css (ported from the Flutter
 * theme) is the single source of colour truth; shadcn components can be added
 * alongside these later without rework because the conventions match.
 */

// ── Button ───────────────────────────────────────────────────────────────────
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-md font-semibold transition-colors ' +
    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 ' +
    'disabled:pointer-events-none disabled:opacity-50 whitespace-nowrap',
  {
    variants: {
      variant: {
        primary: 'bg-brand text-white hover:bg-brand-deep',
        dark: 'bg-ink text-white hover:opacity-90',
        outline: 'border border-birch bg-pure-white text-ink hover:bg-cream',
        ghost: 'text-ink-3 hover:bg-cream hover:text-ink',
        bull: 'bg-bull text-white hover:opacity-90',
        bear: 'bg-bear text-white hover:opacity-90',
      },
      size: {
        sm: 'h-8 px-3 text-xs',
        md: 'h-10 px-4 text-sm',
        lg: 'h-12 px-6 text-sm',
      },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
)

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export function Button({ className, variant, size, ...props }: ButtonProps) {
  return <button className={cn(buttonVariants({ variant, size }), className)} {...props} />
}

// ── Card ─────────────────────────────────────────────────────────────────────
export function Card({
  className,
  children,
}: {
  className?: string
  children: ReactNode
}) {
  return (
    <div
      className={cn(
        'rounded-xl border border-birch bg-pure-white',
        className,
      )}
    >
      {children}
    </div>
  )
}

export function CardHeader({
  title,
  subtitle,
  action,
}: {
  title: string
  subtitle?: string
  action?: ReactNode
}) {
  return (
    // flex-wrap so an action drops onto its own line rather than crushing the
    // title. The monthly/annual toggle on /plans is the case that forced this:
    // beside a title on a 390px phone it squeezed both into unreadable columns.
    <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-3 border-b border-birch px-4 py-4 sm:px-5">
      <div className="min-w-0 flex-1">
        <h2 className="text-sm font-bold text-ink">{title}</h2>
        {subtitle && <p className="mt-0.5 text-xs text-ink-4">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

// ── Input ────────────────────────────────────────────────────────────────────
export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        'h-11 w-full rounded-md border border-birch bg-cream px-3 text-sm text-ink',
        'placeholder:text-ink-5 focus:border-brand focus:outline-none focus:ring-1 focus:ring-brand',
        className,
      )}
      {...props}
    />
  )
}

export function Label({ children }: { children: ReactNode }) {
  return <label className="mb-1.5 block text-xs font-medium text-ink-3">{children}</label>
}

// ── Badge ────────────────────────────────────────────────────────────────────
const badgeVariants = cva(
  'inline-flex items-center rounded-tag px-2 py-0.5 text-[11px] font-bold tracking-wide',
  {
    variants: {
      tone: {
        neutral: 'bg-cream text-ink-4',
        brand: 'bg-brand-pale text-brand-deep',
        bull: 'bg-bull-light text-bull',
        bear: 'bg-bear-light text-bear',
        violet: 'bg-violet-light text-violet',
      },
    },
    defaultVariants: { tone: 'neutral' },
  },
)

export function Badge({
  tone,
  children,
  className,
}: VariantProps<typeof badgeVariants> & { children: ReactNode; className?: string }) {
  return <span className={cn(badgeVariants({ tone }), className)}>{children}</span>
}

// ── Plan badge ───────────────────────────────────────────────────────────────
/**
 * The plan marker shown beside a name, on a profile and on the leaderboard.
 *
 * Renders nothing for the free tier. Every account used to carry an identical
 * FREE_STARTER tag, which told a reader precisely nothing; a badge is only worth
 * the space when it distinguishes.
 */
export function TierBadge({
  tier,
  className,
}: {
  tier: 'free' | 'pro' | 'titan' | null | undefined
  className?: string
}) {
  if (tier !== 'pro' && tier !== 'titan') return null
  return (
    <Badge tone={tier === 'titan' ? 'violet' : 'brand'} className={className}>
      {tier === 'titan' ? 'TITAN' : 'PRO'}
    </Badge>
  )
}

// ── Value with direction colouring ───────────────────────────────────────────
export function Delta({
  value,
  children,
  className,
}: {
  value: number
  children: ReactNode
  className?: string
}) {
  return (
    <span className={cn('tnum font-semibold', value >= 0 ? 'text-bull' : 'text-bear', className)}>
      {children}
    </span>
  )
}

// ── Skeleton + empty state ───────────────────────────────────────────────────
export function Skeleton({ className }: { className?: string }) {
  return <div className={cn('animate-pulse rounded-md bg-cream', className)} />
}

export function EmptyState({
  icon,
  title,
  message,
  action,
}: {
  icon: ReactNode
  title: string
  message: string
  action?: ReactNode
}) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-cream text-ink-4">
        {icon}
      </div>
      <h3 className="text-sm font-bold text-ink">{title}</h3>
      <p className="mt-1 max-w-sm text-xs leading-relaxed text-ink-4">{message}</p>
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}
