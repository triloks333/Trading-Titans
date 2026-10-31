import json
import pathlib
import urllib.request
import time
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
}

today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
print(f"Starting F&O Monthly Market Data Sync for {today}...")

# First, deactivate expired instruments
print("Deactivating any expired instruments...")
deactivate_req = urllib.request.Request(
    f"{url}/rest/v1/instruments?tradeable=eq.true&expiry_date=lt.{today}",
    data=json.dumps({"tradeable": False}).encode("utf-8"),
    headers=HEAD,
    method="PATCH"
)
try:
    with urllib.request.urlopen(deactivate_req, timeout=30) as r:
        print("Expired instruments deactivated successfully.")
except Exception as e:
    print(f"Deactivate error: {e}")

# Fetch FO CSV from Fyers
print("Downloading latest NSE_FO.csv from Fyers...")
csv_url = "https://public.fyers.in/sym_details/NSE_FO.csv"
req = urllib.request.Request(csv_url, headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req, timeout=60) as resp:
    raw_csv = resp.read().decode("utf-8", errors="ignore")

lines = raw_csv.splitlines()
print(f"Downloaded {len(lines)} lines from Fyers NSE_FO.csv")

instruments = []
for line in lines:
    if not line.strip():
        continue
    r = [col.strip() for col in line.split(",")]
    if len(r) < 10:
        continue

    # 0: token, 1: name, 2: inst_type, 3: lot, 8: expiry_epoch, 9: symbol, 15: strike, 16: opt_type
    sym = r[9]
    name = r[1]

    # Exclude unwanted families that cause prefix collisions
    upper_sym = sym.upper()
    if upper_sym.startswith("NSE:NIFTYNXT50") or upper_sym.startswith("NSE:NIFTYFPI"):
        continue

    opt_type = r[16] if len(r) > 16 else "XX"
    inst_type = "FUTURE"
    final_opt_type = None
    if opt_type in ("CE", "PE"):
        inst_type = "OPTION"
        final_opt_type = opt_type

    expiry_date = None
    try:
        epoch = int(r[8])
        if epoch > 0:
            expiry_date = datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        pass

    strike = None
    if inst_type == "OPTION" and len(r) > 15:
        try:
            strike = float(r[15])
        except Exception:
            pass

    lot = 1
    try:
        lot = int(r[3])
    except Exception:
        pass

    # We only care to upload current and upcoming monthly contracts (expiry >= today)
    if not expiry_date or expiry_date < today:
        continue

    instruments.append({
        "fyers_token": r[0],
        "symbol": sym,
        "name": name,
        "market": "stock",
        "instrument_type": inst_type,
        "expiry_date": expiry_date,
        "strike_price": strike,
        "option_type": final_opt_type,
        "lot_size": lot,
        "tradeable": True
    })

print(f"Prepared {len(instruments)} active / upcoming F&O contracts for sync.")

# Batch upsert to database in chunks of 500
BATCH_SIZE = 500
total = len(instruments)
for i in range(0, total, BATCH_SIZE):
    batch = instruments[i:i + BATCH_SIZE]
    post_req = urllib.request.Request(
        f"{url}/rest/v1/instruments",
        data=json.dumps(batch).encode("utf-8"),
        headers=HEAD,
        method="POST"
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(post_req, timeout=40) as r:
                pass
            break
        except Exception as e:
            if attempt == 2:
                print(f"Failed batch {i}..{i+len(batch)}: {e}")
            else:
                time.sleep(1)
    if (i // BATCH_SIZE) % 10 == 0:
        print(f"Synced {min(i + BATCH_SIZE, total)} / {total} instruments...")

print("Sync completed successfully!")
