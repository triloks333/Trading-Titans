import { useQuery } from '@tanstack/react-query'
import { supabase } from './supabase'

/*
 * Who is on which plan.
 *
 * Read from the `user_tiers` view, which is `current_tier(id)` over `profiles`.
 * Deriving it rather than storing a `profiles.tier` column is deliberate: a
 * stored column is a second copy of the truth that has to be kept in step with
 * `subscriptions`, and the failure mode of that going stale is a paying user
 * losing access — or a lapsed one keeping it. The view cannot drift because
 * there is nothing to update.
 *
 * The view is intentionally readable for other users: a plan badge next to a name
 * on the leaderboard is public by design. It exposes a user id and a tier and
 * nothing else, which is why the badge did not become a column on `profiles` —
 * that table stays own-row-only so a badge lookup can never widen into a way of
 * reading somebody's email or balance.
 */

export type Tier = 'free' | 'pro' | 'titan'

export function isPaidTier(tier: Tier | undefined | null): boolean {
  return tier === 'pro' || tier === 'titan'
}

/** Tiers in increasing order of access, for "does this tier reach that one" checks. */
const RANK: Record<Tier, number> = { free: 0, pro: 1, titan: 2 }

export function tierAtLeast(tier: Tier | undefined | null, needed: Tier): boolean {
  return RANK[tier ?? 'free'] >= RANK[needed]
}

/**
 * Tiers for a set of users, as a lookup.
 *
 * ponytail: `current_tier()` is evaluated once per row, so this is O(n) index
 * lookups for a leaderboard page — fine at 100 rows. The ceiling is a board of
 * thousands; the upgrade path is to materialise `tier` into the `leaderboard`
 * view so it comes back with the rest of the row.
 */
export function useTierMap(userIds: string[]) {
  // Sorted and joined so a re-render with the same ids in a different order does
  // not look like a new query and refetch.
  const key = [...userIds].sort().join(',')

  return useQuery({
    queryKey: ['user-tiers', key],
    enabled: userIds.length > 0,
    staleTime: 60_000,
    queryFn: async (): Promise<Record<string, Tier>> => {
      const { data, error } = await supabase
        .from('user_tiers')
        .select('user_id, tier')
        .in('user_id', userIds)
      if (error) throw new Error(error.message)

      const map: Record<string, Tier> = {}
      for (const row of data ?? []) {
        map[(row as { user_id: string }).user_id] = (row as { tier: Tier }).tier
      }
      return map
    },
  })
}

/** The signed-in user's own tier. Defaults to free while loading, never to paid. */
export function useMyTier(userId: string | undefined): Tier {
  const { data } = useTierMap(userId ? [userId] : [])
  return (userId ? data?.[userId] : undefined) ?? 'free'
}
