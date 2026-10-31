import json
import pathlib
import urllib.parse
import urllib.request

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
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def req(path: str, method: str = "GET", data=None):
    r = urllib.request.Request(f"{url}/rest/v1/{path}", headers=HEAD, method=method)
    if data is not None:
        r.data = json.dumps(data).encode("utf-8")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            content = resp.read()
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} on {method} {path}: {e.read().decode('utf-8', errors='ignore')}")
        return None

uid = "068fd8ef-27a2-495d-be98-36dd7958965d"

print("="*80)
print(f"STARTING CLEANUP FOR USER {uid}")
print("="*80)

# 1. Delete corrupted RELIANCE holding
print("1. Deleting corrupted RELIANCE holding...")
del_h = req(f"holdings?user_id=eq.{uid}&symbol=eq.RELIANCE", method="DELETE")
print(f"Deleted holding response: {del_h}")

# 2. Cancel all pending orders for this user
print("\n2. Cancelling pending orders...")
pending = req(f"orders?user_id=eq.{uid}&status=eq.pending")
print(f"Found {len(pending)} pending orders to cancel.")
for p in pending:
    oid = p['id']
    cancel_res = req(f"orders?id=eq.{oid}", method="PATCH", data={"status": "cancelled"})
    print(f"  Cancelled order {oid} ({p['symbol']} qty={p['quantity']})")

# 3. Clean up the corrupted wallet transaction (-5.8 Quadrillion)
print("\n3. Cleaning up corrupted wallet transaction...")
del_tx = req(f"wallet_transactions?user_id=eq.{uid}&amount=lt.-1000000000", method="DELETE")
print(f"Deleted corrupted transactions: {del_tx}")

# 4. Reset wallet_balance to standard demo cash (₹10,000)
print("\n4. Resetting wallet_balance to 10,000.0...")
prof_res = req(f"profiles?id=eq.{uid}", method="PATCH", data={"wallet_balance": 10000.0})
print(f"Updated profile: {prof_res}")

# 5. Insert clean transaction ledger entry
print("\n5. Recording balance reset transaction...")
tx_data = {
    "user_id": uid,
    "amount": 10000.0,
    "balance_before": 0.0,
    "balance_after": 10000.0,
    "kind": "credit",
    "description": "Demo account balance reset"
}
tx_res = req("wallet_transactions", method="POST", data=tx_data)
print(f"Recorded transaction: {tx_res}")

print("\n" + "="*80)
print("CLEANUP COMPLETED - VERIFYING ACCOUNT STATE")
print("="*80)

prof = req(f"profiles?id=eq.{uid}")[0]
print(f"Profile: Name='{prof.get('name')}', Email='{prof.get('email')}', Wallet={prof.get('wallet_balance')}, Realized PnL={prof.get('total_realized_pnl')}")

rem_holdings = req(f"holdings?user_id=eq.{uid}")
print(f"Holdings count: {len(rem_holdings)}")

rem_pending = req(f"orders?user_id=eq.{uid}&status=eq.pending")
print(f"Pending orders count: {len(rem_pending)}")
