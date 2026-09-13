"""Compare live tables/views against the ones the local migrations create.

Answers the question: do the migration files in this repo fully describe the
production schema? Anything listed as UNDOCUMENTED was created outside the CLI
and would lose its only record if the remote-only history rows were dropped.

Read-only.

    python scripts/schema_coverage.py
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"

CREATE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW|MATERIALIZED\s+VIEW)\s+"
    r"(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?\"?(\w+)\"?",
    re.IGNORECASE,
)


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


def main() -> int:
    url, key = load_env()
    req = urllib.request.Request(
        f"{url}/rest/v1/",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/openapi+json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        spec = json.loads(resp.read())

    live = {
        name
        for name in spec.get("definitions", {})
        if not name.startswith("(")  # skip RPC arg pseudo-definitions
    }

    documented: dict[str, str] = {}
    for path in sorted(MIGRATIONS.glob("*.sql")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in CREATE.finditer(text):
            documented.setdefault(match.group(1), path.name)

    undocumented = sorted(live - documented.keys())
    unused = sorted(documented.keys() - live)

    print(f"live relations exposed via REST : {len(live)}")
    print(f"created by local migrations     : {len(documented)}")

    print(f"\n--- UNDOCUMENTED in live db ({len(undocumented)}) ---")
    for name in undocumented:
        print(f"  {name}")
    if not undocumented:
        print("  (none — the migration files describe every exposed relation)")

    print(f"\n--- in migrations but not exposed via REST ({len(unused)}) ---")
    print("  (expected for staging tables, RLS-hidden tables and dropped objects)")
    for name in unused:
        print(f"  {name}")

    return 1 if undocumented else 0


if __name__ == "__main__":
    sys.exit(main())
