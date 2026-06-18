import requests
import json

url = "https://bftvimnhpoiuoyryyiff.supabase.co/functions/v1/market-quote"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak"
}

params = {
    "symbol": "RELIANCE",
    "market": "stock"
}

response = requests.get(url, headers=headers, params=params)
print(f"Status Code: {response.statusCode if hasattr(response, 'statusCode') else response.status_code}")
try:
    print(json.dumps(response.json(), indent=2))
except Exception as e:
    print("Failed to parse JSON response:", response.text)
