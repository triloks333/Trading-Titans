import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { CircleAlert, CircleCheck, Loader2, ShieldCheck } from 'lucide-react'
import { supabase, authRedirectUrl } from '@/lib/supabase'
import { money, cn } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { Button, Card, CardHeader, Input, Label } from '@/components/ui'

/**
 * Turns a guest account into a permanent one.
 *
 * Two things happen and the order matters. First an identity is attached to the
 * existing user — `updateUser` for email and password, or `linkIdentity` for
 * Google — so the account keeps its id, and with it every order, holding and
 * balance. Creating a fresh account instead would silently abandon all of it.
 * Then `convert_guest_account` is called, which syncs the placeholder
 * `@guest.tradingtitans` email onto the profile and pays the one-off bonus.
 *
 * The session is refreshed before that RPC because until it is, the JWT still
 * carries `is_anonymous: true` and the guest restrictions stay in force for the
 * rest of the token's life. Same reason the mobile client refreshes first.
 */
export function UpgradeAccount() {
  const { isGuest, profile, refreshProfile } = useAuth()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState<'email' | 'google' | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [bonus, setBonus] = useState<number | null>(null)

  /**
   * Maps a link failure to something actionable. "identity already exists" is the
   * common one and means the address belongs to another account, which the raw
   * message does not make obvious.
   */
  function mapError(e: unknown): string {
    const raw = e instanceof Error ? e.message : String(e)
    const m = raw.toLowerCase()
    if (m.includes('already been registered') || m.includes('already exists'))
      return 'That email is already used by another account. Sign in to it instead, or use a different address.'
    if (m.includes('should be at least') || m.includes('weak password'))
      return 'Please choose a password of at least 6 characters.'
    if (m.includes('identity is already linked'))
      return 'That sign-in method is already linked to this account.'
    return raw
  }

  async function finish() {
    // Refresh first: see the note on the component.
    try {
      await supabase.auth.refreshSession()
    } catch {
      /* a stale token only delays restrictions lifting; the RPC decides anyway */
    }
    const { data, error: rpcError } = await supabase.rpc('convert_guest_account')
    if (rpcError) throw new Error(rpcError.message)
    const result = (data ?? {}) as { converted?: boolean; bonus?: number }
    await refreshProfile()
    void queryClient.invalidateQueries()
    return result.converted ? (result.bonus ?? 0) : null
  }

  if (!isGuest) {
    return (
      <div className="space-y-6">
        <h1 className="text-xl font-extrabold text-ink">Account</h1>
        <Card className="flex items-start gap-3 px-5 py-5">
          <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-bull" />
          <div>
            <p className="text-sm font-bold text-ink">Your account is permanent</p>
            <p className="mt-1 text-xs leading-relaxed text-ink-4">
              {profile?.email
                ? `Signed in as ${profile.email}. `
                : ''}
              Nothing to upgrade — your positions and balance are already saved to
              this account.
            </p>
          </div>
        </Card>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <div>
        <h1 className="text-xl font-extrabold text-ink">Make your account permanent</h1>
        <p className="mt-1 text-sm leading-relaxed text-ink-4">
          You are exploring as a guest. Attach an email or Google to keep
          everything you have built — every position, order and rupee stays exactly
          where it is — and claim a one-off bonus.
        </p>
      </div>

      {bonus != null ? (
        <Card className="flex items-start gap-3 px-5 py-5">
          <CircleCheck className="mt-0.5 h-5 w-5 shrink-0 text-bull" />
          <div>
            <p className="text-sm font-bold text-ink">Account upgraded</p>
            <p className="mt-1 text-xs leading-relaxed text-ink-4">
              {bonus > 0
                ? `${money(bonus)} in demo cash has been credited. `
                : 'Your account is now permanent. '}
              Your positions and history are unchanged.
            </p>
            <Button size="sm" className="mt-3" onClick={() => navigate('/')}>
              Back to dashboard
            </Button>
          </div>
        </Card>
      ) : (
        <>
          <Card>
            <CardHeader
              title="Email and password"
              subtitle="You will get a confirmation link to verify the address."
            />
            <form
              className="space-y-4 px-5 py-5"
              onSubmit={(e) => {
                e.preventDefault()
                setError(null)
                setBusy('email')
                void (async () => {
                  try {
                    // updateUser on the EXISTING user, not signUp: this attaches an
                    // identity rather than creating a second account, which is what
                    // preserves the portfolio.
                    const { error: upErr } = await supabase.auth.updateUser({
                      email: email.trim(),
                      password,
                    })
                    if (upErr) throw upErr
                    const credited = await finish()
                    if (credited == null) {
                      setError(
                        'Almost there — open the confirmation link we just emailed you, then come back to this page.',
                      )
                    } else {
                      setBonus(credited)
                    }
                  } catch (e2) {
                    setError(mapError(e2))
                  } finally {
                    setBusy(null)
                  }
                })()
              }}
            >
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
                  placeholder="At least 6 characters"
                  autoComplete="new-password"
                  minLength={6}
                  required
                />
              </div>
              <Button type="submit" size="lg" className="w-full" disabled={busy != null}>
                {busy === 'email' && <Loader2 className="h-4 w-4 animate-spin" />}
                Attach email and keep my portfolio
              </Button>
            </form>
          </Card>

          <Card>
            <CardHeader title="Or use Google" subtitle="One tap, no password to remember." />
            <div className="px-5 py-5">
              <Button
                variant="outline"
                size="lg"
                className="w-full"
                disabled={busy != null}
                onClick={() => {
                  setError(null)
                  setBusy('google')
                  void (async () => {
                    try {
                      // linkIdentity, not signInWithOAuth: signing in would REPLACE
                      // the guest session with a different account and orphan the
                      // portfolio. The conversion RPC runs when the redirect returns
                      // and the auth listener fires.
                      const { error: linkErr } = await supabase.auth.linkIdentity({
                        provider: 'google',
                        options: { redirectTo: authRedirectUrl() },
                      })
                      if (linkErr) throw linkErr
                    } catch (e2) {
                      setError(mapError(e2))
                      setBusy(null)
                    }
                  })()
                }}
              >
                {busy === 'google' && <Loader2 className="h-4 w-4 animate-spin" />}
                Continue with Google
              </Button>
            </div>
          </Card>
        </>
      )}

      {error && (
        <div
          className={cn(
            'flex items-start gap-2 rounded-md px-4 py-3 text-xs leading-relaxed',
            'bg-bear-light text-bear',
          )}
        >
          <CircleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}
    </div>
  )
}
