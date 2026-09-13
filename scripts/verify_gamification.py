"""Post-migration live check for the gamification layer.

Reads the seeded catalogue and flags, then runs evaluate_challenges() against a
real account to prove every column reference in the evaluator actually resolves.
Parsing the SQL only proved syntax; this proves it runs.

Read-only except for the evaluator call, which is idempotent by design (the
UNIQUE(user_id, challenge_key, cycle) index absorbs repeats).

    python scripts/verify_gamification.py
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


class Client:
    def __init__(self, url: str, key: str) -> None:
        self.url, self.key = url, key

    def _call(self, path: str, method: str = "GET", body: dict | None = None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            f"{self.url}/rest/v1/{path}",
            data=data,
            method=method,
            headers={
                "apikey": self.key,
                "Authorization": f"Bearer {self.key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=40) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw.strip() else None
        except urllib.error.HTTPError as exc:
            return {"__error__": exc.read().decode()[:500], "__status__": exc.code}

    def select(self, table: str, query: str = "select=*"):
        return self._call(f"{table}?{query}")

    def rpc(self, fn: str, params: dict | None = None):
        return self._call(f"rpc/{fn}", method="POST", body=params or {})


def fail(msg: str) -> int:
    print(f"\nFAIL: {msg}")
    return 1


def main() -> int:
    client = Client(*load_env())

    # ── Flags ───────────────────────────────────────────────────────────────
    flags = client.select("app_flags", "select=key,enabled&order=key")
    if isinstance(flags, dict):
        return fail(f"app_flags unreadable: {flags}")
    print("app_flags:")
    for row in flags:
        print(f"  {row['key']:<24} enabled={row['enabled']}")
    by_key = {r["key"]: r["enabled"] for r in flags}
    if by_key.get("monetization_enabled") is not False:
        return fail("monetization_enabled should seed as false")
    if by_key.get("us_stocks_enabled") is not False:
        return fail("us_stocks_enabled should seed as false")

    # ── Catalogue ───────────────────────────────────────────────────────────
    challenges = client.select(
        "challenges", "select=key,category,reward_amount,repeat_limit&order=sort_order"
    )
    if isinstance(challenges, dict):
        return fail(f"challenges unreadable: {challenges}")
    print(f"\nchallenges seeded: {len(challenges)}")
    by_cat: dict[str, int] = {}
    for row in challenges:
        by_cat[row["category"]] = by_cat.get(row["category"], 0) + 1
    for cat, count in sorted(by_cat.items()):
        print(f"  {cat:<14} {count}")

    if "stop_loss_scholar" in {r["key"] for r in challenges}:
        return fail("stop_loss_scholar should not be seeded (dropped from the list)")
    total_reward = sum(float(r["reward_amount"]) for r in challenges)
    print(f"  total advertised reward pool: Rs {total_reward:,.0f}")

    # ── Evaluator against a real account with trades ─────────────────────────
    # Pick the profile with the most executed orders, so the most conditions get
    # exercised in one call.
    orders = client.select("orders", "select=user_id&status=eq.executed&limit=2000")
    if isinstance(orders, dict):
        return fail(f"orders unreadable: {orders}")
    counts: dict[str, int] = {}
    for row in orders:
        counts[row["user_id"]] = counts.get(row["user_id"], 0) + 1
    if not counts:
        print("\nNo executed orders in the database; skipping the evaluator run.")
        return 0
    user_id = max(counts, key=counts.get)
    print(f"\nevaluating the busiest account ({counts[user_id]} executed orders)")

    before = client.select(
        "user_challenges", f"select=challenge_key&user_id=eq.{user_id}"
    )
    result = client.rpc("evaluate_challenges", {"p_user_id": user_id})
    if isinstance(result, dict) and "__error__" in result:
        return fail(f"evaluate_challenges raised: {result['__error__']}")
    print(f"  evaluate_challenges returned: {result} new grant(s)")

    after = client.select(
        "user_challenges",
        f"select=challenge_key,cycle,reward_amount&user_id=eq.{user_id}&order=granted_at",
    )
    if isinstance(after, dict):
        return fail(f"user_challenges unreadable: {after}")
    print(f"  grants for this account: {len(before or [])} -> {len(after)}")
    for row in after[:15]:
        print(f"    {row['challenge_key']:<20} cycle={row['cycle']:<14} Rs {float(row['reward_amount']):,.0f}")
    if len(after) > 15:
        print(f"    ... and {len(after) - 15} more")

    # ── Idempotency: a second run must grant nothing new ────────────────────
    again = client.rpc("evaluate_challenges", {"p_user_id": user_id})
    if isinstance(again, dict) and "__error__" in again:
        return fail(f"second evaluate_challenges raised: {again['__error__']}")
    if again != 0:
        return fail(f"re-running granted {again} more; it must be idempotent")
    print("  re-run granted 0 (idempotent)")

    # ── Rewards pipe ────────────────────────────────────────────────────────
    unclaimed = client.select(
        "rewards", f"select=amount,message,is_claimed&user_id=eq.{user_id}&is_claimed=is.false"
    )
    if isinstance(unclaimed, dict):
        return fail(f"rewards unreadable: {unclaimed}")
    print(f"\nunclaimed rewards waiting for this account: {len(unclaimed)}")
    for row in unclaimed[:5]:
        print(f"    Rs {float(row['amount']):,.0f}  {row['message'][:60]}")

    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
