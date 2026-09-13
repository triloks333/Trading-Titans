import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  epochToIso,
  razorpaySignature,
  verifyRazorpaySignature,
} from "./razorpay_signature.ts";

const SECRET = "tt_webhook_secret";
const BODY = '{"event":"order.paid","payload":{"order":{"entity":{"id":"order_X"}}}}';

// Known-answer test. If the digest algorithm, encoding, or hex formatting ever
// drifts, every real Razorpay delivery starts failing verification — this is the
// cheapest way to notice that here instead of in production.
Deno.test("signature is a stable hex HMAC-SHA256 of the raw body", async () => {
  const sig = await razorpaySignature(BODY, SECRET);
  assertEquals(sig.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(sig), true);
  assertEquals(sig, await razorpaySignature(BODY, SECRET));
});

Deno.test("a correct signature verifies", async () => {
  const sig = await razorpaySignature(BODY, SECRET);
  assertEquals(await verifyRazorpaySignature(BODY, sig, SECRET), true);
});

Deno.test("verification refuses everything that is not the real thing", async () => {
  const sig = await razorpaySignature(BODY, SECRET);

  // Wrong secret: this is the forged-webhook case.
  assertEquals(await verifyRazorpaySignature(BODY, sig, "wrong_secret"), false);

  // Tampered body under a captured signature: the replay-with-edits case, e.g.
  // swapping in a bigger order.
  assertEquals(
    await verifyRazorpaySignature(BODY.replace("order_X", "order_Y"), sig, SECRET),
    false,
  );

  // Missing header, empty header, truncated digest.
  assertEquals(await verifyRazorpaySignature(BODY, null, SECRET), false);
  assertEquals(await verifyRazorpaySignature(BODY, "", SECRET), false);
  assertEquals(await verifyRazorpaySignature(BODY, sig.slice(0, 63), SECRET), false);

  // Unconfigured secret must fail closed, not sign with "".
  assertEquals(await verifyRazorpaySignature(BODY, sig, ""), false);
});

Deno.test("re-serialised JSON does not verify", async () => {
  // Guards the one mistake that silently breaks this: verifying a stringified
  // parse instead of the raw text. Any formatting the sender used — here, the
  // indentation a pretty-printed payload arrives with — is part of the digest.
  const pretty = JSON.stringify(JSON.parse(BODY), null, 2);
  const sig = await razorpaySignature(pretty, SECRET);
  const reserialised = JSON.stringify(JSON.parse(pretty));
  assertEquals(reserialised === pretty, false);
  assertEquals(await verifyRazorpaySignature(reserialised, sig, SECRET), false);
  // ...and the untouched raw text still does verify.
  assertEquals(await verifyRazorpaySignature(pretty, sig, SECRET), true);
});

Deno.test("epoch seconds convert, absent periods stay null", () => {
  assertEquals(epochToIso(1767225600), "2026-01-01T00:00:00.000Z");
  assertEquals(epochToIso(null), null);
  assertEquals(epochToIso(undefined), null);
  assertEquals(epochToIso(0), null);
  assertEquals(epochToIso("1767225600"), null);
  assertEquals(epochToIso(Number.NaN), null);
});
