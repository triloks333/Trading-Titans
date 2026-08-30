import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CircleAlert, CircleCheck, Loader2 } from 'lucide-react'
import { fetchChargeConfig } from '@/lib/market'
import { calculateCharges, type InstrumentType } from '@/lib/charges'
import { placeOrder, type OrderSide } from '@/lib/orders'
import { instrumentMoney, money, currencyFor, cn } from '@/lib/format'
import { useAuth } from '@/lib/auth'
import { Button, Input, Label, Badge } from '@/components/ui'

export interface OrderTarget {
  symbol: string
  name: string
  market: string
  instrumentType: InstrumentType
  price: number
  /** Contract size. 1 for cash. */
  lotSize: number
  optionType?: string | null
  strikePrice?: number | null
  expiryDate?: string | null
}

/**
 * Order entry.
 *
 * The web app previously had no way to place an order at all — the Trade screen
 * listed instruments and drew a chart, and that was the end of it. Everything a
 * trade actually costs is decided server-side; this collects the intent, shows an
 * estimate, and posts it.
 */
export function OrderTicket({
  target,
  isExit = false,
  onDone,
}: {
  target: OrderTarget
  isExit?: boolean
  onDone?: () => void
}) {
  const { profile, refreshProfile } = useAuth()
  const queryClient = useQueryClient()

  const [side, setSide] = useState<OrderSide>('buy')
  const [isMarket, setIsMarket] = useState(true)
  const [lots, setLots] = useState('1')
  const [limitText, setLimitText] = useState(target.price.toFixed(2))
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null)

  const chargeConfig = useQuery({
    queryKey: ['chargeConfig'],
    queryFn: fetchChargeConfig,
    staleTime: 60 * 60_000,
  })

  const isFo = target.instrumentType !== 'EQUITY'
  const lotSize = isFo ? Math.max(1, target.lotSize) : 1
  const lotsNum = Number(lots)
  // Units are what the engine trades in. For F&O the user picks LOTS, so this is
  // the one multiplication that must not be got wrong — a missing lot size would
  // place an order for 1 unit instead of a 65-unit NIFTY contract, or the reverse.
  const quantity = Number.isFinite(lotsNum) && lotsNum > 0 ? Math.floor(lotsNum) * lotSize : 0

  const limitNum = Number(limitText)
  const priceUsed = isMarket ? target.price : Number.isFinite(limitNum) ? limitNum : 0

  const charges = useMemo(
    () =>
      calculateCharges({
        instrumentType: target.instrumentType,
        side,
        quantity,
        price: priceUsed,
        market: target.market,
        config: chargeConfig.data?.config ?? null,
      }),
    [target.instrumentType, target.market, side, quantity, priceUsed, chargeConfig.data],
  )

  const currency = currencyFor(target.market)
  const tradeValue = priceUsed * quantity

  /*
   * The rupee cost, which is what the wallet is measured in.
   *
   * A US instrument is priced in dollars while the wallet holds rupees, so a
   * dollar trade value cannot be compared against the balance directly. The
   * engine converts once at fill and records the rate; here the balance check is
   * simply skipped for US orders rather than compared across currencies, because a
   * wrong "insufficient funds" warning on a perfectly affordable trade is worse
   * than leaving the server to say so.
   */
  const wallet = profile?.wallet_balance ?? 0
  // A derivative blocks margin (15%) rather than the full notional; a long option
  // is paid for in full. Mirrors the engine's marginPct.
  const isLongOption = target.instrumentType === 'OPTION' && side === 'buy'
  const capitalNeeded = isFo && !isLongOption ? tradeValue * 0.15 : tradeValue
  const costInr = currency === 'INR' ? capitalNeeded + charges.totalCharges : null
  const shortOfFunds =
    !isExit && side === 'buy' && costInr != null && costInr > wallet && quantity > 0

  const submit = useMutation({
    mutationFn: () =>
      placeOrder({
        symbol: target.symbol,
        market: target.market,
        side,
        instrumentType: target.instrumentType,
        quantity,
        isMarket,
        price: isMarket ? undefined : limitNum,
        isExitOrder: isExit,
        optionType: (target.optionType as 'CE' | 'PE' | null) ?? null,
        strikePrice: target.strikePrice ?? null,
        expiryDate: target.expiryDate ?? null,
      }),
    onSuccess: (r) => {
      setResult(r)
      if (r.ok) {
        // Refresh everything a fill touches, so the user does not have to reload
        // to see their money move.
        void refreshProfile()
        void queryClient.invalidateQueries({ queryKey: ['orders'] })
        void queryClient.invalidateQueries({ queryKey: ['recentOrders'] })
        void queryClient.invalidateQueries({ queryKey: ['holdings'] })
        void queryClient.invalidateQueries({ queryKey: ['foPositions'] })
        void queryClient.invalidateQueries({ queryKey: ['todayActivity'] })
        onDone?.()
      }
    },
  })

  const canSubmit =
    quantity > 0 && priceUsed > 0 && !submit.isPending && !shortOfFunds

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-bold text-ink">{target.name}</p>
          <p className="text-[11px] text-ink-4">
            {target.symbol}
            {isFo && ` · lot ${lotSize}`}
          </p>
        </div>
        <p className="tnum shrink-0 text-lg font-extrabold text-ink">
          {instrumentMoney(target.price, target.market, 2)}
        </p>
      </div>

      {/* Buy / Sell. Coloured, because picking the wrong one costs real balance. */}
      <div className="grid grid-cols-2 gap-2">
        {(['buy', 'sell'] as const).map((s) => (
          <button
            key={s}
            onClick={() => setSide(s)}
            className={cn(
              'h-10 rounded-md text-sm font-bold transition-colors',
              side === s
                ? s === 'buy'
                  ? 'bg-bull text-white'
                  : 'bg-bear text-white'
                : 'bg-cream text-ink-4 hover:text-ink',
            )}
          >
            {s.toUpperCase()}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <Label>{isFo ? 'Lots' : 'Quantity'}</Label>
          <Input
            type="number"
            min="1"
            step="1"
            value={lots}
            onChange={(e) => setLots(e.target.value)}
          />
          {isFo && quantity > 0 && (
            <p className="mt-1 text-[11px] text-ink-4">{quantity} units</p>
          )}
        </div>
        <div>
          <Label>Order type</Label>
          <div className="flex h-11 gap-1.5">
            {([true, false] as const).map((m) => (
              <button
                key={String(m)}
                onClick={() => setIsMarket(m)}
                className={cn(
                  'flex-1 rounded-md text-xs font-semibold transition-colors',
                  isMarket === m ? 'bg-ink text-white' : 'bg-cream text-ink-4 hover:text-ink',
                )}
              >
                {m ? 'Market' : 'Limit'}
              </button>
            ))}
          </div>
        </div>
      </div>

      {!isMarket && (
        <div>
          <Label>Limit price</Label>
          <Input
            type="number"
            step="0.05"
            value={limitText}
            onChange={(e) => setLimitText(e.target.value)}
          />
          <p className="mt-1 text-[11px] text-ink-4">
            A resting limit order fills AT your price, not at whatever the market
            prints when it triggers.
          </p>
        </div>
      )}

      {/* Cost breakdown. Charges are an estimate; the engine recomputes at fill. */}
      <div className="space-y-1.5 rounded-md border border-birch bg-parchment px-4 py-3 text-xs">
        <Row label="Trade value" value={instrumentMoney(tradeValue, target.market, 2)} />
        {isFo && !isLongOption && (
          <Row
            label="Margin blocked (15%)"
            value={instrumentMoney(capitalNeeded, target.market, 2)}
          />
        )}
        <Row
          label="Charges (est.)"
          value={charges.totalCharges > 0 ? money(charges.totalCharges, 2) : '—'}
        />
        {charges.totalCharges > 0 && (
          <div className="pl-3 text-[11px] text-ink-4">
            <Row label="Brokerage" value={money(charges.brokerage, 2)} muted />
            <Row label="STT" value={money(charges.stt, 2)} muted />
            <Row label="Stamp duty" value={money(charges.stampDuty, 2)} muted />
            <Row label="Exchange + GST + fees" value={money(charges.exchange + charges.gst + charges.clearing + charges.sebi + charges.turnover, 2)} muted />
            {charges.dp > 0 && <Row label="DP charge" value={money(charges.dp, 2)} muted />}
          </div>
        )}
        <div className="mt-1 border-t border-birch pt-1.5">
          <Row
            label={side === 'buy' ? 'Approx. debit' : 'Approx. credit'}
            value={
              costInr != null
                ? money(
                    side === 'buy'
                      ? capitalNeeded + charges.totalCharges
                      : capitalNeeded - charges.totalCharges,
                    2,
                  )
                : `${instrumentMoney(capitalNeeded, target.market, 2)} + fees`
            }
            bold
          />
        </div>
        {currency !== 'INR' && (
          <p className="pt-1 text-[11px] leading-relaxed text-ink-4">
            Priced in dollars. The rupee amount is fixed at the exchange rate when
            the order fills, and recorded on the trade.
          </p>
        )}
      </div>

      {shortOfFunds && (
        <Note tone="bad">
          Not enough balance. You have {money(wallet, 2)} and this needs about{' '}
          {money(costInr ?? 0, 2)}.
        </Note>
      )}

      {result && (
        <Note tone={result.ok ? 'good' : 'bad'}>{result.message}</Note>
      )}

      <Button
        variant={side === 'buy' ? 'bull' : 'bear'}
        size="lg"
        className="w-full"
        disabled={!canSubmit}
        onClick={() => {
          setResult(null)
          submit.mutate()
        }}
      >
        {submit.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
        {isExit ? 'Close position' : side === 'buy' ? 'Place buy order' : 'Place sell order'}
      </Button>

      <p className="text-center text-[10px] leading-relaxed text-ink-5">
        Simulated trading with virtual money. Charges shown are an estimate; the
        exact figure is calculated when the order fills.
      </p>
    </div>
  )
}

function Row({
  label,
  value,
  bold,
  muted,
}: {
  label: string
  value: string
  bold?: boolean
  muted?: boolean
}) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className={muted ? 'text-ink-4' : 'text-ink-3'}>{label}</span>
      <span className={cn('tnum', bold ? 'font-bold text-ink' : muted ? 'text-ink-4' : 'text-ink')}>
        {value}
      </span>
    </div>
  )
}

function Note({ tone, children }: { tone: 'good' | 'bad'; children: React.ReactNode }) {
  return (
    <div
      className={cn(
        'flex items-start gap-2 rounded-md px-3 py-2.5 text-xs leading-relaxed',
        tone === 'good' ? 'bg-bull-light text-bull' : 'bg-bear-light text-bear',
      )}
    >
      {tone === 'good' ? (
        <CircleCheck className="mt-0.5 h-3.5 w-3.5 shrink-0" />
      ) : (
        <CircleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
      )}
      <span>{children}</span>
    </div>
  )
}

/** Small badge for a market's session state, used beside the ticket header. */
export function MarketBadge({ market }: { market: string }) {
  return <Badge tone="neutral">{market.replace('_', ' ').toUpperCase()}</Badge>
}
