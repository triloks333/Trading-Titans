"""Checks whether our MATIC quote is real.

Polygon rebranded MATIC -> POL in Sept 2024. CoinDCX kept a MATICINR market
listed, so our ticker lookup still finds a row and never errors — it just returns
a price for a token nobody trades any more. This prints both markets side by side
so the gap is visible.

    python scripts/diagnose_matic.py
"""

import json
import urllib.request

TICKER = "https://api.coindcx.com/exchange/ticker"
CG = ("https://api.coingecko.com/api/v3/simple/price"
      "?ids=matic-network,polygon-ecosystem-token&vs_currencies=inr")


def get(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json",
                                               "User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


tickers = {t["market"]: t for t in get(TICKER)}

print("CoinDCX (the source market-quote uses):")
for market in ("MATICINR", "POLINR"):
    t = tickers.get(market)
    if not t:
        print(f"  {market:10s} not listed")
        continue
    print(f"  {market:10s} last={float(t['last_price']):>12,.4f}  "
          f"vol={float(t.get('volume') or 0):>16,.2f}  "
          f"change_24h={t.get('change_24_hour')}")

try:
    cg = get(CG)
    print("\nCoinGecko reference (INR):")
    for cid in ("matic-network", "polygon-ecosystem-token"):
        print(f"  {cid:26s} {cg.get(cid, {}).get('inr')}")
except Exception as exc:  # rate limited without a key
    print(f"\nCoinGecko lookup unavailable: {exc}")


# What our own endpoint actually serves, after the CoinDCX -> Binance ->
# CoinGecko fallback chain has run.
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

req = urllib.request.Request(
    f"{url}/functions/v1/market-quote?symbol=MATIC&market=crypto",
    headers={"apikey": key, "Authorization": f"Bearer {key}"},
)
with urllib.request.urlopen(req, timeout=40) as r:
    q = json.loads(r.read())
print("\nOur market-quote for MATIC:")
print(f"  price={q.get('price')} currency={q.get('currency')} "
      f"source={q.get('source')} name={q.get('display_name')}")

req = urllib.request.Request(
    f"{url}/functions/v1/market-quote?symbol=POL&market=crypto",
    headers={"apikey": key, "Authorization": f"Bearer {key}"},
)
with urllib.request.urlopen(req, timeout=40) as r:
    q = json.loads(r.read())
print("Our market-quote for POL:")
print(f"  price={q.get('price')} currency={q.get('currency')} "
      f"source={q.get('source')} name={q.get('display_name')}")
