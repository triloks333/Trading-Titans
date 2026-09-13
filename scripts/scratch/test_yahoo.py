import requests
import json

url = "https://query1.finance.yahoo.com/v8/finance/chart/TVSMOTOR-2026-06-25-3000-CE.NS?range=2d&interval=1d"
headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
}
response = requests.get(url, headers=headers)
print(f"Status Code: {response.status_code}")
try:
    print(json.dumps(response.json(), indent=2))
except Exception as e:
    print("Failed to parse JSON response:", response.text)
