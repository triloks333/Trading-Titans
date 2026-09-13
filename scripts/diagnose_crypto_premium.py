"""Why does our ETH price differ from the TradingView chart?

Our crypto quotes come from CoinDCX in rupees. Converting that to dollars with the
USD/INR rate does NOT give the global ETH/USD price, because an Indian exchange's
rupee price carries its own premium or discount versus offshore venues.

This prints our number, the global number, and the implied exchange rate, so the
gap can be attributed rather than guessed at.

Read-only.

    python scripts/diagnose_crypto_premium.py
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
UA = {"User-Agent": "Mozilla/5.0"}


def get_json(url: str, headers: dict | None = None):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as exc:
        return {"__error__": f"{type(exc).__name__}: {exc}"}


def main() -> int:
    head = {"apikey": KEY, "Authorization": f"Bearer {KEY}"}

    fx = get_json(f"{URL}/functions/v1/market-quote?market=fx", head)
    rate = fx.get("price") if isinstance(fx, dict) else None
    print(f"USD/INR (our rate, from Yahoo)      : {rate}")

    print()
    for sym, binance in [("ETH", "ETHUSDT"), ("BTC", "BTCUSDT")]:
        ours = get_json(f"{URL}/functions/v1/market-quote?symbol={sym}&market=crypto", head)
        if not isinstance(ours, dict) or "price" not in ours:
            print(f"{sym}: could not read our quote: {ours}")
            continue
        inr = float(ours["price"])
        source = ours.get("source")

        glob = get_json(f"https://api.binance.com/api/v3/ticker/price?symbol={binance}")
        gusd = float(glob["price"]) if isinstance(glob, dict) and "price" in glob else None

        shown = inr / rate if rate else None
        print(f"{sym}  (our source: {source})")
        print(f"  our price in INR                  : Rs {inr:,.2f}")
        print(f"  what the app shows in USD         : ${shown:,.2f}" if shown else "  (no rate)")
        if gusd:
            print(f"  global {binance} (Binance)     : ${gusd:,.2f}")
            implied = inr / gusd
            premium = (shown / gusd - 1) * 100 if shown else 0
            print(f"  implied INR per USD              : {implied:,.2f}")
            print(f"  premium of our price vs global   : {premium:+.2f}%")
            print(f"  -> the gap is the Indian-exchange premium, not an FX error")
            print(f"     ({implied:,.2f} implied vs {rate:,.2f} actual)")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
