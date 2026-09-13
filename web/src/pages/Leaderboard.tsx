import { useQuery } from '@tanstack/react-query'
import { Trophy, Crown } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { signedMoney, cn } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { useTierMap } from '@/lib/tier'
import {
  Badge,
  Card,
  CardHeader,
  Delta,
  EmptyState,
  Skeleton,
  TierBadge,
} from '@/components/ui'

interface Row {
  id: string
  name: string | null
  total_realized_pnl: number | null
}

/**
 * Leaderboard, read from the `leaderboard` VIEW rather than `profiles`.
 *
 * That is not interchangeable. `profiles` is restricted to owner and admin reads,
 * so querying it here would return one row — your own — and look like an empty
 * board. The view exposes only the safe columns and deliberately excludes email,
 * which is exactly why it exists. Same source the mobile app uses.
 */
export function Leaderboard() {
  const { session } = useAuth()

  const board = useQuery({
    queryKey: ['leaderboard'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('leaderboard')
        // wallet_balance is deliberately not selected: the board ranks on
        // realised P&L and shows only that. Owners and admins are excluded by
        // the view itself, not here.
        .select('id, name, total_realized_pnl')
        .order('total_realized_pnl', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as Row[]
    },
    refetchInterval: 60_000,
  })

  const rows = board.data ?? []
  const myIndex = rows.findIndex((r) => r.id === session?.user?.id)

  // Plan badges come from `user_tiers`, in one follow-up query for the whole page
  // rather than a lookup per row. The `leaderboard` view's `plan` column is not
  // used: every account sits on 'free_starter', so it badged all 193 rows
  // identically and told a reader nothing.
  const { data: tiers } = useTierMap(rows.map((r) => r.id))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-extrabold text-ink">Leaderboard</h1>
        <p className="mt-1 text-sm text-ink-4">
          Ranked by realised profit, booked net of exit charges.
        </p>
      </div>

      {myIndex >= 0 && (
        <Card className="flex items-center gap-4 px-5 py-4">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-brand-pale text-sm font-extrabold text-brand-deep">
            #{myIndex + 1}
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-bold text-ink">Your position</p>
            <p className="text-[11px] text-ink-4">
              {myIndex === 0
                ? 'Top of the board.'
                : `${myIndex} trader${myIndex === 1 ? '' : 's'} ahead of you.`}
            </p>
          </div>
          <Delta value={rows[myIndex].total_realized_pnl ?? 0} className="text-base">
            {signedMoney(rows[myIndex].total_realized_pnl ?? 0, 2)}
          </Delta>
        </Card>
      )}

      <Card>
        <CardHeader title="Top traders" subtitle="Updated every minute" />
        {board.isLoading ? (
          <div className="space-y-3 p-5">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-11 w-full" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Trophy className="h-5 w-5" />}
            title="Nobody on the board yet"
            message="Close a trade at a profit and you will be the first."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
                  <th className="px-5 py-2.5 font-medium">#</th>
                  <th className="px-3 py-2.5 font-medium">Trader</th>
                  <th className="px-5 py-2.5 text-right font-medium">Realised P&L</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => {
                  const isMe = r.id === session?.user?.id
                  return (
                    <tr
                      key={r.id}
                      className={cn(
                        'border-b border-birch/60 last:border-0',
                        isMe && 'bg-brand-pale/50',
                      )}
                    >
                      <td className="px-5 py-3">
                        <span
                          className={cn(
                            'tnum inline-flex h-6 min-w-6 items-center justify-center rounded-md px-1.5 text-[11px] font-bold',
                            i === 0
                              ? 'bg-brand text-white'
                              : i < 3
                                ? 'bg-brand-pale text-brand-deep'
                                : 'text-ink-4',
                          )}
                        >
                          {i + 1}
                        </span>
                      </td>
                      <td className="px-3 py-3">
                        <div className="flex items-center gap-2">
                          {i === 0 && <Crown className="h-3.5 w-3.5 text-brand" />}
                          <span className="font-semibold text-ink">
                            {r.name?.trim() || 'Anonymous Titan'}
                          </span>
                          {isMe && <Badge tone="brand">YOU</Badge>}
                          <TierBadge tier={tiers?.[r.id]} />
                        </div>
                      </td>
                      <td className="px-5 py-3 text-right">
                        <Delta value={r.total_realized_pnl ?? 0}>
                          {signedMoney(r.total_realized_pnl ?? 0, 2)}
                        </Delta>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  )
}
