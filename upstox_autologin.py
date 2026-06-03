import os
import sys
import subprocess
import datetime

# 1. Install missing dependencies automatically
def install_dependencies():
    required_packages = ["upstox-totp", "supabase", "python-dotenv"]
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
from upstox_totp import UpstoxTOTP

# 2. Load environment variables
# Look in root .env first, then backend/.env
if os.path.exists(".env"):
    load_dotenv(".env")
elif os.path.exists("backend/.env"):
    load_dotenv("backend/.env")
else:
    print("WARNING: No .env file found in root or backend/ folder. Loading system environment variables.")

# 3. Retrieve secrets
UPSTOX_USERNAME = os.getenv("UPSTOX_USERNAME")
UPSTOX_PASSWORD = os.getenv("UPSTOX_PASSWORD")
UPSTOX_PIN_CODE = os.getenv("UPSTOX_PIN_CODE")
UPSTOX_TOTP_SECRET = os.getenv("UPSTOX_TOTP_SECRET")

UPSTOX_CLIENT_ID = os.getenv("UPSTOX_CLIENT_ID") or os.getenv("UPSTOX_API_KEY")
UPSTOX_CLIENT_SECRET = os.getenv("UPSTOX_CLIENT_SECRET") or os.getenv("UPSTOX_API_SECRET")
UPSTOX_REDIRECT_URI = os.getenv("UPSTOX_REDIRECT_URI")

SUPABASE_URL = os.getenv("SUPABASE_URL") or "https://bftvimnhpoiuoyryyiff.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

# Validate required variables
required_vars = {
    "UPSTOX_USERNAME": UPSTOX_USERNAME,
    "UPSTOX_PASSWORD": UPSTOX_PASSWORD,
    "UPSTOX_PIN_CODE": UPSTOX_PIN_CODE,
    "UPSTOX_TOTP_SECRET": UPSTOX_TOTP_SECRET,
    "UPSTOX_CLIENT_ID / UPSTOX_API_KEY": UPSTOX_CLIENT_ID,
    "UPSTOX_CLIENT_SECRET / UPSTOX_API_SECRET": UPSTOX_CLIENT_SECRET,
    "UPSTOX_REDIRECT_URI": UPSTOX_REDIRECT_URI,
    "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
}

missing_vars = [k for k, v in required_vars.items() if not v]
if missing_vars:
    print("\nERROR: Missing required environment variables:")
    for mv in missing_vars:
        print(f" - {mv}")
    print("\nPlease define them in your .env file or environment.")
    sys.exit(1)

# Ensure upstox-totp library sees variables under its expected names
os.environ["UPSTOX_USERNAME"] = UPSTOX_USERNAME
os.environ["UPSTOX_PASSWORD"] = UPSTOX_PASSWORD
os.environ["UPSTOX_PIN_CODE"] = UPSTOX_PIN_CODE
os.environ["UPSTOX_TOTP_SECRET"] = UPSTOX_TOTP_SECRET
os.environ["UPSTOX_CLIENT_ID"] = UPSTOX_CLIENT_ID
os.environ["UPSTOX_CLIENT_SECRET"] = UPSTOX_CLIENT_SECRET
os.environ["UPSTOX_REDIRECT_URI"] = UPSTOX_REDIRECT_URI

print("Initiating automated Upstox login...")

try:
    # Initialize UpstoxTOTP auth client
    upx = UpstoxTOTP()
    
    # Perform headless login and fetch access token
    response = upx.app_token.get_access_token()
    
    if not response.success or not response.data:
        raise Exception(f"Login failed: {response.message if hasattr(response, 'message') else response}")
        
    access_token = response.data.access_token
    print("Successfully authenticated with Upstox!")
    
    # Calculate expiry (3:30 AM IST next day)
    now = datetime.datetime.now(datetime.timezone.utc)
    ist_offset = datetime.timedelta(hours=5, minutes=30)
    now_ist = now + ist_offset
    cutoff = now_ist.replace(hour=3, minute=30, second=0, microsecond=0)
    if now_ist >= cutoff:
        cutoff += datetime.timedelta(days=1)
    
    expires_at = (cutoff - ist_offset).isoformat()
    
    print(f"Token Expiry calculated as: {expires_at} (3:30 AM IST)")
    
    # Initialize Supabase client
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    
    # Upsert access token to public.upstox_tokens
    print("Writing token to Supabase table 'upstox_tokens'...")
    db_res = supabase.table("upstox_tokens").upsert({
        "id": "main",
        "access_token": access_token,
        "expires_at": expires_at,
        "created_at": now.isoformat()
    }).execute()
    
    print("\nSUCCESS: Upstox credentials refreshed successfully! Real-time feeds are active.")
    
except Exception as e:
    print(f"\nFATAL ERROR during Upstox autologin: {e}")
    sys.exit(1)
