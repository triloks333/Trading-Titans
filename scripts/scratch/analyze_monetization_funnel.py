import json
import pathlib
import urllib.parse
import urllib.request
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[2]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Accept": "application/json"
}

def get(path: str):
    r = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            content = resp.read()
            return json.loads(content) if content else []
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} on {path}: {e.read().decode('utf-8', errors='ignore')}")
        return []

print("="*80)
print("DEEP ANALYSIS: MONETIZATION & CONVERSION FUNNEL")
print("="*80)

# 1. Total users breakdown
profiles = get("profiles?select=id,name,email,wallet_balance,subscription_active,plan,created_at,purchased_cash_floor,location,country_code,last_platform,total_realized_pnl,login_streak")
print(f"Total registered profiles: {len(profiles)}")

# Plan distribution
plans = Counter(p.get("plan") or "none" for p in profiles)
print("\nUser Plans Distribution:")
for plan, count in plans.items():
    print(f"  {plan}: {count}")

# Subscriptions active
subs = Counter(p.get("subscription_active") for p in profiles)
print(f"\nSubscription active flag: {dict(subs)}")

# Purchased cash floor (>0 means they bought top-up)
paid_topups = [p for p in profiles if (p.get("purchased_cash_floor") or 0) > 0]
print(f"\nUsers with purchased_cash_floor > 0 (bought topup): {len(paid_topups)}")
for p in paid_topups:
    print(f"  {p['name']} ({p['email']}): purchased_floor={p['purchased_cash_floor']}, wallet={p['wallet_balance']}")

# Check wallet balances: how many users actually need top-up?
wallets = [float(p.get("wallet_balance") or 0) for p in profiles]
zero_or_low = [w for w in wallets if w < 1000]
mid_wallets = [w for w in wallets if 1000 <= w <= 15000]
high_wallets = [w for w in wallets if w > 15000]

print(f"\nWallet Balances Overview:")
print(f"  < 1,000 INR (broke/low capital): {len(zero_or_low)} users ({len(zero_or_low)/len(wallets)*100:.1f}%)")
print(f"  1,000 - 15,000 INR (standard default ~10k): {len(mid_wallets)} users ({len(mid_wallets)/len(wallets)*100:.1f}%)")
print(f"  > 15,000 INR (high capital / profitable): {len(high_wallets)} users ({len(high_wallets)/len(wallets)*100:.1f}%)")

# Platform & location breakdown
platforms = Counter(p.get("last_platform") or "unknown" for p in profiles)
print(f"\nPlatform Breakdown: {dict(platforms)}")

countries = Counter(p.get("country_code") or "unknown" for p in profiles)
print(f"Top 5 Countries: {dict(countries.most_common(5))}")
