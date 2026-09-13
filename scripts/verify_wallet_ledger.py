"""Live check for the wallet_transactions ledger.

Confirms the table and columns exist, the backfill covered every account, the
ledger reconciles against profiles.wallet_balance, and clients cannot write to
it.

Read-only, apart from one deliberately-invalid insert attempted with the ANON
key, which is expected to be refused. It never touches a balance.

The reconciliation check doubles as a trigger liveness test: once any account has
activity after the migration, the newest ledger row's balance_after must still
equal the live wallet_balance. If the trigger were not firing, the two would have
drifted apart.

    python scripts/verify_wallet_ledger.py
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from collections import Counter
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


def load_anon_key() -> str | None:
    """The public anon key, read from the committed Flutter config."""
    cfg = ROOT / "app" / "lib" / "core" / "supabase_config.dart"
    if not cfg.exists():
        return None
    m = re.search(r"defaultValue:\s*'([A-Za-z0-9._-]{40,})'", cfg.read_text(encoding="utf-8"))
    return m.group(1) if m else None


URL, KEY = load_env()
HEAD = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
failures: list[str] = []


def call(path: str, method: str = "GET", body: dict | None = None, headers: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{URL}/rest/v1/{path}", data=data, method=method, headers=headers or HEAD
    )
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
    print("table and columns")
    cols = ("id", "user_id", "amount", "balance_before", "balance_after",
            "kind", "description", "created_at")
    r = call(f"wallet_transactions?select={','.join(cols)}&limit=1")
    exists = not isinstance(r, dict)
    check("wallet_transactions readable with all columns", exists,
          str(r)[:180] if not exists else "")
    if not exists:
        print("\nTable missing or unreadable - has the migration been applied?")
        return 1

    print("\nbackfill coverage")
    profiles = call("profiles?select=id,wallet_balance&limit=1000")
    ledger = call("wallet_transactions?select=user_id,amount,balance_after,kind,created_at"
                  "&order=created_at.desc&limit=5000")
    if not isinstance(profiles, list) or not isinstance(ledger, list):
        check("read profiles + ledger", False, f"{str(profiles)[:120]} / {str(ledger)[:120]}")
        return 1

    by_user: dict[str, list[dict]] = {}
    for row in ledger:
        by_user.setdefault(row["user_id"], []).append(row)

    missing = [p["id"] for p in profiles if p["id"] not in by_user]
    check(f"every account has at least one ledger row ({len(profiles)} accounts)",
          not missing,
          f"{len(missing)} without any: {[m[:8] for m in missing]}" if missing else "")

    openings = [r for r in ledger if r["kind"] == "opening"]
    dupes = [u for u, rows in by_user.items()
             if sum(1 for r in rows if r["kind"] == "opening") > 1]
    check("exactly one opening row per account (backfill not double-counted)",
          not dupes, f"{len(dupes)} with more than one" if dupes else "")

    print("\nreconciliation against the live balance")
    print("  (also proves the trigger fires: any post-migration change that the")
    print("   trigger missed would show up here as a mismatch)")
    drift = []
    for p in profiles:
        rows = by_user.get(p["id"])
        if not rows:
            continue
        # `ledger` came back created_at desc, so the first entry is the newest.
        newest = rows[0]
        want = float(p["wallet_balance"] or 0)
        got = float(newest["balance_after"] or 0)
        if abs(want - got) > 0.005:
            drift.append((p["id"][:8], want, got, newest["kind"]))
    check("newest balance_after equals profiles.wallet_balance for every account",
          not drift)
    for uid, want, got, kind in drift:
        print(f"        {uid}  wallet={want:.2f}  ledger={got:.2f}  (newest kind={kind})")

    print("\nledger contents")
    kinds = Counter(r["kind"] for r in ledger)
    for kind, n in kinds.most_common():
        print(f"        {kind:<12} {n}")
    post = len(ledger) - len(openings)
    if post == 0:
        print("        (no post-migration rows yet - place a trade or claim a")
        print("         reward, then re-run: a new row must appear and the")
        print("         reconciliation above must still pass)")

    print("\nclients cannot write to the ledger")
    anon = load_anon_key()
    if not anon:
        check("anon key found in app/lib/core/supabase_config.dart", False)
    else:
        target = profiles[0]["id"] if profiles else "00000000-0000-0000-0000-000000000000"
        r = call(
            "wallet_transactions",
            "POST",
            {"user_id": target, "amount": 1, "balance_before": 0,
             "balance_after": 1, "kind": "tamper"},
            headers={"apikey": anon, "Authorization": f"Bearer {anon}",
                     "Content-Type": "application/json"},
        )
        refused = isinstance(r, dict) and "__error__" in r
        check("anon INSERT refused (no client write policy exists)", refused,
              "" if refused else "INSERT SUCCEEDED - the ledger is writable!")
        if refused:
            print(f"        status {r['__status__']}")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        return 1
    print("Wallet ledger verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
