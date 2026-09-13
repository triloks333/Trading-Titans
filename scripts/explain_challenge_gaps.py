"""For one account, show the raw numbers behind each ungranted challenge.

The evaluator running without error proves its SQL resolves. This proves the
*outcome* is right: that the challenges which did not pay out genuinely were not
met, rather than being blocked by a logic bug.

Read-only.

    python scripts/explain_challenge_gaps.py [user_id]
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
    return url, key


URL, KEY = load_env()


def get(path: str):
    req = urllib.request.Request(
        f"{URL}/rest/v1/{path}",
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw.strip() else []
    except urllib.error.HTTPError as exc:
        return {"__error__": exc.read().decode()[:300]}


def main() -> int:
    if len(sys.argv) > 1:
        user_id = sys.argv[1]
    else:
        orders = get("orders?select=user_id&status=eq.executed&limit=2000")
        counts: dict[str, int] = {}
        for row in orders:
            counts[row["user_id"]] = counts.get(row["user_id"], 0) + 1
        user_id = max(counts, key=counts.get)

    profile = get(
        f"profiles?select=total_realized_pnl,challenge_baseline_capital,"
        f"longest_login_streak,total_xp,is_admin&id=eq.{user_id}"
    )
    if isinstance(profile, dict) or not profile:
        print(f"profile unreadable: {profile}")
        return 1
    p = profile[0]

    pnl = float(p["total_realized_pnl"])
    baseline = float(p["challenge_baseline_capital"])
    print(f"account {user_id[:8]}  admin={p['is_admin']}  xp={p['total_xp']}")
    print(f"  total_realized_pnl        Rs {pnl:,.2f}")
    print(f"  challenge_baseline_capital Rs {baseline:,.2f}")
    print(f"  longest_login_streak       {p['longest_login_streak']}")

    print("\nungranted challenges and why:")

    need = 0.20 * baseline
    print(f"  titan_20        needs realized >= Rs {need:,.0f}  -> have Rs {pnl:,.0f}"
          f"  {'MET' if pnl >= need else 'not met'}")
    for label, threshold in (("1l", 100000), ("5l", 500000), ("10l", 1000000)):
        print(f"  century_club_{label:<3} needs realized >= Rs {threshold:,}"
              f"  -> {'MET' if pnl >= threshold else 'not met'}")

    print(f"  login_streak_3  needs streak >= 3 -> have {p['longest_login_streak']}"
          f"  {'MET' if p['longest_login_streak'] >= 3 else 'not met (no login recorded yet)'}")

    holdings = get(f"holdings?select=symbol,market,quantity&user_id=eq.{user_id}")
    if not isinstance(holdings, dict):
        open_pos = [h for h in holdings if float(h["quantity"]) > 0]
        symbols = {h["symbol"] for h in open_pos}
        markets = {h["market"] for h in open_pos}
        print(f"  diversifier     needs 5+ symbols held -> have {len(symbols)}"
              f"  {'MET' if len(symbols) >= 5 else 'not met'}")
        print(f"  globetrotter    needs 3 markets held  -> have {sorted(markets)}"
              f"  {'MET' if len(markets & {'stock','us_stock','crypto'}) >= 3 else 'not met'}")

    autopsies = get(f"trade_autopsies?select=pnl&user_id=eq.{user_id}")
    if not isinstance(autopsies, dict):
        losing = [a for a in autopsies if float(a["pnl"]) < 0]
        print(f"  autopsy_analyst needs 5 losing autopsies -> have {len(losing)}"
              f"  {'MET' if len(losing) >= 5 else 'not met'}")

    alerts = get(f"price_alerts?select=status&user_id=eq.{user_id}&status=eq.triggered")
    if not isinstance(alerts, dict):
        print(f"  alert_watcher   needs 3 triggered alerts -> have {len(alerts)}"
              f"  {'MET' if len(alerts) >= 3 else 'not met'}")

    referrals = get(f"profiles?select=id&referred_by=eq.{user_id}")
    if not isinstance(referrals, dict):
        n = len(referrals)
        print(f"  referral_5/10   needs 5 / 10 referrals -> have {n}"
              f"  {'MET' if n >= 5 else 'not met'}")

    print("\nIf every line above reads 'not met', the 3 grants are the correct outcome.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
