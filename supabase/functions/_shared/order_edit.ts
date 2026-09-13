/// Authorisation and validation rules for editing or cancelling a resting order.
///
/// Lives here rather than inside the two edge functions so it can be tested
/// without booting them — same reasoning as fill_price.ts: those entrypoints call
/// `serve()` and read env vars at module scope, so importing one from a test
/// would start an HTTP server and reach the network.
///
/// BACKGROUND
/// Both clients used to PATCH `orders` directly. The RLS policy was
/// `USING (auth_uid() = user_id)` with no WITH CHECK and no column restriction,
/// so the documented API surface of the table let a signed-in user set ANY
/// column on their own rows — `realized_pnl`, `status`, `quantity`. No exploit
/// was needed. These functions plus the accompanying migration make the server
/// the only writer, and this module holds the decisions both of them make.

/// The subset of an order row these rules need.
export interface EditableOrder {
  id: string;
  user_id: string;
  status: string;
  order_type: string | null;
  side: string;
  quantity: number;
  price: number;
  is_exit: boolean | null;
  instrument_type: string | null;
}

export interface EditRequest {
  quantity?: number | null;
  price?: number | null;
}

export interface EditResult {
  quantity: number;
  price: number;
  /// NULL for a market order: it has no trigger to carry.
  limitPrice: number | null;
  total: number;
}

export type Decision<T> =
  | { ok: true; value: T }
  | { ok: false; status: number; error: string };

function deny(status: number, error: string): Decision<never> {
  return { ok: false, status, error };
}

/// Whether `userId` may edit or cancel `order` at all.
///
/// A row belonging to somebody else returns 404 rather than 403 on purpose: 403
/// would confirm that the id exists, which turns this endpoint into a probe for
/// other people's order ids.
export function authoriseEdit(
  order: EditableOrder | null,
  userId: string,
): Decision<EditableOrder> {
  if (!order) return deny(404, "Order not found.");
  if (order.user_id !== userId) return deny(404, "Order not found.");
  if (order.status !== "pending") {
    // Naming the real status is the difference between a user retrying forever
    // and understanding that the engine got there first.
    const reason = order.status === "executed"
      ? "That order has already been filled."
      : order.status === "cancelled"
      ? "That order was already cancelled."
      : order.status === "executing"
      ? "That order is being filled right now."
      : `That order is no longer pending (status: ${order.status}).`;
    return deny(409, reason);
  }
  return { ok: true, value: order };
}

/// Resolves the requested edit into the exact columns to write.
///
/// `positionQty` is the absolute size of the user's current position in this
/// instrument, and is only consulted for an EXIT order.
///
/// ponytail: the holdings cap is deliberately applied to exits ONLY, not to
/// every sell. A plain sell above holdings is a SHORT, which this product
/// supports on purpose — the engine has an EQ_SHORT_NEW path and blocks the
/// trade at fill time if the margin is not there. Capping all sells at holdings
/// would quietly delete short selling, which is a trading-logic change and not
/// what a security fix is for. An exit is different: it claims to be closing
/// something, so overshooting it is the oversell bug that left negative-quantity
/// holdings behind. The ceiling is that the cap uses the position as it stands
/// now, so a fill landing between this check and the write could still overshoot
/// slightly; the upgrade path is to re-check inside the execution engine, which
/// already clamps exits via exitNewNetQty.
export function resolveEdit(
  order: EditableOrder,
  requested: EditRequest,
  positionQty: number,
): Decision<EditResult> {
  const isLimit = order.order_type === "limit";

  let quantity = order.quantity;
  if (requested.quantity != null) {
    const q = Number(requested.quantity);
    if (!Number.isFinite(q) || q <= 0) {
      return deny(400, "Quantity must be greater than zero.");
    }
    quantity = q;
  }

  let price = order.price;
  if (requested.price != null) {
    if (!isLimit) {
      return deny(400, "A market order has no limit price to change.");
    }
    const p = Number(requested.price);
    if (!Number.isFinite(p) || p <= 0) {
      return deny(400, "Limit price must be greater than zero.");
    }
    price = p;
  }

  if (requested.quantity == null && requested.price == null) {
    return deny(400, "Nothing to change.");
  }

  if (order.is_exit === true && order.side === "sell") {
    const available = Math.abs(Number(positionQty) || 0);
    if (quantity > available + 1e-8) {
      return deny(
        400,
        available <= 0
          ? "You no longer hold this position, so there is nothing to exit."
          : `You can exit at most ${available} of this position.`,
      );
    }
  }

  return {
    ok: true,
    value: {
      quantity,
      price,
      // Kept in step with `price` because the engine reads the trigger as
      // `limit_price ?? price` and overwrites `price` with the fill price at
      // execution. Letting them drift is what made a correct engine look broken.
      limitPrice: isLimit ? price : null,
      // Recomputed server-side. The web client's old direct PATCH changed
      // quantity without touching `total`, leaving the stored order value stale.
      total: quantity * price,
    },
  };
}
