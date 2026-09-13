/// Cancels a resting order.
///
/// Exists because both clients used to PATCH `orders` directly, and the RLS
/// policy behind that (`USING (auth_uid() = user_id)`, no WITH CHECK, no column
/// restriction) let a signed-in user set ANY column on their own rows —
/// `realized_pnl`, `status`, `quantity`. Cancelling is the legitimate half of
/// that access; this endpoint provides it so the direct grant can be withdrawn.
///
/// The status transition is a compare-and-swap on `status = 'pending'`, matching
/// the execution engine's own `claim()`. That is what makes a cancel racing a
/// fill lose harmlessly instead of cancelling something already executed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { authoriseEdit, type EditableOrder } from "../_shared/order_edit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const SELECT_COLS =
  "id, user_id, status, order_type, side, quantity, price, is_exit, instrument_type";

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
    // Authenticate from the JWT. A body-supplied user id is never trusted, which
    // is what stops one account cancelling another's order.
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

    const { data: row } = await supabase
      .from("orders").select(SELECT_COLS).eq("id", orderId).maybeSingle();

    const auth = authoriseEdit((row as EditableOrder | null) ?? null, userId);
    if (!auth.ok) return json({ error: auth.error }, auth.status);

    // Compare-and-swap: only a still-pending row may be cancelled.
    const { data: updated, error } = await supabase
      .from("orders")
      .update({ status: "cancelled" })
      .eq("id", orderId)
      .eq("user_id", userId)
      .eq("status", "pending")
      .select("id, status");

    if (error) return json({ error: error.message }, 500);
    if (!updated || updated.length === 0) {
      return json({ error: "That order is no longer pending — it may have just been filled." }, 409);
    }

    return json({ ok: true, orderId, status: "cancelled", message: "Order cancelled." });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
