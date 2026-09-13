/// Changes the quantity and/or limit price of a resting order.
///
/// Replaces a direct client PATCH of `orders`. The old RLS policy
/// (`USING (auth_uid() = user_id)`, no WITH CHECK, no column restriction) meant
/// modifying an order and rewriting `realized_pnl` were the same privilege, so
/// the only way to keep the first is to move it here and withdraw the grant.
///
/// The decision rules live in ../_shared/order_edit.ts so they can be unit
/// tested without booting this function. What stays here is I/O: authenticate,
/// read the row, look up the position when the edit needs it, write.
///
/// NOT changed by this endpoint: the trigger comparison, the fill-price rule, or
/// anything the execution engine does. It only edits a pending row's own fields.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { authoriseEdit, type EditableOrder, resolveEdit } from "../_shared/order_edit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const SELECT_COLS =
  "id, user_id, status, order_type, side, quantity, price, is_exit, instrument_type, symbol, market";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  const pre = handleCors(req);
  if (pre) return pre;

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing Authorization" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Invalid token" }, 401);
    const userId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const orderId = typeof body.orderId === "string" ? body.orderId.trim() : "";
    if (!orderId) return json({ error: "orderId required" }, 400);

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Same budget as place-order: editing repeatedly is as expensive as placing.
    try {
      const { data: allowed } = await supabase.rpc("check_rate_limit", {
        p_key: `modify-order:${userId}`, p_max: 30, p_window_seconds: 60,
      });
      if (allowed === false) {
        return json({ error: "Too many changes in a short time. Please wait a moment." }, 429);
      }
    } catch (_) { /* fail open, as place-order does */ }

    const { data: row } = await supabase
      .from("orders").select(SELECT_COLS).eq("id", orderId).maybeSingle();

    const auth = authoriseEdit((row as EditableOrder | null) ?? null, userId);
    if (!auth.ok) return json({ error: auth.error }, auth.status);
    const order = row as EditableOrder & { symbol: string; market: string };

    // Only an exit is clamped, so only an exit pays for the position lookup.
    // Equity and crypto live in `holdings`; derivatives in `fo_positions`.
    let held = 0;
    if (order.is_exit === true && order.side === "sell") {
      const itype = order.instrument_type ?? "EQUITY";
      if (itype === "FUTURE" || itype === "OPTION") {
        const { data } = await supabase
          .from("fo_positions").select("net_qty")
          .eq("user_id", userId).eq("symbol", order.symbol).maybeSingle();
        held = Math.abs(Number(data?.net_qty ?? 0));
      } else {
        const { data } = await supabase
          .from("holdings").select("quantity")
          .eq("user_id", userId).eq("symbol", order.symbol).eq("market", order.market)
          .maybeSingle();
        held = Math.abs(Number(data?.quantity ?? 0));
      }
    }

    const decision = resolveEdit(
      order,
      {
        quantity: body.quantity != null ? Number(body.quantity) : null,
        price: body.price != null ? Number(body.price) : null,
      },
      held,
    );
    if (!decision.ok) return json({ error: decision.error }, decision.status);
    const next = decision.value;

    // CAS on `status = 'pending'` again: the row was pending when read, but the
    // engine may have claimed it since.
    const { data: updated, error } = await supabase
      .from("orders")
      .update({
        quantity: next.quantity,
        price: next.price,
        limit_price: next.limitPrice,
        total: next.total,
      })
      .eq("id", orderId)
      .eq("user_id", userId)
      .eq("status", "pending")
      .select("id, quantity, price, limit_price, total, status");

    if (error) return json({ error: error.message }, 500);
    if (!updated || updated.length === 0) {
      return json({ error: "That order is no longer pending — it may have just been filled." }, 409);
    }

    return json({ ok: true, order: updated[0], message: "Order updated." });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
