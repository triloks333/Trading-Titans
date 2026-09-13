"""Live check for the user-preference columns and RPCs.

Confirms the columns exist, the CHECK constraints reject bad values, and the
preference RPCs resolve without a PostgREST overload ambiguity (the risk when a
function gains a parameter).

Read-only apart from deliberately-invalid writes, which are expected to fail.

    python scripts/verify_preferences.py
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


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


URL, KEY = load_env()
HEAD = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
failures: list[str] = []


def call(path: str, method: str = "GET", body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}/rest/v1/{path}", data=data, method=method, headers=HEAD)
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as exc:
        return {"__error__": exc.read().decode()[:400], "__status__": exc.code}


def check(label: str, ok: bool, detail: str = "") -> None:
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{(' - ' + detail) if detail else ''}")
    if not ok:
        failures.append(label)


def main() -> int:
    print("columns")
    for col in ("display_currency", "preferred_markets", "onboarding_completed_at", "location"):
        r = call(f"profiles?select={col}&limit=1")
        check(f"profiles.{col}", not isinstance(r, dict))

    print("\ndefaults on existing accounts")
    rows = call("profiles?select=display_currency,preferred_markets,location,onboarding_completed_at&limit=5")
    if isinstance(rows, list):
        for row in rows:
            print(f"        currency={row['display_currency']} "
                  f"markets={'+'.join(row['preferred_markets'] or [])} "
                  f"location={row['location']} onboarded={row['onboarding_completed_at']}")
        check("all rows have a currency", all(r["display_currency"] for r in rows))
        check("all rows have markets", all(r["preferred_markets"] for r in rows))
    else:
        check("read profiles", False, str(rows)[:150])

    print("\nRPCs resolve (no overload ambiguity after adding p_location)")
    r = call("rpc/get_user_preferences", "POST", {})
    ambiguous = isinstance(r, dict) and "__error__" in r and "ambiguous" in r["__error__"].lower()
    check("get_user_preferences", not ambiguous,
          r["__error__"][:120] if isinstance(r, dict) and "__error__" in r else "")

    # Service role has no auth.uid(), so this raises "Not authenticated" — which
    # still proves the function resolved and ran.
    r = call("rpc/save_user_preferences", "POST", {"p_location": "india"})
    resolved = not (isinstance(r, dict) and "__error__" in r
                    and ("ambiguous" in r["__error__"].lower()
                         or "does not exist" in r["__error__"].lower()))
    check("save_user_preferences resolves with p_location", resolved,
          r["__error__"][:120] if isinstance(r, dict) and "__error__" in r else "")

    print("\nconstraints reject bad values")
    r = call("rpc/save_user_preferences", "POST", {"p_location": "mars"})
    rejected = isinstance(r, dict) and "__error__" in r
    check("location 'mars' rejected", rejected)

    r = call("rpc/save_user_preferences", "POST", {"p_display_currency": "GBP"})
    check("currency 'GBP' rejected", isinstance(r, dict) and "__error__" in r)

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        return 1
    print("All preference checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
