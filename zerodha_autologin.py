import os
import sys
import subprocess
import datetime
import hashlib
import time

# 1. Install missing dependencies automatically
def install_dependencies():
    required_packages = ["supabase", "python-dotenv", "pyotp", "requests"]
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
from urllib.parse import urlparse, parse_qs

# 2. Load environment variables
if os.path.exists(".env"):
    load_dotenv(".env")
elif os.path.exists("backend/.env"):
    load_dotenv("backend/.env")

# 3. Retrieve secrets
ZERODHA_USERNAME = os.getenv("ZERODHA_USERNAME")
ZERODHA_PASSWORD = os.getenv("ZERODHA_PASSWORD")
ZERODHA_TOTP_SECRET = os.getenv("ZERODHA_TOTP_SECRET")

ZERODHA_API_KEY = os.getenv("ZERODHA_API_KEY") or "0pfnq24r6pgjpr2j"
ZERODHA_API_SECRET = os.getenv("ZERODHA_API_SECRET") or "nczc2z30hlamkjofnzn1554172ebgzgt"

SUPABASE_URL = os.getenv("SUPABASE_URL") or "https://bftvimnhpoiuoyryyiff.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

# Validate required variables (TOTP Secret is optional; if missing, we will prompt for TOTP input)
required_vars = {
    "ZERODHA_USERNAME": ZERODHA_USERNAME,
    "ZERODHA_PASSWORD": ZERODHA_PASSWORD,
    "ZERODHA_API_KEY": ZERODHA_API_KEY,
    "ZERODHA_API_SECRET": ZERODHA_API_SECRET,
    "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
}

missing_vars = [k for k, v in required_vars.items() if not v]
if missing_vars:
    print("\nERROR: Missing required environment variables:")
    for mv in missing_vars:
        print(f" - {mv}")
    print("\nPlease define them in your .env file to enable automated Zerodha login.")
    sys.exit(1)

print(f"Initiating automated headless Zerodha login for user {ZERODHA_USERNAME}...")

try:
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    })
    
    # Step 1: Submit Username & Password
    payload_login = {
        "user_id": ZERODHA_USERNAME,
        "password": ZERODHA_PASSWORD
    }
    
    res_login = session.post("https://kite.zerodha.com/api/login", data=payload_login)
    if res_login.status_code != 200:
        raise Exception(f"Username/password submission failed: {res_login.text}")
        
    login_data = res_login.json()
    if login_data.get("status") != "success":
        raise Exception(f"Zerodha login initiation failed: {login_data}")
        
    request_id = login_data["data"]["request_id"]
    
    # Step 2: Generate or Prompt for TOTP code
    totp_code = None
    if ZERODHA_TOTP_SECRET and ZERODHA_TOTP_SECRET.strip():
        try:
            # Try to generate TOTP code automatically
            clean_secret = ZERODHA_TOTP_SECRET.strip().replace(" ", "")
            totp = pyotp.TOTP(clean_secret)
            totp_code = totp.now()
            print("Generated TOTP code automatically using ZERODHA_TOTP_SECRET.")
        except Exception as e:
            print(f"Warning: Failed to generate TOTP automatically ({e}). Falling back to manual entry.")
            totp_code = None

    if not totp_code:
        totp_code = input("Please enter the 6-digit TOTP code from your Authenticator app: ").strip()
        while len(totp_code) != 6 or not totp_code.isdigit():
            totp_code = input("Invalid code. Please enter a 6-digit numeric TOTP code: ").strip()
    
    payload_twofa = {
        "user_id": ZERODHA_USERNAME,
        "request_id": request_id,
        "twofa_value": totp_code,
        "twofa_type": "totp"
    }
    
    res_twofa = session.post("https://kite.zerodha.com/api/twofa", data=payload_twofa)
    if res_twofa.status_code != 200:
        raise Exception(f"TOTP submission failed: {res_twofa.text}")
        
    twofa_data = res_twofa.json()
    if twofa_data.get("status") != "success":
        raise Exception(f"Zerodha 2FA check failed: {twofa_data}")
        
    print("Logged in successfully to Kite session. Initiating OAuth callback...")
    
    # Step 3: Call authorization url to trigger callback redirect
    auth_url = f"https://kite.zerodha.com/connect/login?api_key={ZERODHA_API_KEY}&v=3"
    res_auth = session.get(auth_url, allow_redirects=False)
    
    redirect_url = res_auth.headers.get("Location")
    if not redirect_url:
        # Check if we got a 200 OK because of an already active session
        if res_auth.status_code == 200:
            raise Exception("Already logged in, but no redirect location returned.")
        raise Exception(f"Failed to retrieve auth code redirect URL (Status: {res_auth.status_code}).")
        
    # Extract request_token from query parameters
    parsed_url = urlparse(redirect_url)
    query_params = parse_qs(parsed_url.query)
    request_token = query_params.get("request_token", [None])[0]
    
    if not request_token:
        raise Exception(f"request_token not found in callback redirect URL: {redirect_url}")
        
    print("Retrieved request token successfully. Generating access token...")
    
    # Step 4: Exchange request_token for access_token via API
    checksum_str = ZERODHA_API_KEY + request_token + ZERODHA_API_SECRET
    checksum = hashlib.sha256(checksum_str.encode()).hexdigest()
    
    payload_token = {
        "api_key": ZERODHA_API_KEY,
        "request_token": request_token,
        "checksum": checksum
    }
    
    res_token = requests.post("https://api.kite.trade/session/token", data=payload_token, headers={
        "X-Kite-Version": "3"
    })
    
    if res_token.status_code != 200:
        raise Exception(f"Token exchange API call failed: {res_token.text}")
        
    token_data = res_token.json()
    if token_data.get("status") != "success" or not token_data.get("data", {}).get("access_token"):
        raise Exception(f"Token exchange response unsuccessful: {token_data}")
        
    access_token = token_data["data"]["access_token"]
    print("Successfully generated Zerodha Connect Access Token!")
    
    # Calculate expiry: 6:00 AM IST next day
    now = datetime.datetime.now(datetime.timezone.utc)
    ist_offset = datetime.timedelta(hours=5, minutes=30)
    now_ist = now + ist_offset
    cutoff = now_ist.replace(hour=6, minute=0, second=0, microsecond=0)
    if now_ist >= cutoff:
        cutoff += datetime.timedelta(days=1)
    
    expires_at = (cutoff - ist_offset).isoformat()
    
    # Initialize Supabase client
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    
    # Upsert access token to public.kite_tokens
    print("Writing token to Supabase table 'kite_tokens'...")
    supabase.table("kite_tokens").upsert({
        "id": "main",
        "access_token": access_token,
        "expires_at": expires_at,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat()
    }).execute()
    
    print("\nSUCCESS: Zerodha Kite Connect credentials refreshed successfully! Real-time NSE data is now active.")
    
except Exception as e:
    print(f"\nFATAL ERROR during Zerodha autologin: {e}")
    sys.exit(1)
