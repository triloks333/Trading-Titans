import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Sends a KASHIVWEALTH VAULT notification to the recipient's phones.
// Called by the `kv_notifications` AFTER INSERT trigger (via pg_net), so any
// vault notification also reaches the system tray while the app is closed.
//
// Body: { user_id, title, body, kind }
//
// Reuses the same FCM service account as Trading Titans; the vault Android app
// (com.kashivwealth.vault) is registered in that same Firebase project.

const FCM_SA = Deno.env.get("FCM_SERVICE_ACCOUNT");
const CHANNEL = "kv_workspace_channel";

let cachedToken: { token: string; exp: number } | null = null;

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  let s = btoa(bin).split("+").join("-").split("/").join("_");
  while (s.endsWith("=")) s = s.slice(0, -1);
  return s;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  let c = pem
    .split("-----BEGIN PRIVATE KEY-----").join("")
    .split("-----END PRIVATE KEY-----").join("");
  c = c.split("\n").join("").split("\r").join("").split(" ").join("").split("\t").join("");
  const der = Uint8Array.from(atob(c), (x) => x.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// deno-lint-ignore no-explicit-any
async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned =
    enc({ alg: "RS256", typ: "JWT" }) + "." +
    enc({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    });
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = unsigned + "." + b64url(new Uint8Array(sig));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt,
  });
  const j = await res.json();
  if (!j.access_token) throw new Error("FCM oauth failed: " + JSON.stringify(j));
  cachedToken = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cachedToken.token;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) { /* ignore */ }

  const userId = String(body.user_id ?? "");
  const title = String(body.title ?? "").trim() || "KASHIVWEALTH VAULT";
  const msg = String(body.body ?? "").trim();
  const kind = String(body.kind ?? "general");
  if (!userId) {
    return new Response(JSON.stringify({ skipped: "no user_id" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!FCM_SA) {
    return new Response(JSON.stringify({ pushed: 0, fcm: false }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  let sa: { project_id: string; private_key: string; client_email: string };
  let accessToken: string;
  try {
    sa = JSON.parse(FCM_SA);
    accessToken = await getAccessToken(sa);
  } catch (e) {
    console.error("FCM init failed:", e instanceof Error ? e.message : String(e));
    return new Response(JSON.stringify({ pushed: 0, fcm: false }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: devices } = await supabase
    .from("kv_devices")
    .select("id, fcm_token")
    .eq("user_id", userId)
    .not("fcm_token", "is", null);

  let pushed = 0;
  for (const device of devices ?? []) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              notification: { title, body: msg },
              data: { kind },
              android: {
                priority: "HIGH",
                notification: { channel_id: CHANNEL },
              },
              apns: { payload: { aps: { sound: "default" } } },
            },
          }),
        },
      );
      if (res.status === 400 || res.status === 403 || res.status === 404) {
        // Token is dead: clear it so it stops being retried.
        await supabase
          .from("kv_devices")
          .update({ fcm_token: null })
          .eq("id", device.id);
      } else if (res.ok) {
        pushed++;
      } else {
        console.error("FCM send failed", res.status, (await res.text()).slice(0, 300));
      }
    } catch (_) { /* ignore individual token failures */ }
  }

  return new Response(JSON.stringify({ pushed, fcm: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
