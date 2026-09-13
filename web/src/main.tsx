import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'

import { AuthProvider, useAuth } from '@/lib/auth'
import { AppShell } from '@/components/AppShell'
import { AuthPage } from '@/pages/AuthPage'
import { Dashboard } from '@/pages/Dashboard'
import { Trade } from '@/pages/Trade'
import { Portfolio } from '@/pages/Portfolio'
import { WalletPage } from '@/pages/WalletPage'
import { Leaderboard } from '@/pages/Leaderboard'
import { Autopsy } from '@/pages/Autopsy'
import { Notifications } from '@/pages/Notifications'
import { UpgradeAccount } from '@/pages/UpgradeAccount'
import { Plans } from '@/pages/Plans'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Prices move; stale-by-default with a short window keeps the UI honest
      // without hammering the database on every navigation.
      staleTime: 10_000,
      retry: 1,
      refetchOnWindowFocus: true,
    },
  },
})

function Root() {
  const { session, loading } = useAuth()

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-parchment">
        <div className="h-6 w-6 animate-spin rounded-full border-2 border-birch border-t-brand" />
      </div>
    )
  }

  if (!session) return <AuthPage />

  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="/" element={<Dashboard />} />
        <Route path="/trade" element={<Trade />} />
        <Route path="/portfolio" element={<Portfolio />} />
        <Route path="/wallet" element={<WalletPage />} />
        <Route path="/leaderboard" element={<Leaderboard />} />
        <Route path="/autopsy" element={<Autopsy />} />
        <Route path="/notifications" element={<Notifications />} />
        <Route path="/upgrade" element={<UpgradeAccount />} />
        <Route path="/plans" element={<Plans />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      {/* Served under /app (see vite.config.ts). Without the basename every
          <NavLink to="/trade"> would point at thetradingtitans.com/trade, which
          is the marketing site, not this app.

          The trailing slash MUST be stripped. Vite's BASE_URL is "/app/", and
          React Router refuses to match the URL "/app" against a basename of
          "/app/" — it renders nothing at all and only says so in a console
          warning. Every request still returns 200, so this looks healthy from
          the outside and shows the user a blank page. */}
      <BrowserRouter basename={import.meta.env.BASE_URL.replace(/\/$/, '')}>
        <AuthProvider>
          <Root />
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
