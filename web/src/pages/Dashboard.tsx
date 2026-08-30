import { useQuery } from '@tanstack/react-query'
import { NavLink } from 'react-router-dom'
import { ArrowUpRight, Briefcase, Trophy, Target } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import {
  fetchQuotes,
  fetchAllQuotes,
  fetchTodayActivity,
  fetchUsdInr,
  PULSE,
  PULSE_SYMBOLS,
} from '@/lib/market'
import {
  money,
  signedMoney,
  instrumentMoney,
  signedInstrumentMoney,
  percent,
  cn,
  timeAgo,
} from '@/lib/format'
import { buildPositions, totalsOf } from '@/lib/positions'
import { useAuth } from '@/lib/auth'
import { Badge, Card, CardHeader, Delta, EmptyState, Skeleton, Button } from '@/components/ui'
import type { Order, Challenge } from '@/lib/types'

export function Dashboard() {
  const { profile } = useAuth()

  const pulse = useQuery({
    queryKey: ['pulse'],
    queryFn: () => fetchQuotes(PULSE_SYMBOLS),
    refetchInterval: 15_000,
  })

  const holdings = useQuery({
    queryKey: ['holdings'],
    queryFn: async () => {
      const { data, error } = await supabase.from('holdings').select('*')
      if (error) throw error
      return data ?? []
    },
  })

  const foPositions = useQuery({
    queryKey: ['foPositions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('fo_positions')
        .select('*')
        .eq('is_settled', false)
      if (error) throw error
      return data ?? []
    },
  })

  const quotes = useQuery({
    queryKey: ['allQuotes'],
    queryFn: fetchAllQuotes,
    refetchInterval: 20_000,
  })

  const today = useQuery({ queryKey: ['todayActivity'], queryFn: fetchTodayActivity })
  const usdInr = useQuery({
    queryKey: ['usdInr'],
    queryFn: fetchUsdInr,
    staleTime: 5 * 60_000,
  })

  const orders = useQuery({
    queryKey: ['recentOrders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(6)
      if (error) throw error
      return (data ?? []) as Order[]
    },
  })

  const challenges = useQuery({
    queryKey: ['challenges'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('challenges')
        .select('*')
        .eq('is_active', true)
        .order('sort_order')
        .limit(5)
      if (error) throw error
      return (data ?? []) as Challenge[]
    },
  })

  /*
   * The dashboard and the portfolio now derive their numbers from the SAME model.
   *
   * They used to each do it inline, and disagreed: this page summed every holding
   * including closed ones and excluded shorts and F&O, while Portfolio filtered
   * differently. Two screens reporting different totals for one portfolio is the
   * exact complaint that had to be fixed on mobile, so the web gets one source of
   * truth rather than inheriting the same argument.
   */
  const positions = buildPositions({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    holdings: (holdings.data ?? []) as any,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    foPositions: (foPositions.data ?? []) as any,
    quotes: quotes.data ?? [],
    today: today.data ?? new Map(),
    usdInr: usdInr.data ?? 0,
  })
  const totals = totalsOf(positions)
  const wallet = profile?.wallet_balance ?? 0
  const total = wallet + totals.valueInr

  return (
    <div className="space-y-6">
      {/* Top row: four summary tiles. */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <Stat label="Total portfolio value" value={money(total)} emphasis />
        <Stat label="Wallet" value={money(wallet)} hint="Available to trade" />
        <Stat
          label="Capital deployed"
          value={money(totals.investedInr)}
          hint={`${positions.length} position${positions.length === 1 ? '' : 's'}`}
        />
        <Stat
          label="Today's P&L"
          value={signedMoney(totals.dayPnlInr, 2)}
          delta={totals.dayPnlInr}
        />
        <Stat
          label="Unrealised P&L"
          value={signedMoney(totals.pnlInr, 2)}
          delta={totals.pnlInr}
          hint={totals.investedInr > 0 ? percent(totals.pnlPct) : undefined}
        />
      </div>

      {/* Market pulse strip. */}
      <Card>
        <CardHeader title="Market Pulse" subtitle="Live index and crypto prices" />
        <div className="grid divide-birch sm:grid-cols-3 sm:divide-x lg:grid-cols-6">
          {pulse.isLoading
            ? Array.from({ length: 6 }).map((_, i) => (
                <div key={i} className="p-4">
                  <Skeleton className="h-3 w-20" />
                  <Skeleton className="mt-2 h-5 w-24" />
                </div>
              ))
            : PULSE.map(({ symbol: sym, label }) => {
                const q = pulse.data?.find((x) => x.symbol === sym)
                const chg = q?.change_pct ?? 0
                return (
                  <div key={sym} className="p-4">
                    <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">
                      {label}
                    </p>
                    <p className="tnum mt-1 text-lg font-bold text-ink">
                      {q ? instrumentMoney(q.price, q.market, 0) : '—'}
                    </p>
                    {q && <Delta value={chg} className="text-xs">{percent(chg)}</Delta>}
                  </div>
                )
              })}
        </div>
      </Card>

      {/* Main two-column region — the thing a phone layout cannot do. */}
      <div className="grid gap-6 lg:grid-cols-[1.7fr_1fr]">
        <Card>
          <CardHeader
            title="Your holdings"
            subtitle="Marked to the latest available price"
            action={
              <NavLink to="/portfolio">
                <Button variant="ghost" size="sm">
                  View all <ArrowUpRight className="h-3 w-3" />
                </Button>
              </NavLink>
            }
          />
          {holdings.isLoading ? (
            <div className="space-y-3 p-5">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          ) : positions.length === 0 ? (
            <EmptyState
              icon={<Briefcase className="h-5 w-5" />}
              title="No holdings yet"
              message="Buy your first stock and it will show up here with live profit and loss."
              action={
                <NavLink to="/trade">
                  <Button size="sm">Start trading</Button>
                </NavLink>
              }
            />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
                    <th className="px-5 py-2.5 font-medium">Symbol</th>
                    <th className="px-3 py-2.5 text-right font-medium">Qty</th>
                    <th className="px-3 py-2.5 text-right font-medium">Avg</th>
                    <th className="px-3 py-2.5 text-right font-medium">LTP</th>
                    <th className="px-3 py-2.5 text-right font-medium">Value</th>
                    <th className="px-5 py-2.5 text-right font-medium">P&L</th>
                  </tr>
                </thead>
                <tbody>
                  {positions.slice(0, 8).map((p) => (
                    <tr key={p.key} className="border-b border-birch/60 last:border-0">
                      <td className="px-5 py-3">
                        <div className="flex items-center gap-2">
                          <p className="font-semibold text-ink">{p.label}</p>
                          {p.isShort && <Badge tone="bear">SHORT</Badge>}
                        </div>
                        <p className="text-[11px] text-ink-4">{p.kind.toLowerCase()}</p>
                      </td>
                      <td className="tnum px-3 py-3 text-right text-ink-3">{p.quantity}</td>
                      <td className="tnum px-3 py-3 text-right text-ink-3">
                        {instrumentMoney(p.displayAvgPrice, p.market, 2)}
                      </td>
                      <td className="tnum px-3 py-3 text-right text-ink">
                        {instrumentMoney(p.displayLtp, p.market, 2)}
                      </td>
                      <td className="tnum px-3 py-3 text-right text-ink">
                        {instrumentMoney(p.displayValue, p.market, 2)}
                      </td>
                      <td className="px-5 py-3 text-right">
                        <Delta value={p.displayPnl}>
                          {signedInstrumentMoney(p.displayPnl, p.market, 2)}
                        </Delta>
                        <p
                          className={cn(
                            'text-[11px]',
                            p.displayPnl >= 0 ? 'text-bull' : 'text-bear',
                          )}
                        >
                          {percent(p.displayPnlPct)}
                        </p>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        <div className="space-y-6">
          <Card>
            <CardHeader title="Challenges" subtitle="Earn demo cash by practising" />
            {challenges.isLoading ? (
              <div className="space-y-3 p-5">
                {Array.from({ length: 4 }).map((_, i) => (
                  <Skeleton key={i} className="h-8 w-full" />
                ))}
              </div>
            ) : (
              <ul className="divide-y divide-birch/60">
                {(challenges.data ?? []).map((c) => (
                  <li key={c.key} className="flex items-start gap-3 px-5 py-3">
                    <Target className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-semibold text-ink">{c.title}</p>
                      <p className="truncate text-[11px] text-ink-4">{c.description}</p>
                    </div>
                    <Badge tone="bull">{money(c.reward_amount)}</Badge>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <CardHeader
              title="Recent orders"
              action={
                <NavLink to="/portfolio">
                  <Button variant="ghost" size="sm">
                    All <ArrowUpRight className="h-3 w-3" />
                  </Button>
                </NavLink>
              }
            />
            {orders.isLoading ? (
              <div className="space-y-3 p-5">
                {Array.from({ length: 3 }).map((_, i) => (
                  <Skeleton key={i} className="h-8 w-full" />
                ))}
              </div>
            ) : (orders.data ?? []).length === 0 ? (
              <EmptyState
                icon={<Trophy className="h-5 w-5" />}
                title="No orders yet"
                message="Your placed, pending and executed orders will appear here."
              />
            ) : (
              <ul className="divide-y divide-birch/60">
                {(orders.data ?? []).map((o) => (
                  <li key={o.id} className="flex items-center gap-3 px-5 py-3">
                    <Badge tone={o.side === 'buy' ? 'bull' : 'bear'}>
                      {o.side.toUpperCase()}
                    </Badge>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-semibold text-ink">{o.symbol}</p>
                      <p className="text-[11px] text-ink-4">
                        {o.quantity} @ {instrumentMoney(o.price ?? 0, o.market, 2)} ·{' '}
                        {timeAgo(o.created_at)}
                      </p>
                    </div>
                    <Badge tone={o.status === 'executed' ? 'neutral' : 'brand'}>
                      {o.status}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </div>
  )
}

function Stat({
  label,
  value,
  hint,
  delta,
  emphasis,
}: {
  label: string
  value: string
  hint?: string
  delta?: number
  emphasis?: boolean
}) {
  return (
    <Card className="px-5 py-4">
      <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">{label}</p>
      <p
        className={cn(
          'tnum mt-1.5 font-extrabold text-ink',
          emphasis ? 'text-[26px]' : 'text-xl',
          delta !== undefined && (delta >= 0 ? 'text-bull' : 'text-bear'),
        )}
      >
        {value}
      </p>
      {hint && <p className="mt-0.5 text-[11px] text-ink-4">{hint}</p>}
    </Card>
  )
}
