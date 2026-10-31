import urllib.request
import json

headers = {'User-Agent': 'Mozilla/5.0'}

italy_symbols = ['ENI.MI', 'RACE.MI', 'ISP.MI', 'UCG.MI']
# Pakistan Stock Exchange (PSX) symbols on Yahoo Finance
pakistan_symbols = ['OGDC.KA', 'LUCK.KA', 'ENGRO.KA', 'MCB.KA', 'HBL.KA', 'SYS.KA']

print("--- TESTING ITALY STOCKS (Yahoo Finance) ---")
for sym in italy_symbols:
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}?interval=1d&range=1d"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            meta = data['chart']['result'][0]['meta']
            print(f"  {sym}: price={meta.get('regularMarketPrice')} {meta.get('currency')} | name={meta.get('shortName', sym)}")
    except Exception as e:
        print(f"  {sym}: Error {e}")

print("\n--- TESTING PAKISTAN STOCKS (Yahoo Finance) ---")
for sym in pakistan_symbols:
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}?interval=1d&range=1d"
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            meta = data['chart']['result'][0]['meta']
            print(f"  {sym}: price={meta.get('regularMarketPrice')} {meta.get('currency')} | name={meta.get('shortName', sym)}")
    except Exception as e:
        print(f"  {sym}: Error {e}")
