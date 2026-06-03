import os
import sys
import subprocess
import datetime
import hashlib
import time

# 1. Install missing dependencies automatically
def install_dependencies():
    required_packages = ["fyers-apiv3", "supabase", "python-dotenv", "pyotp", "requests"]
    missing_packages = []
    
    for pkg in required_packages:
        name = pkg.replace("-", "_")
        try:
            __import__(name)
        except ImportError:
            missing_packages.append(pkg)
            
    if missing_packages:
        print(f"Missing required packages: {missing_packages}. Installing them now...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", *missing_packages])
            print("Successfully installed dependencies.")
        except Exception as e:
            print(f"Error installing dependencies: {e}")
            sys.exit(1)

install_dependencies()

from dotenv import load_dotenv
from supabase import create_client
import pyotp
import requests

# 2. Load environment variables
if os.path.exists(".env"):
    load_dotenv(".env")
elif os.path.exists("backend/.env"):
    load_dotenv("backend/.env")

# 3. Retrieve secrets
FYERS_USERNAME = os.getenv("FYERS_USERNAME")  # e.g., FY12345
FYERS_PASSWORD = os.getenv("FYERS_PASSWORD")
FYERS_PIN = os.getenv("FYERS_PIN")            # 4-digit PIN
FYERS_TOTP_SECRET = os.getenv("FYERS_TOTP_SECRET") # 32-character TOTP key

FYERS_APP_ID = os.getenv("FYERS_APP_ID")      # App ID (e.g. 44FRVAERLU-200)
FYERS_SECRET_KEY = os.getenv("FYERS_SECRET_KEY")
FYERS_REDIRECT_URI = os.getenv("FYERS_REDIRECT_URI") or "http://127.0.0.1:5000/"

SUPABASE_URL = os.getenv("SUPABASE_URL") or "https://bftvimnhpoiuoyryyiff.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

# Validate required variables
required_vars = {
    "FYERS_USERNAME": FYERS_USERNAME,
    "FYERS_PASSWORD": FYERS_PASSWORD,
    "FYERS_PIN": FYERS_PIN,
    "FYERS_TOTP_SECRET": FYERS_TOTP_SECRET,
    "FYERS_APP_ID": FYERS_APP_ID,
    "FYERS_SECRET_KEY": FYERS_SECRET_KEY,
    "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
}

missing_vars = [k for k, v in required_vars.items() if not v]
if missing_vars:
    print("\nERROR: Missing required environment variables:")
    for mv in missing_vars:
        print(f" - {mv}")
    print("\nPlease define them in your .env file to enable automated Fyers login.")
    sys.exit(1)

print("Initiating automated headless Fyers login...")

try:
    # Fyers API v3 automated auth flow using Requests
    session = requests.Session()
    
    # Step 1: Send Client ID (send-otp)
    payload_send_otp = {"fy_id": FYERS_USERNAME, "app_id": "2"}
    res_otp = session.post("https://api.fyers.in/api/v3/send-otp", json=payload_send_otp)
    if res_otp.status_code != 200:
        raise Exception(f"Failed to send OTP request: {res_otp.text}")
        
    otp_data = res_otp.json()
    if otp_data.get("s") != "ok":
        raise Exception(f"Fyers send-otp response status not ok: {otp_data}")

    # Generate current TOTP code using the secret key
    totp = pyotp.TOTP(FYERS_TOTP_SECRET.replace(" ", ""))
    current_otp = totp.now()
    
    # Step 2: Verify OTP
    payload_verify_otp = {
        "fy_id": FYERS_USERNAME,
        "otp": current_otp,
        "app_id": "2"
    }
    res_verify = session.post("https://api.fyers.in/api/v3/verify-otp", json=payload_verify_otp)
    if res_verify.status_code != 200:
        raise Exception(f"Failed to verify OTP: {res_verify.text}")
        
    verify_data = res_verify.json()
    if verify_data.get("s") != "ok":
        raise Exception(f"Fyers verify-otp validation failed: {verify_data}")

    # Step 3: Verify PIN
    payload_verify_pin = {
        "fy_id": FYERS_USERNAME,
        "pin": FYERS_PIN,
        "app_id": "2"
    }
    res_pin = session.post("https://api.fyers.in/api/v3/verify-pin", json=payload_verify_pin)
    if res_pin.status_code != 200:
        raise Exception(f"Failed PIN verification: {res_pin.text}")
        
    pin_data = res_pin.json()
    if pin_data.get("s") != "ok":
        raise Exception(f"Fyers PIN validation failed: {pin_data}")

    # Get authorization code using the active session
    # Generate the OAuth redirect URL
    params = {
        "client_id": FYERS_APP_ID,
        "redirect_uri": FYERS_REDIRECT_URI,
        "response_type": "code",
        "state": "automation_state"
    }
    
    auth_url = f"https://api.fyers.in/api/v3/generate-authcode"
    res_auth = session.get(auth_url, params=params, allow_redirects=False)
    
    # The authorization code is returned in the redirect URL parameter
    redirect_url = res_auth.headers.get("Location")
    if not redirect_url:
        raise Exception("Failed to retrieve auth code redirect URL.")
        
    # Extract code from the URL
    from urllib.parse import urlparse, parse_qs
    parsed_url = urlparse(redirect_url)
    auth_code = parse_qs(parsed_url.query).get("code", [None])[0]
    
    if not auth_code:
        raise Exception(f"Auth code not found in redirect URL: {redirect_url}")

    print("Successfully generated authorization code. Exchanging for access token...")

    # Step 4: Validate Auth Code & Get Access Token
    app_id_hash = hashlib.sha256(f"{FYERS_APP_ID}:{FYERS_SECRET_KEY}".encode()).hexdigest()
    
    payload_token = {
        "grant_type": "authorization_code",
        "appIdHash": app_id_hash,
        "code": auth_code
    }
    
    res_token = requests.post("https://api.fyers.in/api/v3/validate-authcode", json=payload_token)
    if res_token.status_code != 200:
        raise Exception(f"Failed token exchange: {res_token.text}")
        
    token_data = res_token.json()
    if token_data.get("s") != "ok" or not token_data.get("access_token"):
        raise Exception(f"Token generation failed: {token_data}")
        
    access_token = token_data["access_token"]
    print("Successfully generated Fyers Access Token!")

    # Fyers tokens are valid for 24 hours
    expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).isoformat()

    # Initialize Supabase client
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    
    # Upsert access token to public.fyers_tokens
    print("Writing token to Supabase table 'fyers_tokens'...")
    supabase.table("fyers_tokens").upsert({
        "id": "main",
        "access_token": access_token,
        "expires_at": expires_at,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat()
    }).execute()
    
    print("\nSUCCESS: Fyers credentials refreshed successfully! Real-time NSE data is now active.")
    
except Exception as e:
    print(f"\nFATAL ERROR during Fyers autologin: {e}")
    sys.exit(1)
