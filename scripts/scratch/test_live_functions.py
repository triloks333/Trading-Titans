import urllib.request, json

url = 'https://bftvimnhpoiuoyryyiff.supabase.co'
anon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak'

tests = [
    'market=pakistan_stock&symbol=OGDC.KA',
    'market=italy_stock&symbol=ENI.MI',
    'market=fx&symbol=EURINR',
    'market=stock&symbol=RELIANCE',
    'market=crypto&symbol=BTC'
]

for q in tests:
    req = urllib.request.Request(f"{url}/functions/v1/market-quote?{q}", headers={'Authorization': f"Bearer {anon}"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read().decode('utf-8')
            print(f"SUCCESS {q} -> {data[:120]}")
    except urllib.error.HTTPError as e:
        print(f"HTTP ERROR {q} -> {e.code} : {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"FAILED {q} -> {e}")
