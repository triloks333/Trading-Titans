/// Which price a triggered limit order actually fills at.
///
/// Lives here rather than in execute-pending-orders/index.ts so it can be tested
/// without booting the function: that entrypoint calls `serve()` and reads env
/// vars at module scope, so importing it from a test would start an HTTP server
/// and reach the network.
///
/// BACKGROUND
/// The pending-order engine samples the market roughly once a minute, and it used
/// to book every limit fill at whatever price that poll happened to see. A sell
/// limit at 281 therefore filled at 281.4 — as if the stock had gapped over the
/// order, when in fact it traded straight through 281 and the poller simply was
/// not looking. The bonus was always in the user's favour, but its size was an
/// artifact of the polling interval rather than of anything the market did, and
/// the fill price disagreed with the price the user had asked for.
///
/// THE RULE
/// A limit order has two legitimate fill prices, and which one applies is fixed
/// at placement, not at trigger time:
///
///   - RESTING — the limit was away from the market when the order was placed.
///     The order sits in the book and is hit AT its limit as the price passes
///     through. Fill = limit.
///   - MARKETABLE — the limit was already at or through the market when placed.
///     The order crosses the spread immediately and earns real price improvement.
///     Fill = the polled price.
///
/// `refExec` is the pre-trade reference price stamped on the order at placement
/// (`orders.execution_reference_price`), already passed through the same
/// instrument pricing model as `polled` by the caller. That matters for
/// derivatives: the reference column stores the underlying spot, while the limit
/// is on the premium, so comparing them raw would misclassify every F&O order.

/// True when the order was resting at placement and so must fill at its limit.
///
/// ponytail: an opening gap is deliberately NOT modelled (Option A). A resting
/// sell limit at 281 on a stock that opens at 290 fills at 281, not 290, so the
/// user gives up the gap. The ceiling is fidelity on gap days; the upgrade path
/// is to fill at `quotes_cache.open` when the trigger fires on the session's
/// first poll. Chosen because a predictable fill at the requested price is worth
/// more here than modelling a rare case, and it never invents a phantom bonus.
export function isRestingLimit(
  side: string,
  orderType: string,
  limit: number,
  refExec: number | null,
): boolean {
  if (orderType !== "limit") return false; // market orders fill at the market
  // No usable reference, or a reference equal to the limit — place-order stamps
  // the limit itself as the reference when the pre-trade quote fetch fails, so
  // that case is "marketability unknown", not "marketable". Both fall back to
  // resting, which is the conservative read: the user gets exactly the price
  // they asked for and never a bonus the market did not hand out.
  if (refExec == null || !Number.isFinite(refExec) || refExec <= 0) return true;
  if (refExec === limit) return true;
  const marketable = side === "sell" ? refExec >= limit : refExec <= limit;
  return !marketable;
}

/// The price to book the fill at. Returns `polled` untouched for market orders
/// and for limit orders that were marketable at placement.
export function resolveFillPrice(
  side: string,
  orderType: string,
  limit: number,
  polled: number,
  refExec: number | null,
): number {
  return isRestingLimit(side, orderType, limit, refExec) ? limit : polled;
}
