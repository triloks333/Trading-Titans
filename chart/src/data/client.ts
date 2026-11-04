/*
 * Where the chart gets its numbers.
 *
 * Same project, same publishable key, same Row Level Security as the app and the
 * web app. Defaults mirror `web/src/lib/supabase.ts` so a fresh checkout runs
 * with no setup — that file established the convention and this follows it
 * rather than inventing a second one.
 *
 * No `@supabase/supabase-js` here on purpose. This module makes two GETs; pulling
 * in the whole client library would add ~40kB to a bundle that has to be inlined
 * into a Flutter asset and loaded on a phone.
 */

const url =
  import.meta.env?.VITE_SUPABASE_URL ?? 'https://bftvimnhpoiuoyryyiff.supabase.co'

const anonKey =
  import.meta.env?.VITE_SUPABASE_ANON_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak'

export const base = url.replace(/\/$/, '')
export const functionsBase = `${base}/functions/v1`
export const restBase = `${base}/rest/v1`

export const headers: Record<string, string> = {
  apikey: anonKey,
  Authorization: `Bearer ${anonKey}`,
}

export async function getJson<T>(target: string, timeoutMs = 12_000): Promise<T> {
  const res = await fetch(target, {
    headers,
    signal: AbortSignal.timeout(timeoutMs),
  })
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return (await res.json()) as T
}
