import urllib.request
import json

SUPABASE_URL = "https://bftvimnhpoiuoyryyiff.supabase.co"
ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak"

def query(endpoint):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    req = urllib.request.Request(url, headers={"apikey": ANON, "Authorization": f"Bearer {ANON}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

print("--- Instruments matching RELIANCE FUT ---")
try:
    res = query("instruments?symbol=ilike.*RELIANCE*&instrument_type=eq.FUTURE&limit=20")
    for r in res:
        print(f"symbol: {r['symbol']}, name: {r['name']}, expiry: {r.get('expiry_date')}, lot: {r.get('lot_size')}")
except Exception as e:
    print("Error:", e)

print("\n--- All FUTURE instruments for RELIANCE (any instrument_type) ---")
try:
    res = query("instruments?symbol=ilike.*RELIANCE*FUT*&limit=20")
    for r in res:
        print(f"symbol: {r['symbol']}, type: {r.get('instrument_type')}, name: {r['name']}")
except Exception as e:
    print("Error:", e)

print("\n--- Quotes cache for RELIANCE ---")
try:
    res = query("quotes_cache?symbol=ilike.*RELIANCE*&limit=20")
    for r in res:
        print(f"symbol: {r['symbol']}, price: {r.get('price')}, updated: {r.get('updated_at')}")
except Exception as e:
    print("Error:", e)
