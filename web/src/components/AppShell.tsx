import { NavLink, Outlet } from 'react-router-dom'
import {
  LayoutDashboard,
  ArrowLeftRight,
  Briefcase,
  Wallet,
  Trophy,
  Stethoscope,
  Bell,
  LogOut,
  TrendingUp,
  Lock,
  Sparkles,
} from 'lucide-react'
import { cn, money } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { useMyTier } from '@/lib/tier'
import { useMonetisationEnabled } from '@/lib/payments'
import { Badge, Button, TierBadge } from '@/components/ui'

const NAV = [
  { to: '/', label: 'Dashboard', short: 'Home', icon: LayoutDashboard },
  { to: '/trade', label: 'Trade', short: 'Trade', icon: ArrowLeftRight },
  { to: '/portfolio', label: 'Portfolio', short: 'Folio', icon: Briefcase },
  { to: '/wallet', label: 'Wallet', short: 'Wallet', icon: Wallet },
  { to: '/leaderboard', label: 'Leaderboard', short: 'League', icon: Trophy },
  { to: '/autopsy', label: 'Trade Autopsy', short: 'Autopsy', icon: Stethoscope },
]

const PLANS_NAV = { to: '/plans', label: 'Plans', short: 'Plans', icon: Sparkles }

/**
 * The application chrome: a sidebar on a desktop, a top bar plus a bottom tab bar
 * on a phone, with routed content between them.
 *
 * This used to be desktop-only, and the comment here used to boast that "the
 * sidebar never collapses into a bottom tab bar". That was a bug dressed as a
 * decision. The sidebar was `w-[240px] shrink-0` with no breakpoint, so on a 390px
 * phone the content column got 150px, and after `main`'s padding about 94px of
 * usable width — every page in the app was crushed into a sliver. It mattered most
 * on /plans, because the Android app hands checkout off to that page *in the phone
 * browser*, so the one screen guaranteed to be viewed on a small display was the
 * one being squeezed hardest.
 *
 * The pages themselves were always fine: every grid carries `sm:` prefixes and
 * every table is wrapped in `overflow-x-auto`. Only the shell needed fixing.
 */
export function AppShell() {
  const { session, profile, isGuest, signOut } = useAuth()
  const tier = useMyTier(session?.user?.id)
  const { data: monetisation } = useMonetisationEnabled()

  // Plans only appears once monetisation is switched on in app_flags, so the paid
  // surface stays invisible until it is meant to exist. The page itself re-checks
  // the flag; this only keeps it out of the way.
  const items = monetisation ? [...NAV, PLANS_NAV] : NAV

  return (
    <div className="flex min-h-screen bg-parchment">
      {/* Desktop sidebar. Hidden below lg, where the bottom bar takes over. */}
      <aside className="sticky top-0 hidden h-screen w-[240px] shrink-0 flex-col border-r border-birch bg-pure-white lg:flex">
        <div className="flex items-center gap-2.5 px-5 py-5">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand text-white">
            <TrendingUp className="h-4.5 w-4.5" />
          </div>
          <span className="text-sm font-extrabold text-ink">Trading Titans</span>
        </div>

        <nav className="flex-1 space-y-0.5 px-2">
          {items.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 rounded-md px-3 py-2.5 text-[13px] transition-colors',
                  isActive
                    ? 'bg-brand-pale font-bold text-ink'
                    : 'font-medium text-ink-3 hover:bg-cream hover:text-ink',
                )
              }
            >
              {({ isActive }) => (
                <>
                  <Icon
                    className={cn('h-4.5 w-4.5', isActive ? 'text-brand' : 'text-ink-4')}
                  />
                  {label}
                </>
              )}
            </NavLink>
          ))}
        </nav>

        {isGuest && (
          <div className="mx-3 mb-3 rounded-lg border border-brand-border bg-brand-pale p-3">
            <p className="text-xs font-bold text-ink">You are missing ₹6,000</p>
            <p className="mt-1 text-[11px] leading-relaxed text-ink-3">
              Guest accounts start with ₹5,000 and cannot be recovered if you sign
              out.
            </p>
            <NavLink to="/upgrade">
              <Button size="sm" variant="dark" className="mt-2.5 w-full">
                <Lock className="h-3 w-3" />
                Make it permanent
              </Button>
            </NavLink>
          </div>
        )}

        <div className="border-t border-birch px-5 py-4">
          <p className="truncate text-[13px] font-bold text-ink">
            {profile?.name ?? 'Titan'}
          </p>
          <p className="truncate text-[11px] text-ink-4">
            {isGuest ? 'Guest account' : (profile?.email ?? '')}
          </p>
          <p className="tnum mt-2 text-[17px] font-extrabold text-ink">
            {money(profile?.wallet_balance)}
          </p>
          <p className="text-[10px] text-ink-4">Demo cash</p>
          <button
            onClick={() => void signOut()}
            className="mt-3 flex items-center gap-1.5 text-[11px] font-semibold text-ink-4 hover:text-bear"
          >
            <LogOut className="h-3 w-3" />
            Sign out
          </button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-14 items-center justify-between gap-2 border-b border-birch bg-parchment/85 px-4 backdrop-blur sm:px-6 lg:px-7">
          <div className="flex min-w-0 items-center gap-2">
            {/* The logo lives in the sidebar on a desktop; on a phone the sidebar
                is gone, so the app needs to say its name somewhere. */}
            <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-brand text-white lg:hidden">
              <TrendingUp className="h-4 w-4" />
            </div>
            <span className="hidden text-xs text-ink-4 lg:inline">Welcome back,</span>
            <span className="truncate text-sm font-bold text-ink">
              {profile?.name ?? 'Titan'}
            </span>
            {isGuest && <Badge tone="brand">GUEST</Badge>}
            {/* The plan badge comes from `user_tiers` (derived from an actual
                Razorpay subscription), not from `profiles.subscription_active`,
                which is a legacy column no payment path writes. Reading that
                column would badge people according to whatever it was last left
                at. */}
            {!isGuest && <TierBadge tier={tier} />}
          </div>
          <div className="flex shrink-0 items-center gap-2 sm:gap-4">
            <div className="text-right">
              <p className="hidden text-[10px] uppercase tracking-wide text-ink-4 sm:block">
                Wallet
              </p>
              <p className="tnum text-sm font-bold text-ink">
                {money(profile?.wallet_balance)}
              </p>
            </div>
            <NavLink
              to="/notifications"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-birch bg-pure-white text-ink-3 hover:text-ink"
            >
              <Bell className="h-4 w-4" />
            </NavLink>
            {/* Sign out lived only in the sidebar footer, so on a phone there was
                no way to sign out at all. */}
            <button
              onClick={() => void signOut()}
              aria-label="Sign out"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-birch bg-pure-white text-ink-4 hover:text-bear lg:hidden"
            >
              <LogOut className="h-4 w-4" />
            </button>
          </div>
        </header>

        {/* Same guest nudge as the sidebar's, for the phone where the sidebar is
            hidden. Losing it would let a guest spend money on an account that
            cannot be recovered. */}
        {isGuest && (
          <NavLink
            to="/upgrade"
            className="flex items-center gap-2 border-b border-brand-border bg-brand-pale px-4 py-2.5 lg:hidden"
          >
            <Lock className="h-3.5 w-3.5 shrink-0 text-brand-deep" />
            <span className="min-w-0 flex-1 text-[12px] font-semibold text-ink">
              Make your account permanent — you are missing ₹6,000
            </span>
          </NavLink>
        )}

        {/* pb-24 clears the fixed bottom bar, so the last row of a table or the
            final button on /plans is not sitting underneath it. */}
        <main className="min-w-0 flex-1 px-4 py-5 pb-24 sm:px-6 lg:px-7 lg:py-6 lg:pb-6">
          <Outlet />
        </main>
      </div>

      {/* Mobile tab bar. Scrolls horizontally rather than shrinking: seven
          destinations cannot fit legibly across a 390px screen, and squeezing them
          is what made the Flutter navbar unreadable before it was rebuilt. */}
      <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-birch bg-pure-white/95 backdrop-blur lg:hidden">
        <div className="flex overflow-x-auto">
          {items.map(({ to, short, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                cn(
                  'flex min-w-[68px] flex-1 flex-col items-center gap-1 px-1 py-2.5 text-[10px] transition-colors',
                  isActive ? 'font-bold text-brand' : 'font-medium text-ink-4',
                )
              }
            >
              {({ isActive }) => (
                <>
                  <Icon className={cn('h-5 w-5', isActive ? 'text-brand' : 'text-ink-4')} />
                  <span>{short}</span>
                </>
              )}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
