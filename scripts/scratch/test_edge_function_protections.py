import json
import pathlib
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]

url = anon_key = service_key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_ANON_KEY="):
        anon_key = line.split("=", 1)[1].strip().strip('"')
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        service_key = line.split("=", 1)[1].strip().strip('"')

def call_place_order(jwt, body):
    req = urllib.request.Request(
        f"{url}/functions/v1/place-order",
        headers={
            "Authorization": f"Bearer {jwt}",
            "apikey": anon_key,
            "Content-Type": "application/json"
        },
        data=json.dumps(body).encode("utf-8"),
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8", errors="ignore"))

# Get user email
admin_req = urllib.request.Request(
    f"{url}/auth/v1/admin/users/068fd8ef-27a2-495d-be98-36dd7958965d",
    headers={"apikey": service_key, "Authorization": f"Bearer {service_key}"}
)
user_data = json.loads(urllib.request.urlopen(admin_req).read())
email = user_data["email"]

# Generate magic link to acquire JWT session
link_req = urllib.request.Request(
    f"{url}/auth/v1/admin/generate_link",
    headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json"},
    data=json.dumps({"type": "magiclink", "email": email}).encode("utf-8"),
    method="POST"
)
link_data = json.loads(urllib.request.urlopen(link_req).read())
token_hash = link_data.get("hashed_token")

# Verify OTP to get JWT session
verify_req = urllib.request.Request(
    f"{url}/auth/v1/verify",
    headers={"apikey": anon_key, "Content-Type": "application/json"},
    data=json.dumps({"type": "magiclink", "token_hash": token_hash}).encode("utf-8"),
    method="POST"
)
try:
    session_data = json.loads(urllib.request.urlopen(verify_req).read())
    user_jwt = session_data["access_token"]
except urllib.error.HTTPError as e:
    print(f"Verify failed ({e.code}): {e.read().decode('utf-8')}")
    print("Action link was:", link_data.get("properties", {}).get("action_link"))
    import sys
    sys.exit(1)
print("Acquired test JWT for user.")

# TEST 1: Exorbitant quantity (5 trillion)
print("\n--- TEST 1: Exorbitant Quantity (5 Trillion Shares) ---")
status, resp = call_place_order(user_jwt, {
    "symbol": "RELIANCE",
    "market": "stock",
    "side": "buy",
    "quantity": 5000000000000,
    "instrumentType": "EQUITY"
})
print(f"Status: {status}, Response: {resp}")

# TEST 2: False exit order when holding doesn't exist
print("\n--- TEST 2: Fake Exit Order on Non-Existent Holding ---")
status, resp = call_place_order(user_jwt, {
    "symbol": "RELIANCE",
    "market": "stock",
    "side": "buy",
    "quantity": 10,
    "isExitOrder": True,
    "instrumentType": "EQUITY"
})
print(f"Status: {status}, Response: {resp}")

# TEST 3: Buy order exceeding wallet balance
print("\n--- TEST 3: Buy Order Exceeding Wallet Balance (50,000 shares ~INR 5.8 Crore when wallet has INR 10,000) ---")
status, resp = call_place_order(user_jwt, {
    "symbol": "RELIANCE",
    "market": "stock",
    "side": "buy",
    "quantity": 50000,
    "instrumentType": "EQUITY"
})
print("Status:", status, "Response:", json.dumps(resp).encode('ascii', 'backslashreplace').decode('ascii'))
