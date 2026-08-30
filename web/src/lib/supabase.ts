import { createClient } from '@supabase/supabase-js'

/*
 * Same project, same anon key, same Row Level Security as the Android app.
 * There is no separate web backend and no new privileges: every query below is
 * subject to the identical RLS policies the mobile app runs under, so the web
 * app cannot read or write anything the phone could not.
 *
 * Publishable via env in production; the defaults mirror
 * app/lib/core/supabase_config.dart so a local checkout runs with no setup.
 */
const url =
  import.meta.env.VITE_SUPABASE_URL ?? 'https://bftvimnhpoiuoyryyiff.supabase.co'

const anonKey =
  import.meta.env.VITE_SUPABASE_ANON_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak'

export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})

/** Base URL for the edge functions the mobile app already uses. */
export const functionsBase = `${url.replace(/\/$/, '')}/functions/v1`

export const functionHeaders: Record<string, string> = {
  apikey: anonKey,
  Authorization: `Bearer ${anonKey}`,
  'Content-Type': 'application/json',
}

/**
 * Placeholder email domain the handle_new_user() trigger writes for anonymous
 * users. Mirrors AppConstants.guestEmailDomain.
 */
export const GUEST_EMAIL_DOMAIN = '@guest.tradingtitans'

/** Where an OAuth round-trip should return to. Works on localhost and in prod. */
export const authRedirectUrl = () => window.location.origin
