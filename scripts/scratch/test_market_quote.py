import requests
import json

url = "https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/market-quote"
headers = {
    "Content-Type": "application/json",
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak"
}

test_symbols = [
    "RELIANCE",
    "NSE:RELIANCE",
    "NSE:RELIANCE26DECFUT",
    "RELIANCE26DECFUT",
    "RELIANCE 29 Dec 26 FUT",
    "RELIANCE 26 DEC FUT",
    "RELIANCE-2026-10-27-3125-CE",
    "NSE:RELIANCE26OCTFUT"
]

for s in test_symbols:
    params = {"symbol": s, "market": "stock"}
    resp = requests.get(url, headers=headers, params=params)
    print(f"--- Symbol: {s} --- (Status: {resp.status_code})")
    try:
        data = resp.json()
        print(f"  price={data.get('price')}, name={data.get('name')}, is_fno={data.get('is_fno')}, type={data.get('instrument_type')}")
    except Exception:
        print("  raw text:", resp.text[:200])
