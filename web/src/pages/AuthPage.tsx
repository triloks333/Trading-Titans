import { useState } from 'react'
import { BarChart3, Lock, Wallet, TrendingUp } from 'lucide-react'
import { Button, Input, Label } from '@/components/ui'
import { useAuth } from '@/lib/auth'

const POINTS = [
  {
    icon: <TrendingUp className="h-4 w-4" />,
    title: 'Real market prices',
    body: 'NSE, BSE, US stocks and crypto — live, with real brokerage and STT applied to every trade.',
  },
  {
    icon: <Wallet className="h-4 w-4" />,
    title: 'Virtual money only',
    body: 'Start with ₹11,000 in demo cash. Every order behaves exactly as it would with your own money.',
  },
  {
    icon: <BarChart3 className="h-4 w-4" />,
    title: 'Earn by playing',
    body: '25 challenges pay demo cash for practising. Climb the leaderboard on percentage return.',
  },
]

/**
 * Reads an auth outcome out of the URL hash.
 *
 * Supabase appends the result of an emailed link to the fragment. On success it
 * is `#access_token=…`, which the client consumes itself and we never see here.
 * On failure it is `#error=…&error_description=…`, which nothing consumes — so
 * without this the user lands on a plain sign-in form with no idea why, having
 * just clicked a link that promised to verify them.
 */
function readHashOutcome(): string | null {
  const hash = window.location.hash
  if (!hash.includes('error')) return null
  const params = new URLSearchParams(hash.replace(/^#/, ''))
  const desc = params.get('error_description') ?? params.get('error')
  // Strip it so a refresh does not resurrect a stale message.
  window.history.replaceState(null, '', window.location.pathname)
  return desc ? desc.replace(/\+/g, ' ') : null
}

export function AuthPage() {
  const auth = useAuth()
  const [mode, setMode] = useState<'signin' | 'register'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(() => readHashOutcome())
  const [notice, setNotice] = useState<string | null>(null)

  async function run(fn: () => Promise<void>) {
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      await fn()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="grid min-h-screen lg:grid-cols-[1.15fr_1fr]">
      {/* Brand half. Hidden below lg, where the form should own the screen. */}
      <aside className="hidden flex-col justify-center bg-ink px-16 py-16 lg:flex">
        <div className="max-w-lg">
          <h1 className="text-[2.6rem] font-black leading-[1.1] text-white">
            Learn the market
            <br />
            without losing money.
          </h1>
          <p className="mt-5 text-sm leading-relaxed text-white/65">
            A trading desk that behaves exactly like the real one, funded entirely
            with virtual cash. Practise, compete, and get it wrong for free.
          </p>

          <div className="mt-12 space-y-7">
            {POINTS.map((p) => (
              <div key={p.title} className="flex gap-4">
                <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-white/10 text-brand-mid">
                  {p.icon}
                </div>
                <div>
                  <h3 className="text-sm font-bold text-white">{p.title}</h3>
                  <p className="mt-1 text-xs leading-relaxed text-white/55">{p.body}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </aside>

      {/* Form half. */}
      <main className="flex items-center justify-center px-6 py-12">
        <div className="w-full max-w-[380px]">
          <div className="mb-8 flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand text-white">
              <TrendingUp className="h-5 w-5" />
            </div>
            <span className="text-base font-extrabold text-ink">Trading Titans</span>
          </div>

          <h2 className="text-2xl font-extrabold text-ink">
            {mode === 'signin' ? 'Welcome back, Titan' : 'Join the Titans'}
          </h2>
          <p className="mt-1 text-sm text-ink-4">
            {mode === 'signin'
              ? 'Sign in to your trading desk.'
              : 'Real market. Virtual risk.'}
          </p>

          <form
            className="mt-7 space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              void run(async () => {
                if (mode === 'signin') {
                  await auth.signIn(email, password)
                } else {
                  await auth.register(email, password, name)
                  setNotice(
                    `Account created. We sent a verification link to ${email.trim()}. ` +
                      'Open it to confirm your address, then sign in here.',
                  )
                  setMode('signin')
                }
              })
            }}
          >
            {mode === 'register' && (
              <div>
                <Label>Name</Label>
                <Input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Your name"
                  autoComplete="name"
                  required
                />
              </div>
            )}

            <div>
              <Label>Email</Label>
              <Input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                autoComplete="email"
                required
              />
            </div>

            <div>
              <Label>Password</Label>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
                required
              />
            </div>

            {error && (
              <p className="rounded-md bg-bear-light px-3 py-2 text-xs leading-relaxed text-bear">
                {error}
              </p>
            )}
            {notice && (
              <p className="rounded-md bg-bull-light px-3 py-2 text-xs leading-relaxed text-bull">
                {notice}
              </p>
            )}

            <Button type="submit" size="lg" className="w-full" disabled={busy}>
              {busy ? 'Please wait…' : mode === 'signin' ? 'Sign in' : 'Create account'}
            </Button>
          </form>

          <div className="my-5 flex items-center gap-3">
            <span className="h-px flex-1 bg-birch" />
            <span className="text-[11px] font-medium text-ink-5">OR</span>
            <span className="h-px flex-1 bg-birch" />
          </div>

          <Button
            variant="outline"
            size="lg"
            className="w-full"
            disabled={busy}
            onClick={() => void run(auth.signInWithGoogle)}
          >
            <GoogleMark />
            Continue with Google
          </Button>

          <Button
            variant="ghost"
            size="lg"
            className="mt-2 w-full"
            disabled={busy}
            onClick={() => void run(auth.continueAsGuest)}
          >
            <Lock className="h-3.5 w-3.5" />
            Explore as guest (₹5,000)
          </Button>

          <p className="mt-6 text-center text-xs text-ink-4">
            {mode === 'signin' ? 'New to the desk?' : 'Already have an account?'}{' '}
            <button
              type="button"
              className="font-semibold text-brand hover:underline"
              onClick={() => {
                setMode(mode === 'signin' ? 'register' : 'signin')
                setError(null)
                setNotice(null)
              }}
            >
              {mode === 'signin' ? 'Create account' : 'Sign in'}
            </button>
          </p>

          <p className="mt-8 text-center text-[11px] leading-relaxed text-ink-5">
            Virtual money only. Trading Titans is an educational simulator and
            does not offer real trading or investment advice.
          </p>
        </div>
      </main>
    </div>
  )
}

function GoogleMark() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22-.03-.63z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"
      />
    </svg>
  )
}
