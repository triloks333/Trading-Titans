import urllib.request, json

url = 'https://bftvimnhpoiuoyryyiff.supabase.co'
anon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak'

pakistan_symbols = ['OGDC.KA', 'LUCK.KA', 'MCB.KA', 'SYS.KA', 'HBL.KA', 'ENGRO.KA', 'HUBC.KA', 'FFC.KA']
italy_symbols = ['ENI.MI', 'RACE.MI', 'ISP.MI', 'UCG.MI', 'STLAM.MI', 'ENEL.MI', 'G.MI', 'PRY.MI']

print("Testing Pakistan symbols:")
for sym in pakistan_symbols:
    req = urllib.request.Request(f"{url}/functions/v1/market-quote?market=pakistan_stock&symbol={sym}", headers={'Authorization': f"Bearer {anon}"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"  {sym}: price={data.get('price')} {data.get('currency')} change={data.get('change_pct')}%")
    except Exception as e:
        print(f"  {sym}: FAILED {e}")

print("\nTesting Italy symbols:")
for sym in italy_symbols:
    req = urllib.request.Request(f"{url}/functions/v1/market-quote?market=italy_stock&symbol={sym}", headers={'Authorization': f"Bearer {anon}"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"  {sym}: price={data.get('price')} {data.get('currency')} change={data.get('change_pct')}%")
    except Exception as e:
        print(f"  {sym}: FAILED {e}")
