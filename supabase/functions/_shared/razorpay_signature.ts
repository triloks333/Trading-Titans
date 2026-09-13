/// Razorpay webhook authentication.
///
/// The signature is an HMAC-SHA256 of the *exact raw request body* under the
/// webhook secret. Re-serialising the parsed JSON changes key order and
/// whitespace, which changes the digest, which fails every time — so callers
/// must hand the original text in, never JSON.stringify(parsed).

const enc = new TextEncoder();

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Compares without leaking where the mismatch is. An early-exit compare hands
/// an attacker the expected digest one byte at a time, given enough attempts and
/// a stopwatch.
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function razorpaySignature(
  rawBody: string,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, enc.encode(rawBody)));
}

export async function verifyRazorpaySignature(
  rawBody: string,
  header: string | null,
  secret: string,
): Promise<boolean> {
  // An empty secret would otherwise produce a perfectly valid HMAC that anyone
  // can reproduce, turning a misconfiguration into an open door.
  if (!secret || !header) return false;
  return constantTimeEquals(await razorpaySignature(rawBody, secret), header);
}

export async function sha256Hex(text: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(text)));
}

/// Razorpay sends epoch seconds, and sends nothing when a billing period has
/// not been established yet. Both cases have to survive the trip.
export function epochToIso(seconds: unknown): string | null {
  return typeof seconds === "number" && Number.isFinite(seconds) && seconds > 0
    ? new Date(seconds * 1000).toISOString()
    : null;
}
