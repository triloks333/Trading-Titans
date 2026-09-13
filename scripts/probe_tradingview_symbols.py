"""Find which TradingView symbols exist for our tradable coins.

We price crypto from CoinDCX in rupees, so the chart should be an INR pair on the
same (or nearest) venue. TradingView's Indian-exchange coverage is patchy, so this
probes its public symbol search and reports what is actually available per coin,
rather than us hardcoding symbols that render a blank chart.

    python scripts/probe_tradingview_symbols.py
"""

from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request

SEARCH = "https://symbol-search.tradingview.com/symbol_search/v3/"
UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Origin": "https://www.tradingview.com",
    "Referer": "https://www.tradingview.com/",
}

# The coins the trade screen offers.
COINS = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "POL"]


def search(text: str) -> list[dict]:
    url = f"{SEARCH}?text={urllib.parse.quote(text)}&hl=1&exchange=&lang=en&search_type=crypto&domain=production"
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = json.loads(resp.read())
            return body.get("symbols", []) or []
    except Exception as exc:
        print(f"    search failed for {text}: {type(exc).__name__}: {exc}")
        return []


def clean(s: str) -> str:
    return s.replace("<em>", "").replace("</em>", "")


def main() -> int:
    print("Looking for INR-quoted crypto pairs on TradingView\n")
    inr_exchanges: dict[str, int] = {}
    per_coin: dict[str, list[str]] = {}

    for coin in COINS:
        hits = search(f"{coin}INR")
        found = []
        for h in hits:
            sym = clean(h.get("symbol", ""))
            exch = clean(h.get("exchange", ""))
            desc = clean(h.get("description", ""))
            if "INR" not in sym.upper():
                continue
            found.append(f"{exch}:{sym}")
            inr_exchanges[exch] = inr_exchanges.get(exch, 0) + 1
            print(f"  {coin:<6} {exch:<12} {sym:<14} {desc[:40]}")
        per_coin[coin] = found
        if not found:
            print(f"  {coin:<6} (no INR pair found)")

    print("\nINR-capable exchanges by hit count:")
    for exch, n in sorted(inr_exchanges.items(), key=lambda kv: -kv[1]):
        print(f"  {exch:<14} {n} coin(s)")

    print("\nCoverage per coin:")
    complete = []
    for exch in inr_exchanges:
        covered = [c for c in COINS if any(f.startswith(exch + ":") for f in per_coin[c])]
        print(f"  {exch:<14} {len(covered)}/{len(COINS)}  missing: "
              f"{', '.join(c for c in COINS if c not in covered) or 'none'}")
        if len(covered) == len(COINS):
            complete.append(exch)

    print()
    if complete:
        print(f"Full coverage from: {', '.join(complete)}")
    else:
        print("No single exchange covers every coin — a per-coin fallback is needed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
