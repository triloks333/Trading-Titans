import { useQuery } from '@tanstack/react-query'
import {
  Flag,
  CandlestickChart,
  UserPlus,
  Crown,
  Gift,
  Unlock,
  Receipt,
  ReceiptText,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { money, signedMoney, shortDate, cn } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { Card, CardHeader, EmptyState, Skeleton } from '@/components/ui'
import type { WalletTransaction } from '@/lib/types'

/*
 * Reads public.wallet_transactions — the append-only ledger fed by a trigger that
 * observes profiles.wallet_balance. Every balance movement is recorded there
 * regardless of which code path caused it.
 *
 * The `kind` column has no CHECK constraint on purpose, so that no statement line
 * is ever dropped for carrying a label this build has not seen. `describe` below
 * therefore has to degrade gracefully rather than throw.
 */
function describe(kind: string | null, amount: number, description: string | null) {
  const desc = description?.trim() ? description : null
  const credit = amount >= 0

  switch (kind) {
    case 'opening':
      return { label: desc ?? 'Opening balance', icon: <Flag className="h-4 w-4" /> }
    case 'trade':
      return {
        label: desc ?? (credit ? 'Trade proceeds' : 'Trade cost'),
        icon: <CandlestickChart className="h-4 w-4" />,
      }
    case 'referral':
      return { label: desc ?? 'Referral bonus', icon: <UserPlus className="h-4 w-4" /> }
    case 'plan':
      return { label: desc ?? 'Plan credit', icon: <Crown className="h-4 w-4" /> }
    case 'credit':
      return { label: desc ?? 'Demo cash credited', icon: <Gift className="h-4 w-4" /> }
    // Written by convert_guest_account() via the app.wallet_reason hint, which
    // leaves description NULL — so this fallback is what the user actually reads.
    case 'conversion_bonus':
      return { label: desc ?? 'Permanent account bonus', icon: <Unlock className="h-4 w-4" /> }
    default:
      return {
        label: desc ?? (credit ? 'Credit' : 'Debit'),
        icon: <Receipt className="h-4 w-4" />,
      }
  }
}

export function WalletPage() {
  const { profile } = useAuth()

  const txns = useQuery({
    queryKey: ['walletTransactions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('wallet_transactions')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []) as WalletTransaction[]
    },
  })

  const credits = (txns.data ?? []).filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0)
  const debits = (txns.data ?? []).filter((t) => t.amount < 0).reduce((s, t) => s + t.amount, 0)

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-3">
        <Card className="px-5 py-4">
          <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">
            Wallet balance
          </p>
          <p className="tnum mt-1.5 text-[26px] font-extrabold text-ink">
            {money(profile?.wallet_balance, 2)}
          </p>
          <p className="mt-0.5 text-[11px] text-ink-4">Available to trade</p>
        </Card>
        <Card className="px-5 py-4">
          <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">
            Credited in
          </p>
          <p className="tnum mt-1.5 text-xl font-extrabold text-bull">{money(credits, 2)}</p>
          <p className="mt-0.5 text-[11px] text-ink-4">Last 100 entries</p>
        </Card>
        <Card className="px-5 py-4">
          <p className="text-[11px] font-medium uppercase tracking-wide text-ink-4">
            Spent out
          </p>
          <p className="tnum mt-1.5 text-xl font-extrabold text-bear">
            {money(Math.abs(debits), 2)}
          </p>
          <p className="mt-0.5 text-[11px] text-ink-4">Last 100 entries</p>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="Wallet activity"
          subtitle="Every movement of demo cash, newest first"
        />
        {txns.isLoading ? (
          <div className="space-y-3 p-5">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full" />
            ))}
          </div>
        ) : (txns.data ?? []).length === 0 ? (
          <EmptyState
            icon={<ReceiptText className="h-5 w-5" />}
            title="No wallet activity yet"
            message="Rewards, referral bonuses and the cash impact of your trades will appear here."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-birch text-left text-[11px] uppercase tracking-wide text-ink-4">
                  <th className="px-5 py-2.5 font-medium">Activity</th>
                  <th className="px-3 py-2.5 font-medium">Date</th>
                  <th className="px-3 py-2.5 text-right font-medium">Amount</th>
                  <th className="px-5 py-2.5 text-right font-medium">Balance</th>
                </tr>
              </thead>
              <tbody>
                {(txns.data ?? []).map((t) => {
                  const { label, icon } = describe(t.kind, t.amount, t.description)
                  const credit = t.amount >= 0
                  return (
                    <tr key={t.id} className="border-b border-birch/60 last:border-0">
                      <td className="px-5 py-3">
                        <div className="flex items-center gap-3">
                          <span
                            className={cn(
                              'flex h-8 w-8 shrink-0 items-center justify-center rounded-lg',
                              credit ? 'bg-bull-light text-bull' : 'bg-bear-light text-bear',
                            )}
                          >
                            {icon}
                          </span>
                          <span className="font-medium text-ink">{label}</span>
                        </div>
                      </td>
                      <td className="px-3 py-3 text-xs text-ink-4">
                        {shortDate(t.created_at)}
                      </td>
                      <td
                        className={cn(
                          'tnum px-3 py-3 text-right font-semibold',
                          credit ? 'text-bull' : 'text-bear',
                        )}
                      >
                        {signedMoney(t.amount)}
                      </td>
                      <td className="tnum px-5 py-3 text-right text-ink-3">
                        {money(t.balance_after, 2)}
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
