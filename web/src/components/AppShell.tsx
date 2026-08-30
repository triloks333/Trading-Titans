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
} from 'lucide-react'
import { cn, money } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { Badge, Button } from '@/components/ui'

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/trade', label: 'Trade', icon: ArrowLeftRight },
  { to: '/portfolio', label: 'Portfolio', icon: Briefcase },
  { to: '/wallet', label: 'Wallet', icon: Wallet },
  { to: '/leaderboard', label: 'Leaderboard', icon: Trophy },
  { to: '/autopsy', label: 'Trade Autopsy', icon: Stethoscope },
]

/**
 * The application chrome: a persistent sidebar and a top bar, with routed
 * content between them.
 *
 * Unlike the Flutter build this is a genuine web layout — the sidebar never
 * collapses into a bottom tab bar, the content area is a real grid rather than a
 * single phone-width column, and navigating a detail page keeps the sidebar in
 * place because only the <Outlet /> swaps.
 */
export function AppShell() {
  const { profile, isGuest, signOut } = useAuth()

  return (
    <div className="flex min-h-screen bg-parchment">
      <aside className="sticky top-0 flex h-screen w-[240px] shrink-0 flex-col border-r border-birch bg-pure-white">
        <div className="flex items-center gap-2.5 px-5 py-5">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand text-white">
            <TrendingUp className="h-4.5 w-4.5" />
          </div>
          <span className="text-sm font-extrabold text-ink">Trading Titans</span>
        </div>

        <nav className="flex-1 space-y-0.5 px-2">
          {NAV.map(({ to, label, icon: Icon }) => (
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
        <header className="sticky top-0 z-10 flex h-14 items-center justify-between gap-4 border-b border-birch bg-parchment/85 px-7 backdrop-blur">
          <div className="flex items-baseline gap-3">
            <span className="text-xs text-ink-4">Welcome back,</span>
            <span className="text-sm font-bold text-ink">{profile?.name ?? 'Titan'}</span>
            {isGuest && <Badge tone="brand">GUEST</Badge>}
            {profile?.subscription_active && !isGuest && <Badge tone="bull">ACTIVE</Badge>}
          </div>
          <div className="flex items-center gap-4">
            <div className="text-right">
              <p className="text-[10px] uppercase tracking-wide text-ink-4">Wallet</p>
              <p className="tnum text-sm font-bold text-ink">
                {money(profile?.wallet_balance)}
              </p>
            </div>
            <NavLink
              to="/notifications"
              className="flex h-9 w-9 items-center justify-center rounded-lg border border-birch bg-pure-white text-ink-3 hover:text-ink"
            >
              <Bell className="h-4 w-4" />
            </NavLink>
          </div>
        </header>

        <main className="min-w-0 flex-1 px-7 py-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
