import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { prefKeyFor } from "../_shared/notification_prefs.ts";

// Generic FCM push sender. Called by the `notifications` AFTER INSERT trigger
// (via pg_net) so EVERY in-app notification, from any source (edge functions,
// SQL crons, manual inserts), also reaches the phone system tray.
//
// Body: { user_id, title, body, action_type, action_data? }
//
// `action_data` is forwarded into the FCM `data` payload under the SAME key names
// the in-app call-to-action already uses (cta_route, cta_url, symbol, market), so
// the client can hand it straight to its existing route allow-list rather than
// translate between two routing contracts. Without this the tray push carried only
// `type` and tapping it could not know where to go.

const FCM_SA = Deno.env.get("FCM_SERVICE_ACCOUNT");

// Map a notifications.action_type to the app's Android channel + push data type
// (matches NotificationService._categoryFromType / channel ids).
function channelFor(t: string | null | undefined): { channel: string; type: string } {
  switch (t) {
    case "price_alert": return { channel: "price_alert_channel_v1", type: "price_alert" };
    case "order":
    case "order_executed":
    case "trade":
    case "expiry": return { channel: "order_executed_channel_v1", type: "order_executed" };
    case "order_pending": return { channel: "order_pending_channel_v1", type: "order_pending" };
    case "order_failed": return { channel: "order_failed_channel_v1", type: "order_failed" };
    case "reward": return { channel: "reward_channel_v1", type: "reward" };
    case "chat": return { channel: "chat_channel_v1", type: "chat" };
    default: return { channel: "broadcast_channel_v1", type: "broadcast" };
  }
}

let cachedToken: { token: string; exp: number } | null = null;
function b64url(bytes: Uint8Array): string {
  let bin = ""; for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  let s = btoa(bin).split("+").join("-").split("/").join("_"); while (s.endsWith("=")) s = s.slice(0, -1); return s;
}
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  let c = pem.split("-----BEGIN PRIVATE KEY-----").join("").split("-----END PRIVATE KEY-----").join("");
  c = c.split("\n").join("").split("\r").join("").split(" ").join("").split("\t").join("");
  const der = Uint8Array.from(atob(c), (x) => x.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der.buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}
// deno-lint-ignore no-explicit-any
async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = enc({ alg: "RS256", typ: "JWT" }) + "." + enc({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 });
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = unsigned + "." + b64url(new Uint8Array(sig));
  const res = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt });
  const j = await res.json();
  if (!j.access_token) throw new Error("FCM oauth failed: " + JSON.stringify(j));
  cachedToken = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cachedToken.token;
}

serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { /* ignore */ }
  const userId = String(body.user_id ?? "");
  const title = String(body.title ?? "").trim() || "Trading Titans";
  const msg = String(body.body ?? "").trim();
  const actionType = (body.action_type ?? null) as string | null;
  if (!userId) return new Response(JSON.stringify({ skipped: "no user_id" }), { headers: { "Content-Type": "application/json" } });

  // The user switched this type off in Settings: the inbox row already exists,
  // only the phone push is skipped. No preferences row means everything is on.
  const prefKey = prefKeyFor(actionType);
  if (prefKey) {
    const { data: prefs } = await supabase.from("notification_preferences").select(prefKey).eq("user_id", userId).maybeSingle();
    if (prefs && (prefs as Record<string, unknown>)[prefKey] === false) {
      return new Response(JSON.stringify({ skipped: `${prefKey} off` }), { headers: { "Content-Type": "application/json" } });
    }
  }

  if (!FCM_SA) return new Response(JSON.stringify({ pushed: 0, fcm: false }), { headers: { "Content-Type": "application/json" } });
  let sa: { project_id: string; private_key: string; client_email: string }; let accessToken: string;
  try { sa = JSON.parse(FCM_SA); accessToken = await getAccessToken(sa); }
  catch (e) { console.error("FCM init failed:", e instanceof Error ? e.message : String(e)); return new Response(JSON.stringify({ pushed: 0, fcm: false }), { headers: { "Content-Type": "application/json" } }); }

  const { channel, type } = channelFor(actionType);

  // Tolerate both shapes: pg_net nests jsonb as a real object, but a caller that
  // stringified it should still work. Mirrors parseActionData() in the client.
  let actionData: Record<string, unknown> | null = null;
  const rawAction = body.action_data;
  if (rawAction && typeof rawAction === "object" && !Array.isArray(rawAction)) {
    actionData = rawAction as Record<string, unknown>;
  } else if (typeof rawAction === "string" && rawAction.trim() !== "") {
    try {
      const parsed = JSON.parse(rawAction);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) actionData = parsed;
    } catch (_) { /* not JSON; leave null */ }
  }

  // FCM data values must be strings, and an empty key is worse than an absent one
  // (the client would read '' as a route and reject it, losing the fallback). Only
  // these four keys are forwarded — no reason to ship a whole row to the handset.
  const pushData: Record<string, string> = { type };
  for (const key of ["cta_route", "cta_url", "symbol", "market", "message_id", "author_name", "author_id", "tag", "is_everyone", "action_route"]) {
    const raw = actionData?.[key];
    if (raw === null || raw === undefined) continue;
    const value = String(raw).trim();
    if (value !== "") pushData[key] = value;
  }

  const { data: tokens } = await supabase.from("push_tokens").select("token").eq("user_id", userId).eq("is_active", true);
  let pushed = 0;
  for (const t of (tokens ?? [])) {
    try {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token: t.token, notification: { title, body: msg }, data: pushData, android: { priority: "HIGH", notification: { channel_id: channel } }, apns: { payload: { aps: { sound: "default" } } } } }),
      });
      if (res.status === 400 || res.status === 403 || res.status === 404) {
        await supabase.from("push_tokens").update({ is_active: false }).eq("token", t.token);
      } else if (res.ok) { pushed++; }
    } catch (_) { /* ignore individual token failures */ }
  }
  return new Response(JSON.stringify({ pushed, fcm: true }), { headers: { "Content-Type": "application/json" } });
});
