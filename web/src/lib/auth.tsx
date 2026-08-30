import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, GUEST_EMAIL_DOMAIN, authRedirectUrl } from './supabase'
import type { Profile } from './types'

interface AuthState {
  session: Session | null
  profile: Profile | null
  loading: boolean
  isGuest: boolean
  signIn: (email: string, password: string) => Promise<void>
  register: (email: string, password: string, name: string) => Promise<void>
  continueAsGuest: () => Promise<void>
  signInWithGoogle: () => Promise<void>
  signOut: () => Promise<void>
  refreshProfile: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

/**
 * Maps a Supabase auth error to something a user can act on.
 * Mirrors mapAuthException in app/lib/services/auth_service.dart so the two
 * clients tell a user the same thing about the same failure.
 */
function mapAuthError(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e)
  const m = raw.toLowerCase()
  if (m.includes('invalid login credentials')) return 'Incorrect email or password.'
  if (m.includes('email not confirmed')) return 'Please verify your email before signing in.'
  if (m.includes('already registered') || m.includes('already exists'))
    return 'An account with this email already exists.'
  if (m.includes('should be at least') || m.includes('weak password'))
    return 'Please use a stronger password (at least 6 characters).'
  if (m.includes('failed to fetch') || m.includes('network'))
    return 'Connection problem. Check your internet and try again.'
  return raw
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  async function loadProfile(userId: string) {
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle()

    if (data) {
      setProfile(data as Profile)
      return
    }

    // Self-heal, exactly as the mobile client does: a signed-in user with no
    // profile row would otherwise be stuck on a blank dashboard.
    await supabase.rpc('ensure_profile')
    const retry = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle()
    setProfile((retry.data as Profile) ?? null)
  }

  useEffect(() => {
    let active = true

    supabase.auth.getSession().then(async ({ data }) => {
      if (!active) return
      setSession(data.session)
      if (data.session?.user) await loadProfile(data.session.user.id)
      if (active) setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      if (next?.user) void loadProfile(next.user.id)
      else setProfile(null)
    })

    return () => {
      active = false
      sub.subscription.unsubscribe()
    }
  }, [])

  const value = useMemo<AuthState>(() => {
    const guestByClaim = session?.user?.is_anonymous === true
    const guestByEmail = profile?.email?.endsWith(GUEST_EMAIL_DOMAIN) ?? false

    return {
      session,
      profile,
      loading,
      // Either signal counts, matching isGuestAccount() on mobile: the JWT claim
      // clears as soon as the session refreshes, while profiles.email keeps the
      // placeholder until convert_guest_account() syncs it.
      isGuest: guestByClaim || guestByEmail,

      async signIn(email, password) {
        const { error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        })
        if (error) throw new Error(mapAuthError(error))
      },

      async register(email, password, name) {
        const { error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: { name: name.trim() },
            // Without this, Supabase falls back to the project's Site URL, which
            // is the marketing site — its /confirm page verifies the address and
            // then tells the user to go and install the Android app, stranding
            // every web signup. Sending them back here means the client picks the
            // token out of the URL hash (detectSessionInUrl) and they land signed
            // in.
            emailRedirectTo: authRedirectUrl(),
          },
        })
        if (error) throw new Error(mapAuthError(error))
      },

      async continueAsGuest() {
        const { error } = await supabase.auth.signInAnonymously()
        if (error) throw new Error(mapAuthError(error))
        // The profile is created by the handle_new_user() trigger inside the
        // signup transaction, so poll briefly rather than assuming it is there.
        for (let i = 0; i < 5; i++) {
          const { data } = await supabase.auth.getUser()
          if (data.user) {
            await loadProfile(data.user.id)
            break
          }
          await new Promise((r) => setTimeout(r, 400))
        }
      },

      async signInWithGoogle() {
        const { error } = await supabase.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: authRedirectUrl() },
        })
        if (error) throw new Error(mapAuthError(error))
      },

      async signOut() {
        await supabase.auth.signOut()
        setProfile(null)
      },

      async refreshProfile() {
        if (session?.user) await loadProfile(session.user.id)
      },
    }
  }, [session, profile, loading])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}
