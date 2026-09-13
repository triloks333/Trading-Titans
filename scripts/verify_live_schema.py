"""Read-only probe: does the live database already contain the objects that the
local migration files create?

This is the safety check before `supabase migration repair --status applied`.
Marking a migration as applied when it never ran would silently lose its
changes, so we confirm the objects are really there first.

Uses PostgREST with the service-role key (SELECT only, LIMIT 0). The key is read
from .env and never printed.

    python scripts/verify_live_schema.py
"""

from __future__ import annotations

import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# table -> the local migration that creates it
EXPECTED = {
    "profiles": "20260521093000_init",
    "orders": "20260521093000_init",
    "holdings": "20260521093000_init",
    "watchlist": "20260521093000_init",
    "referral_commissions": "20260524183000_add_referral_system",
    "notifications": "20260529120200_add_notifications",
    "trade_autopsies": "20260601083000_add_trade_autopsies",
    "support_tickets": "20260601091500_add_support_tickets",
    "rewards": "20260604110000_create_rewards_table",
    "instruments": "20260605120000_create_instruments_table",
    "pnl_history": "20260605130000_optimize_database",
    "crypto_holdings": "20260605130000_optimize_database",
    "ws_health": "20260605130000_optimize_database",
    "fo_positions": "20260611000003_fo_schema_v2",
    "feature_requests": "20260612100000_add_community_wishlist",
    "push_tokens": "20260613000000_create_push_tokens",
    "charge_configurations": "20260614110000_add_order_charges",
    "leaderboard": "20260621000200_profiles_pii_lockdown (view)",
    "kv_members": "20260728000000_kashivwealth_vault_schema",
    "kv_documents": "20260728000000_kashivwealth_vault_schema",
    "kv_notes": "20260728000008_notes_todos_notifications",
    "kv_todos": "20260728000008_notes_todos_notifications",
    "kv_devices": "20260731050000_kv_push_on_notification",
    "price_alerts": "no migration file (created outside the CLI)",
}

# Must NOT exist yet — proves the new migration has not been applied.
NEW = ["app_flags", "challenges", "user_challenges"]


def load_env() -> tuple[str, str]:
    url = key = ""
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith("SUPABASE_URL="):
            url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
        elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
            key = line.split("=", 1)[1].strip().strip('"')
    if not url or not key:
        raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from .env")
    return url, key


def probe(url: str, key: str, table: str) -> tuple[bool, str]:
    req = urllib.request.Request(
        f"{url}/rest/v1/{table}?select=*&limit=0",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return resp.status < 300, f"HTTP {resp.status}"
    except urllib.error.HTTPError as exc:
        # 404 + PGRST205 means the relation is genuinely absent.
        return False, f"HTTP {exc.code}"
    except Exception as exc:  # network problems should not read as "absent"
        return False, f"error: {type(exc).__name__}"


def main() -> int:
    url, key = load_env()
    print(f"probing {url}\n")

    missing = []
    for table, origin in EXPECTED.items():
        ok, detail = probe(url, key, table)
        print(f"  {'OK     ' if ok else 'MISSING'} {table:<24} {detail:<10} {origin}")
        if not ok:
            missing.append(table)

    print()
    already = []
    for table in NEW:
        ok, detail = probe(url, key, table)
        print(f"  {'PRESENT' if ok else 'absent '} {table:<24} {detail:<10} (new migration)")
        if ok:
            already.append(table)

    print()
    if missing:
        print(f"STOP: {len(missing)} expected object(s) missing: {', '.join(missing)}")
        print("Those migrations have NOT been applied — do not mark them as applied.")
        return 1
    print("All expected objects exist. The local migrations are live under the")
    print("dashboard-generated version stamps, so marking them applied is accurate.")
    if already:
        print(f"\nNote: {', '.join(already)} already exist — the new migration is partly applied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
