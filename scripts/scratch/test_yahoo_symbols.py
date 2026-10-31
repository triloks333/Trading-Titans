import urllib.request, json

symbols = ['OGDC.KA', 'OGDC', 'LUCK.KA', 'LUCK', 'ENI.MI', 'ENI', 'RACE.MI', 'RACE']
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}

for sym in symbols:
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}?interval=1d&range=5d"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            meta = data.get('chart', {}).get('result', [{}])[0].get('meta', {})
            price = meta.get('regularMarketPrice')
            cur = meta.get('currency')
            print(f"YAHOO CHART {sym} -> price={price}, cur={cur}")
    except urllib.error.HTTPError as e:
        print(f"YAHOO CHART {sym} -> HTTP {e.code}")
    except Exception as e:
        print(f"YAHOO CHART {sym} -> {e}")
