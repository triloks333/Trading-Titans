import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Briefcase, Layers, ScrollText, TriangleAlert } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { fetchAllQuotes, fetchTodayActivity, fetchUsdInr } from '@/lib/market'
import {
  money,
  signedMoney,
  instrumentMoney,
  signedInstrumentMoney,
  percent,
  shortDate,
  timeAgo,
  cn,
} from '@/lib/format'
import { buildPositions, totalsOf, type Position } from '@/lib/positions'
import { useAuth } from '@/lib/auth'
import { Badge, Card, Delta, EmptyState, Skeleton } from '@/components/ui'
import type { Order } from '@/lib/types'

type Tab = 'holdings' | 'fo' | 'orders'

export function Portfolio() {
  const { profile } = useAuth()
  const [tab, setTab] = useState<Tab>('holdings')

  const holdings = useQuery({
    queryKey: ['holdings'],
    queryFn: async () => {
      const { data, error } = await supabase.from('holdings').select('*')
      if (error) throw error
      return data ?? []
    },
  })

  // Open F&O only. A settled position is history, not a position.
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

  // Only needed to fold US positions into the rupee total. Refetched rarely: the
  // rate moves in paise and a stale one would misstate a portfolio total.
  const usdInr = useQuery({
    queryKey: ['usdInr'],
    queryFn: fetchUsdInr,
    staleTime: 5 * 60_000,
  })

  const orders = useQuery({
    queryKey: ['orders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as Order[]
    },
  })

  const loading =
    holdings.isLoading || foPositions.isLoading || quotes.isLoading || today.isLoading

  const positions = buildPositions({
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    holdings: (holdings.data ?? []) as any,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    foPositions: (foPositions.data ?? []) as any,
    quotes: quotes.data ?? [],
    today: today.data ?? new Map(),
    usdInr: usdInr.data ?? 0,
  })

  const cash = positions.filter((p) => p.kind !== 'FUTURE' && p.kind !== 'OPTION')
  const derivatives = positions.filter((p) => p.kind === 'FUTURE' || p.kind === 'OPTION')
  const totals = totalsOf(positions)

  /*
   * Realised P&L comes from the profile aggregate the engine maintains.
   *
   * Worth being precise about what it is, because it is the one figure here that
   * is not computed on this page: the engine credits it as
   * `total_realized_pnl + realizedPnl - totalCharges`, so it is net of the
   * charges on each CLOSING order but not of the charges paid on the opening one.
   * Labelled accordingly rather than presented as a clean net figure.
   */
  const realised = profile?.total_realized_pnl ?? 0

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <Tile label="Current value" value={money(totals.valueInr, 2)} emphasis />
        <Tile label="Capital deployed" value={money(totals.investedInr, 2)} />
        <Tile
          label="Today's P&L"
          value={signedMoney(totals.dayPnlInr, 2)}
          delta={totals.dayPnlInr}
        />
        <Tile
          label="Unrealised P&L"
          value={signedMoney(totals.pnlInr, 2)}
          delta={totals.pnlInr}
          hint={totals.investedInr > 0 ? percent(totals.pnlPct) : undefined}
        />
        <Tile
          label="Realised P&L"
          value={signedMoney(realised, 2)}
          delta={realised}
          hint="Booked, net of exit charges"
        />
      </div>

      {totals.partial && (
        <div className="flex items-start gap-2.5 rounded-xl border border-birch bg-brand-pale/40 px-4 py-3">
          <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-brand-deep" />
          <p className="text-xs leading-relaxed text-ink-3">
            The USD/INR rate could not be fetched, so US positions are missing from
            the rupee totals above. Their own dollar figures below are unaffected.
          </p>
        </div>
      )}

      <Card>
        <div className="flex gap-1 border-b border-birch px-5 pt-4">
          {(
            [
              ['holdings', `Holdings (${cash.length})`],
              ['fo', `F&O (${derivatives.length})`],
              ['orders', `Orders (${orders.data?.length ?? 0})`],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={cn(
                'rounded-t-md px-4 py-2.5 text-[13px] font-semibold transition-colors',
                tab === id ? 'border-b-2 border-brand text-ink' : 'text-ink-4 hover:text-ink',
              )}
            >
              {label}
            </button>
          ))}
        </div>

        {tab === 'holdings' &&
          (loading ? (
            <Loading rows={5} />
          ) : cash.length === 0 ? (
            <EmptyState
              icon={<Briefcase className="h-5 w-5" />}
              title="No holdings"
              message="Once you buy or short something it appears here, marked to the latest price."
            />
          ) : (
            <PositionTable positions={cash} />
          ))}

        {tab === 'fo' &&
          (loading ? (
            <Loading rows={3} />
          ) : derivatives.length === 0 ? (
            <EmptyState
              icon={<Layers className="h-5 w-5" />}
              title="No open F&O positions"
              message="Futures and options you hold appear here until they are closed or expire."
            />
          ) : (
            <PositionTable positions={derivatives} showLots />
          ))}

        {tab === 'orders' &&
          (orders.isLoading ? (
            <Loading rows={6} />
          ) : (orders.data ?? []).length === 0 ? (
            <EmptyState
              icon={<ScrollText className="h-5 w-5" />}
              title="No orders"
              message="Placed, pending, executed and cancelled orders all show up here."
            />
          ) : (
            <OrderTable orders={orders.data ?? []} />
          ))}
      </Card>
    </div>
  )
}

function Loading({ rows }: { rows: number }) {
  return (
    <div className="space-y-3 p-5">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-11 w-full" />
      ))}
    </div>
  )
}

function PositionTable({
  positions,
  showLots = false,
}: {
  positions: Position[]
  showLots?: boolean
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
            <th className="px-5 py-2.5 font-medium">Instrument</th>
            <th className="px-3 py-2.5 text-right font-medium">{showLots ? 'Lots' : 'Qty'}</th>
            <th className="px-3 py-2.5 text-right font-medium">Avg</th>
            <th className="px-3 py-2.5 text-right font-medium">LTP</th>
            <th className="px-3 py-2.5 text-right font-medium">Capital</th>
            <th className="px-3 py-2.5 text-right font-medium">Value</th>
            <th className="px-3 py-2.5 text-right font-medium">Day P&L</th>
            <th className="px-5 py-2.5 text-right font-medium">P&L</th>
          </tr>
        </thead>
        <tbody>
          {positions.map((p) => (
            <tr key={p.key} className="border-b border-birch/60 last:border-0">
              <td className="px-5 py-3">
                <div className="flex items-center gap-2">
                  <p className="font-semibold text-ink">{p.label}</p>
                  {/* A short is materially different from a long and must never
                      be mistaken for one — it was invisible here before. */}
                  {p.isShort && <Badge tone="bear">SHORT</Badge>}
                  {p.currency === 'USD' && <Badge tone="neutral">USD</Badge>}
                </div>
                <p className="text-[11px] text-ink-4">
                  {showLots && p.units !== p.quantity
                    ? `${Math.abs(p.units)} units${p.expiryDate ? ` · expires ${shortDate(p.expiryDate)}` : ''}`
                    : `Since ${shortDate(p.createdAt)}`}
                </p>
              </td>
              <td className="tnum px-3 py-3 text-right text-ink-3">{p.quantity}</td>
              <td className="tnum px-3 py-3 text-right text-ink-3">
                {instrumentMoney(p.displayAvgPrice, p.market, 2)}
              </td>
              <td className="tnum px-3 py-3 text-right text-ink">
                {instrumentMoney(p.displayLtp, p.market, 2)}
              </td>
              <td className="tnum px-3 py-3 text-right text-ink-3">
                {instrumentMoney(p.displayInvested, p.market, 2)}
              </td>
              <td className="tnum px-3 py-3 text-right font-semibold text-ink">
                {instrumentMoney(p.displayValue, p.market, 2)}
              </td>
              <td className="px-3 py-3 text-right">
                {/* F&O day P&L needs yesterday's modelled premium, which needs
                    yesterday's spot. Shown as a dash rather than a false zero. */}
                {p.kind === 'FUTURE' || p.kind === 'OPTION' ? (
                  <span className="text-ink-5">—</span>
                ) : (
                  <Delta value={p.displayDayPnl}>
                    {signedInstrumentMoney(p.displayDayPnl, p.market, 2)}
                  </Delta>
                )}
              </td>
              <td className="px-5 py-3 text-right">
                <Delta value={p.displayPnl}>
                  {signedInstrumentMoney(p.displayPnl, p.market, 2)}
                </Delta>
                <p className={cn('text-[11px]', p.displayPnl >= 0 ? 'text-bull' : 'text-bear')}>
                  {percent(p.displayPnlPct)}
                </p>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function OrderTable({ orders }: { orders: Order[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
            <th className="px-5 py-2.5 font-medium">Side</th>
            <th className="px-3 py-2.5 font-medium">Symbol</th>
            <th className="px-3 py-2.5 text-right font-medium">Qty</th>
            <th className="px-3 py-2.5 text-right font-medium">Price</th>
            <th className="px-3 py-2.5 text-right font-medium">Charges</th>
            <th className="px-3 py-2.5 text-right font-medium">Net P&L</th>
            <th className="px-3 py-2.5 font-medium">Status</th>
            <th className="px-5 py-2.5 text-right font-medium">Placed</th>
          </tr>
        </thead>
        <tbody>
          {orders.map((o) => {
            // Net, not gross. `realized_pnl` is stored before charges; the
            // portfolio nets them, and showing the raw column here is what made
            // the two disagree on mobile.
            const gross = o.realized_pnl ?? 0
            const charges = o.total_charges ?? 0
            const net = gross - charges
            return (
              <tr key={o.id} className="border-b border-birch/60 last:border-0">
                <td className="px-5 py-3">
                  <Badge tone={o.side === 'buy' ? 'bull' : 'bear'}>
                    {o.side.toUpperCase()}
                  </Badge>
                </td>
                <td className="px-3 py-3 font-semibold text-ink">{o.symbol}</td>
                <td className="tnum px-3 py-3 text-right text-ink-3">{o.quantity}</td>
                <td className="tnum px-3 py-3 text-right text-ink-3">
                  {instrumentMoney(o.price ?? 0, o.market, 2)}
                </td>
                <td className="tnum px-3 py-3 text-right text-ink-3">
                  {charges > 0 ? money(charges, 2) : '—'}
                </td>
                <td className="px-3 py-3 text-right">
                  {gross === 0 && charges === 0 ? (
                    <span className="text-ink-5">—</span>
                  ) : (
                    <Delta value={net}>{signedMoney(net, 2)}</Delta>
                  )}
                </td>
                <td className="px-3 py-3">
                  <Badge
                    tone={
                      o.status === 'executed'
                        ? 'neutral'
                        : o.status === 'cancelled' || o.status === 'failed'
                          ? 'bear'
                          : 'brand'
                    }
                  >
                    {o.status}
                  </Badge>
                </td>
                <td className="px-5 py-3 text-right text-xs text-ink-4">
                  {timeAgo(o.created_at)}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function Tile({
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
          'tnum mt-1.5 font-extrabold',
          emphasis ? 'text-[26px]' : 'text-xl',
          delta === undefined ? 'text-ink' : delta >= 0 ? 'text-bull' : 'text-bear',
        )}
      >
        {value}
      </p>
      {hint && <p className="mt-0.5 text-[11px] text-ink-4">{hint}</p>}
    </Card>
  )
}
