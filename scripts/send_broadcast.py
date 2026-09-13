"""Sends one in-app notification to every eligible user, with an optional button.

HOW THE DELIVERY ACTUALLY WORKS
There is no "send to all" API. Each user gets their own row in `notifications`,
and the `trg_push_on_notification` trigger calls the `push-notification` edge
function for that row, which looks up the user's active FCM tokens and pushes.
So a broadcast is N inserts, and the push is a side effect of the insert. A user
with no active token still gets the notification in the app's bell — they just
do not get the tray alert.

THE BUTTON
`action_data.cta_label` plus `action_data.cta_route` renders a primary button in
the notification's detail sheet (see notifications_screen.dart). Routes the app
understands: plans / topup / subscribe, wallet, league. `cta_url` is the fallback
for web-only destinations and must be https.

    NOTE: the button needs app 1.2.0 or newer. On older builds the notification
    still arrives and reads correctly, there is simply no button — so the body
    should always name the destination in words too.

AUDIENCE
Guests are excluded by default. `create-payment-order` refuses anonymous users
and the app blocks them before checkout, so inviting a guest to recharge is a
dead end. Pass --include-guests to override.

USAGE

    python scripts/send_broadcast.py                  # dry run: audience + copy, sends nothing
    python scripts/send_broadcast.py --send           # actually insert and push
    python scripts/send_broadcast.py --campaign plans_live --send
    python scripts/send_broadcast.py --list           # campaigns available here

Dry run is the default on purpose. This is the one script in the repo whose
mistakes land on ~160 phones and cannot be recalled.

BEFORE YOU SEND THE plans_live CAMPAIGN
Check that the build users actually have can take a payment. On 1.1.9 the plans
screen still shows the "Beta Testing Phase — the paywall is paused" dialog, so
this campaign tells people to recharge and then the app tells them they cannot.
Send it only once the 1.2.0 rollout has reached users.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

if not url or not key:
    raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from .env")

HEAD = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json",
}

GUEST_DOMAIN = "@guest.tradingtitans"


# ── campaigns ────────────────────────────────────────────────────────────────
# Copy lives here rather than on the command line so it can be reviewed in a diff
# before it reaches anyone, and so a resend is byte-identical.
#
# The tray only shows roughly the first 100 characters of `body`, so the first
# sentence has to carry the message on its own.
CAMPAIGNS: dict[str, dict] = {
    "feature_bounty": {
        "title": "Your idea could earn you \u20b92,000 \U0001f680",
        "body": (
            "Got a feature you would love to see in Trading Titans? Send it in, "
            "and if we pick your idea we will credit \u20b92,000 of virtual cash "
            "to your wallet.\n\n"
            "A chart tool you miss, a screen you wish existed, something that "
            "would just make trading here better \u2014 all of it counts.\n\n"
            "Open Profile \u2192 Request a Feature to submit yours. You can also "
            "browse and upvote what everyone else has asked for under Community "
            "Wishlist.\n\n"
            "Think it. Request it. Get rewarded."
        ),
        "action_type": "broadcast",
        "action_data": {
            "cta_label": "Request a feature",
            # NOTE: 'feature' is NOT in kNotificationCtaRoutes on any shipped
            # build, and there is no web page to fall back to, so ctaLabel()
            # returns null and NO BUTTON RENDERS until a build ships that knows
            # this route. That is why the body names the path in words. Harmless
            # to send as-is; the button simply appears for whoever has updated.
            "cta_route": "feature",
        },
    },
    "plans_live": {
        "title": "Top-ups and plans are now live",
        "body": (
            "Recharge your wallet in seconds and keep trading without "
            "interruption.\n\n"
            "One-time top-ups add demo cash to your wallet straight away. Or go "
            "Pro or Titan for demo cash every month, futures and options "
            "trading, and a badge beside your name on your profile and the "
            "League.\n\n"
            "Every price includes GST, and there are no ads on any plan — free "
            "or paid.\n\n"
            "Open the Wallet tab to see what is available."
        ),
        "action_type": "broadcast",
        "action_data": {
            "cta_label": "See plans & top-ups",
            "cta_route": "plans",
            # Read only by clients too old to know the route, and by the web app.
            "cta_url": "https://thetradingtitans.com/app/plans",
        },
    },
}


def get(path: str) -> list[dict]:
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def audience(include_guests: bool) -> list[str]:
    rows = get("profiles?select=id,email")
    ids = []
    for row in rows:
        email = row.get("email") or ""
        if not include_guests and email.endswith(GUEST_DOMAIN):
            continue
        ids.append(row["id"])
    return ids


def reachable(ids: set[str]) -> int:
    rows = get("push_tokens?select=user_id&is_active=eq.true")
    return len({r["user_id"] for r in rows if r["user_id"] in ids})


def insert(rows: list[dict]) -> int:
    """Inserts in batches. Each row fires the push trigger, so batches are kept
    small: one oversized request holding the transaction open while it makes
    hundreds of outbound HTTP calls is how this times out halfway through."""
    sent = 0
    BATCH = 25
    for i in range(0, len(rows), BATCH):
        chunk = rows[i:i + BATCH]
        req = urllib.request.Request(
            f"{url}/rest/v1/notifications",
            data=json.dumps(chunk).encode("utf-8"),
            headers={**HEAD, "Prefer": "return=minimal"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=120):
                sent += len(chunk)
            print(f"  inserted {sent}/{len(rows)}")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:300]
            raise SystemExit(
                f"\nFAILED after {sent} of {len(rows)} rows: HTTP {e.code}\n{body}\n"
                f"Already-inserted rows have been delivered. Re-running would "
                f"double-notify those users, so narrow the audience before retrying."
            )
    return sent


args = sys.argv[1:]
if args and args[0] in {"-h", "--help"}:
    print(__doc__)
    sys.exit(0)

if "--list" in args:
    print("campaigns:")
    for name, c in CAMPAIGNS.items():
        print(f"  {name:14s} {c['title']}")
    sys.exit(0)

name = "plans_live"
if "--campaign" in args:
    name = args[args.index("--campaign") + 1]
if name not in CAMPAIGNS:
    raise SystemExit(f"unknown campaign '{name}'. Try --list")

campaign = CAMPAIGNS[name]
include_guests = "--include-guests" in args
do_send = "--send" in args

ids = audience(include_guests)
tray = reachable(set(ids))

print(f"\ncampaign        {name}")
print(f"audience        {len(ids)} users"
      f"{'' if include_guests else ' (guests excluded)'}")
print(f"tray reach      {tray} have an active push token; "
      f"{len(ids) - tray} will see it only in the app's bell")
print(f"\ntitle           {campaign['title']}")
print("body")
for ln in campaign["body"].splitlines():
    print(f"  {ln}")
print(f"\nbutton          {campaign['action_data'].get('cta_label')} "
      f"-> {campaign['action_data'].get('cta_route')}")
print(f"action_type     {campaign['action_type']} "
      f"(channel broadcast_channel_v1)")

if not do_send:
    print("\nDRY RUN — nothing was sent. Add --send to deliver this.")
    sys.exit(0)

rows = [
    {
        "user_id": uid,
        "title": campaign["title"],
        "body": campaign["body"],
        "is_read": False,
        "action_type": campaign["action_type"],
        "action_data": campaign["action_data"],
    }
    for uid in ids
]

print(f"\nsending to {len(rows)} users...")
sent = insert(rows)
print(f"\nDone. {sent} notifications inserted; the push trigger has fired for each.")
print("Users with the app open see it immediately; the rest get a tray alert.")
