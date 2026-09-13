import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Search, ArrowLeftRight, Loader2 } from 'lucide-react'
import {
  fetchAllQuotes,
  fetchQuotes,
  searchInstruments,
  type SearchHit,
  type SearchMarket,
} from '@/lib/market'
import { instrumentMoney, signedInstrumentMoney, percent, shortDate, cn } from '@/lib/format'
import { Card, CardHeader, Delta, EmptyState, Input, Skeleton, Badge } from '@/components/ui'
import { CandleChart } from '@/components/CandleChart'
import { OrderTicket, type OrderTarget } from '@/components/OrderTicket'
import { underlyingOf } from '@/lib/positions'

const MARKETS: { id: SearchMarket; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'stock', label: 'India' },
  { id: 'us_stock', label: 'US' },
  { id: 'crypto', label: 'Crypto' },
]

/** Debounce, so typing does not fire a search request per keystroke. */
function useDebounced<T>(value: T, ms: number): T {
  const [out, setOut] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setOut(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return out
}

/**
 * Trade: instrument list on the left, detail plus chart plus order ticket on the
 * right. On a phone these are three separate screens with navigation between them;
 * the point of the wider viewport is being able to see the price, the chart and
 * the ticket at the same time.
 */
export function Trade() {
  const [query, setQuery] = useState('')
  const [market, setMarket] = useState<SearchMarket>('all')
  const [selected, setSelected] = useState<SearchHit | null>(null)
  const debouncedQuery = useDebounced(query.trim(), 250)

  // With no search term, show the quote cache — the symbols this user holds,
  // watches or has orders on, plus the popular list. That is a sensible default
  // list AND the only place index prices live.
  const cached = useQuery({
    queryKey: ['allQuotes'],
    queryFn: fetchAllQuotes,
    refetchInterval: 20_000,
  })

  const searched = useQuery({
    queryKey: ['search', debouncedQuery, market],
    queryFn: () => searchInstruments(debouncedQuery, market),
    enabled: debouncedQuery.length >= 2,
  })

  const browsing: SearchHit[] = useMemo(
    () =>
      (cached.data ?? [])
        .filter((q) => market === 'all' || (q.market ?? 'stock') === market)
        .map((q) => ({
          symbol: q.symbol,
          name: q.name?.trim() || q.symbol,
          market: q.market ?? 'stock',
          instrumentType: 'EQUITY' as const,
          expiryDate: null,
          strikePrice: null,
          optionType: null,
          lotSize: 1,
          price: q.price,
          changePct: q.change_pct ?? undefined,
        })),
    [cached.data, market],
  )

  const isSearching = debouncedQuery.length >= 2
  const list = isSearching ? (searched.data ?? []) : browsing
  const active = selected ?? list[0] ?? null

  /*
   * A searched instrument arrives without a price — market-search reads the
   * contract master, which has no prices in it. So the selected one gets a live
   * quote of its own.
   *
   * For a derivative the quote is of the UNDERLYING, because there is no live
   * options feed: the premium is modelled from the spot, exactly as the fill
   * engine does it.
   */
  const quoteSymbol = active
    ? active.instrumentType === 'EQUITY'
      ? active.symbol
      : underlyingOf(active.symbol)
    : ''
  const quoteMarket = active?.instrumentType === 'EQUITY' ? (active?.market ?? 'stock') : 'stock'

  const liveQuote = useQuery({
    queryKey: ['quote', quoteSymbol, quoteMarket],
    queryFn: async () => (await fetchQuotes([quoteSymbol]))[0] ?? null,
    enabled: quoteSymbol.length > 0,
    refetchInterval: 20_000,
  })

  const spot = liveQuote.data?.price ?? active?.price ?? 0

  const target: OrderTarget | null = active
    ? {
        symbol: active.symbol,
        name: active.name,
        market: active.market,
        instrumentType: active.instrumentType,
        price: spot,
        lotSize: active.lotSize,
        optionType: active.optionType,
        strikePrice: active.strikePrice,
        expiryDate: active.expiryDate,
      }
    : null

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(300px,340px)_1fr]">
      <Card className="flex max-h-[calc(100vh-7.5rem)] flex-col overflow-hidden">
        <div className="border-b border-birch p-4">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-5" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search any stock, future, option or coin…"
              className="pl-9"
            />
            {searched.isFetching && (
              <Loader2 className="absolute right-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-ink-5" />
            )}
          </div>
          <div className="mt-3 flex gap-1.5">
            {MARKETS.map((m) => (
              <button
                key={m.id}
                onClick={() => setMarket(m.id)}
                className={cn(
                  'rounded-tag px-2.5 py-1 text-[11px] font-semibold transition-colors',
                  market === m.id ? 'bg-ink text-white' : 'bg-cream text-ink-4 hover:text-ink',
                )}
              >
                {m.label}
              </button>
            ))}
          </div>
          <p className="mt-2 text-[10px] text-ink-5">
            {isSearching
              ? `${list.length} match${list.length === 1 ? '' : 'es'} across the full NSE, US and crypto lists`
              : 'Your watchlist, holdings and popular names. Search to reach everything else.'}
          </p>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {(isSearching ? searched.isLoading : cached.isLoading) ? (
            <div className="space-y-2 p-4">
              {Array.from({ length: 10 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : list.length === 0 ? (
            <EmptyState
              icon={<Search className="h-5 w-5" />}
              title="Nothing found"
              message="No tradeable instrument matches that search in the selected market."
            />
          ) : (
            <ul>
              {list.map((h) => {
                const k = `${h.symbol}${h.expiryDate ?? ''}${h.strikePrice ?? ''}${h.optionType ?? ''}`
                const isActive =
                  active != null &&
                  active.symbol === h.symbol &&
                  active.expiryDate === h.expiryDate &&
                  active.strikePrice === h.strikePrice &&
                  active.optionType === h.optionType
                return (
                  <li key={k}>
                    <button
                      onClick={() => setSelected(h)}
                      className={cn(
                        'flex w-full items-center gap-3 border-b border-birch/60 px-4 py-3 text-left transition-colors',
                        isActive ? 'bg-brand-pale' : 'hover:bg-cream',
                      )}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          <p className="truncate text-[13px] font-bold text-ink">{h.symbol}</p>
                          {h.instrumentType !== 'EQUITY' && (
                            <Badge tone="violet">{h.instrumentType === 'FUTURE' ? 'FUT' : h.optionType ?? 'OPT'}</Badge>
                          )}
                        </div>
                        <p className="truncate text-[11px] text-ink-4">{h.name}</p>
                      </div>
                      <div className="shrink-0 text-right">
                        {h.price != null ? (
                          <>
                            <p className="tnum text-[13px] font-semibold text-ink">
                              {instrumentMoney(h.price, h.market, 2)}
                            </p>
                            <Delta value={h.changePct ?? 0} className="text-[11px]">
                              {percent(h.changePct ?? 0)}
                            </Delta>
                          </>
                        ) : (
                          <p className="text-[11px] text-ink-5">
                            {h.expiryDate ? shortDate(h.expiryDate) : 'tap for price'}
                          </p>
                        )}
                      </div>
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      </Card>

      {active && target ? (
        <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
          <div className="space-y-6">
            <Card className="px-6 py-5">
              <div className="flex flex-wrap items-end justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h1 className="text-xl font-extrabold text-ink">{active.symbol}</h1>
                    <Badge tone="neutral">{active.market.replace('_', ' ').toUpperCase()}</Badge>
                    {active.instrumentType !== 'EQUITY' && (
                      <Badge tone="violet">{active.instrumentType}</Badge>
                    )}
                  </div>
                  <p className="mt-0.5 text-xs text-ink-4">{active.name}</p>
                  {active.instrumentType !== 'EQUITY' && (
                    <p className="mt-1 text-[11px] text-ink-4">
                      Lot {active.lotSize}
                      {active.expiryDate && ` · expires ${shortDate(active.expiryDate)}`}
                      {active.strikePrice ? ` · strike ${active.strikePrice}` : ''}
                    </p>
                  )}
                </div>
                <div className="text-right">
                  <p className="tnum text-3xl font-extrabold text-ink">
                    {instrumentMoney(spot, quoteMarket, 2)}
                  </p>
                  {liveQuote.data && (
                    <Delta value={liveQuote.data.change_pct ?? 0} className="text-sm">
                      {signedInstrumentMoney(liveQuote.data.change ?? 0, quoteMarket, 2)} (
                      {percent(liveQuote.data.change_pct ?? 0)})
                    </Delta>
                  )}
                  {active.instrumentType !== 'EQUITY' && (
                    <p className="mt-0.5 text-[10px] text-ink-5">
                      Underlying spot ({quoteSymbol})
                    </p>
                  )}
                </div>
              </div>

              <dl className="mt-5 grid grid-cols-2 gap-4 border-t border-birch pt-4 sm:grid-cols-4">
                {(
                  [
                    ['Open', liveQuote.data?.open],
                    ['Prev. close', liveQuote.data?.previous_close],
                    ['Day low', liveQuote.data?.day_low],
                    ['Day high', liveQuote.data?.day_high],
                  ] as const
                ).map(([label, v]) => (
                  <div key={label}>
                    <dt className="text-[11px] uppercase tracking-wide text-ink-4">{label}</dt>
                    <dd className="tnum mt-0.5 text-sm font-semibold text-ink">
                      {v != null ? instrumentMoney(v, quoteMarket, 2) : '—'}
                    </dd>
                  </div>
                ))}
              </dl>
            </Card>

            <Card className="overflow-hidden">
              <CardHeader
                title="Price chart"
                subtitle={
                  active.instrumentType === 'EQUITY'
                    ? // Precise on purpose. The live bar comes from `quotes_cache`,
                      // which is what the engine fills at, but the historical bars
                      // are the vendor's and will not agree to the paisa. Claiming
                      // the whole chart is ours would be the wrong half to round.
                      'Live price from our own feed; history from the market'
                    : `Underlying ${quoteSymbol} — derivatives have no separate price feed`
                }
              />
              <CandleChart symbol={quoteSymbol} market={quoteMarket} />
            </Card>
          </div>

          <div>
            <Card className="px-5 py-5 xl:sticky xl:top-6">
              <OrderTicket target={target} />
            </Card>
          </div>
        </div>
      ) : (
        <Card>
          <EmptyState
            icon={<ArrowLeftRight className="h-5 w-5" />}
            title="Pick an instrument"
            message="Choose something from the list to see its price and chart, and to place an order."
          />
        </Card>
      )}
    </div>
  )
}
