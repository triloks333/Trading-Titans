import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Stethoscope, TrendingDown, TrendingUp } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { money, signedMoney, instrumentMoney, percent, shortDate, cn } from '@/lib/format'
import { Badge, Card, CardHeader, Delta, EmptyState, Skeleton } from '@/components/ui'
import type { Order } from '@/lib/types'

/**
 * Post-mortem of closed trades.
 *
 * Built from `orders` rather than a separate insights table, because the exit
 * order already carries everything needed: the realised figure, and each of the
 * charge components the engine wrote onto it.
 *
 * Every P&L here is NET. `realized_pnl` is stored GROSS — charges live in their own
 * columns and are never subtracted from it — so showing that column raw is what
 * made the mobile order sheet and the mobile portfolio disagree about the same
 * trade. The arithmetic is shown rather than asserted.
 *
 * One honest limitation, stated in the UI as well: these charges are the EXIT
 * leg's only. The entry leg was charged on its own row when it was placed, so a
 * full round trip cost more than the figure shown. Pairing entries to exits needs
 * a position-level ledger that does not exist yet, and inventing a pairing would
 * be worse than naming the gap.
 */
export function Autopsy() {
  const [filter, setFilter] = useState<'all' | 'wins' | 'losses'>('all')

  const closed = useQuery({
    queryKey: ['closedOrders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('*')
        .eq('status', 'executed')
        .neq('realized_pnl', 0)
        .order('executed_at', { ascending: false, nullsFirst: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as Order[]
    },
  })

  const rows = useMemo(() => {
    const all = (closed.data ?? []).map((o) => {
      const gross = o.realized_pnl ?? 0
      const charges = o.total_charges ?? 0
      return { order: o, gross, charges, net: gross - charges }
    })
    if (filter === 'wins') return all.filter((r) => r.net > 0)
    if (filter === 'losses') return all.filter((r) => r.net < 0)
    return all
  }, [closed.data, filter])

  const stats = useMemo(() => {
    const all = (closed.data ?? []).map((o) => (o.realized_pnl ?? 0) - (o.total_charges ?? 0))
    const wins = all.filter((n) => n > 0)
    const losses = all.filter((n) => n < 0)
    const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)
    return {
      count: all.length,
      net: sum(all),
      winRate: all.length > 0 ? (wins.length / all.length) * 100 : 0,
      avgWin: wins.length > 0 ? sum(wins) / wins.length : 0,
      avgLoss: losses.length > 0 ? sum(losses) / losses.length : 0,
      totalCharges: (closed.data ?? []).reduce((s, o) => s + (o.total_charges ?? 0), 0),
    }
  }, [closed.data])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-extrabold text-ink">Trade Autopsy</h1>
        <p className="mt-1 text-sm text-ink-4">
          Every closed trade, net of the charges on its exit.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <Tile label="Closed trades" value={String(stats.count)} />
        <Tile label="Net result" value={signedMoney(stats.net, 2)} delta={stats.net} />
        <Tile label="Win rate" value={`${stats.winRate.toFixed(0)}%`} />
        <Tile label="Average win" value={signedMoney(stats.avgWin, 2)} delta={stats.avgWin} />
        <Tile
          label="Charges paid"
          value={money(stats.totalCharges, 2)}
          hint="On exits shown here"
        />
      </div>

      <Card>
        <CardHeader
          title="Closed trades"
          subtitle="Gross, then charges, then what actually reached your wallet"
          action={
            <div className="flex gap-1.5">
              {(
                [
                  ['all', 'All'],
                  ['wins', 'Wins'],
                  ['losses', 'Losses'],
                ] as const
              ).map(([id, label]) => (
                <button
                  key={id}
                  onClick={() => setFilter(id)}
                  className={cn(
                    'rounded-tag px-2.5 py-1 text-[11px] font-semibold transition-colors',
                    filter === id ? 'bg-ink text-white' : 'bg-cream text-ink-4 hover:text-ink',
                  )}
                >
                  {label}
                </button>
              ))}
            </div>
          }
        />

        {closed.isLoading ? (
          <div className="space-y-3 p-5">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Stethoscope className="h-5 w-5" />}
            title="No closed trades yet"
            message="Once you close a position, its full breakdown appears here."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
                  <th className="px-5 py-2.5 font-medium">Instrument</th>
                  <th className="px-3 py-2.5 text-right font-medium">Qty</th>
                  <th className="px-3 py-2.5 text-right font-medium">Exit price</th>
                  <th className="px-3 py-2.5 text-right font-medium">Gross</th>
                  <th className="px-3 py-2.5 text-right font-medium">Charges</th>
                  <th className="px-3 py-2.5 text-right font-medium">Net</th>
                  <th className="px-5 py-2.5 text-right font-medium">Closed</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(({ order: o, gross, charges, net }) => (
                  <tr key={o.id} className="border-b border-birch/60 last:border-0">
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-2">
                        {net >= 0 ? (
                          <TrendingUp className="h-3.5 w-3.5 text-bull" />
                        ) : (
                          <TrendingDown className="h-3.5 w-3.5 text-bear" />
                        )}
                        <span className="font-semibold text-ink">{o.symbol}</span>
                        {o.instrument_type && o.instrument_type !== 'EQUITY' && (
                          <Badge tone="violet">{o.option_type || 'FUT'}</Badge>
                        )}
                      </div>
                      <p className="mt-0.5 text-[11px] text-ink-4">
                        {o.side.toUpperCase()} · {(o.order_type ?? 'market').toUpperCase()}
                      </p>
                    </td>
                    <td className="tnum px-3 py-3 text-right text-ink-3">{o.quantity}</td>
                    <td className="tnum px-3 py-3 text-right text-ink-3">
                      {instrumentMoney(o.price ?? 0, o.market, 2)}
                    </td>
                    <td className="tnum px-3 py-3 text-right text-ink-3">
                      {signedMoney(gross, 2)}
                    </td>
                    <td className="tnum px-3 py-3 text-right text-ink-4">
                      {charges > 0 ? `-${money(charges, 2)}` : '—'}
                    </td>
                    <td className="px-3 py-3 text-right">
                      <Delta value={net}>{signedMoney(net, 2)}</Delta>
                      {gross !== 0 && (
                        <p className="text-[11px] text-ink-5">
                          {percent((charges / Math.abs(gross)) * -100, 1)} to costs
                        </p>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right text-xs text-ink-4">
                      {shortDate(o.executed_at ?? o.created_at)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="border-t border-birch px-5 py-3 text-[11px] leading-relaxed text-ink-4">
          Charges shown are for the exit order only. The entry was charged
          separately when it was placed, so a complete round trip cost more than
          the figures above.
        </p>
      </Card>
    </div>
  )
}

function Tile({
  label,
  value,
  hint,
  delta,
}: {
  label: string
  value: string
  hint?: string
  delta?: number
}) {
  return (
    <Card className="px-5 py-4">
      <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">{label}</p>
      <p
        className={cn(
          'tnum mt-1.5 text-xl font-extrabold',
          delta === undefined ? 'text-ink' : delta >= 0 ? 'text-bull' : 'text-bear',
        )}
      >
        {value}
      </p>
      {hint && <p className="mt-0.5 text-[11px] text-ink-4">{hint}</p>}
    </Card>
  )
}
