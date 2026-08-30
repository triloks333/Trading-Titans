import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, BellOff, CheckCheck } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { timeAgo, cn } from '@/lib/format'
import { Button, Card, CardHeader, EmptyState, Skeleton } from '@/components/ui'

interface Notification {
  id: string
  title: string | null
  body: string | null
  is_read: boolean | null
  action_type: string | null
  created_at: string
}

export function Notifications() {
  const queryClient = useQueryClient()

  const list = useQuery({
    queryKey: ['notifications'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('id, title, body, is_read, action_type, created_at')
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as Notification[]
    },
    refetchInterval: 60_000,
  })

  const rows = list.data ?? []
  const unread = rows.filter((n) => !n.is_read)

  /*
   * Marking read is an UPDATE on `notifications`, which RLS scopes to the owner.
   * No user id is sent: adding one would be redundant at best and, if it were
   * ever trusted, a way to touch another account's rows. The policy is the
   * authority.
   */
  const markAll = useMutation({
    mutationFn: async () => {
      const ids = unread.map((n) => n.id)
      if (ids.length === 0) return
      const { error } = await supabase
        .from('notifications')
        .update({ is_read: true })
        .in('id', ids)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notifications'] }),
  })

  const markOne = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('notifications')
        .update({ is_read: true })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notifications'] }),
  })

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold text-ink">Notifications</h1>
          <p className="mt-1 text-sm text-ink-4">
            {unread.length > 0
              ? `${unread.length} unread`
              : 'Order fills, price alerts and rewards.'}
          </p>
        </div>
        {unread.length > 0 && (
          <Button
            variant="outline"
            size="sm"
            disabled={markAll.isPending}
            onClick={() => markAll.mutate()}
          >
            <CheckCheck className="h-3.5 w-3.5" />
            Mark all read
          </Button>
        )}
      </div>

      <Card>
        <CardHeader title="Recent" subtitle="Newest first" />
        {list.isLoading ? (
          <div className="space-y-3 p-5">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<BellOff className="h-5 w-5" />}
            title="Nothing yet"
            message="When an order fills, a price alert triggers or a reward lands, it shows up here."
          />
        ) : (
          <ul className="divide-y divide-birch/60">
            {rows.map((n) => (
              <li
                key={n.id}
                className={cn(
                  'flex items-start gap-3 px-5 py-3.5',
                  !n.is_read && 'bg-brand-pale/40',
                )}
              >
                <div
                  className={cn(
                    'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full',
                    n.is_read ? 'bg-cream text-ink-4' : 'bg-brand-pale text-brand-deep',
                  )}
                >
                  <Bell className="h-3.5 w-3.5" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-[13px] font-semibold text-ink">
                    {n.title?.trim() || 'Notification'}
                  </p>
                  {n.body && (
                    <p className="mt-0.5 text-xs leading-relaxed text-ink-3">{n.body}</p>
                  )}
                  <p className="mt-1 text-[11px] text-ink-5">{timeAgo(n.created_at)}</p>
                </div>
                {!n.is_read && (
                  <button
                    onClick={() => markOne.mutate(n.id)}
                    className="shrink-0 text-[11px] font-semibold text-brand hover:underline"
                  >
                    Mark read
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  )
}
