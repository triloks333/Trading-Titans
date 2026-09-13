"""Prints the live version-gating config and feature flags.

Read-only. Run before a release to see what version the app currently gates on
and which features are switched on for everyone.

    python scripts/show_release_gate.py
"""

import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {"apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"}


def get(path):
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


print("app_config (version gate):")
for row in sorted(get("app_config?select=key,value"), key=lambda r: r["key"]):
    value = (row["value"] or "").replace("\n", " | ")
    print(f"  {row['key']:24s} {value[:90]}")

print("\napp_flags (feature switches):")
for row in get("app_flags?select=*"):
    print(f"  {row}")
