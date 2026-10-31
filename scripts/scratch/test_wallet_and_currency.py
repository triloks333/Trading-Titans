import os
import subprocess
import time

ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
SERIAL = "adb-RZCX91T406D-5onACz._adb-tls-connect._tcp"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\feature_test"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def adb_cmd(args):
    cmd = [ADB, "-s", SERIAL] + args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout.strip()

def screencap(filename):
    remote = f"/sdcard/{filename}"
    local = os.path.join(OUTPUT_DIR, filename)
    adb_cmd(["shell", "screencap", "-p", remote])
    subprocess.run([ADB, "-s", SERIAL, "pull", remote, local], capture_output=True, timeout=30)
    print(f"Captured: {filename}")
    return local

print("1. Launching Trading Titans...")
adb_cmd(["shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "-n", "com.kwm.tradingtitans/.MainActivity"])
time.sleep(3)

# 2. Go to Wallet tab
print("2. Opening Wallet tab...")
adb_cmd(["shell", "input", "tap", "575", "2170"])
time.sleep(2)
screencap("01_wallet_tab.png")

# 3. Tap Top Up button to check the 29rs pack
print("3. Tapping Top Up Demo Capital button...")
adb_cmd(["shell", "input", "tap", "500", "300"])
time.sleep(2)
screencap("02_topup_modal.png")

# Close top-up modal
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 4. Go to Profile tab
print("4. Opening Profile tab...")
adb_cmd(["shell", "input", "tap", "865", "2170"])
time.sleep(2)
screencap("03_profile_tab.png")

# Scroll down to see Currency and Settings
print("5. Scrolling down in Profile...")
adb_cmd(["shell", "input", "swipe", "540", "1800", "540", "800", "300"])
time.sleep(1)
screencap("04_profile_scrolled.png")

# 6. Test App Restart Persistence
print("6. Testing App Restart Persistence...")
adb_cmd(["shell", "am", "force-stop", "com.kwm.tradingtitans"])
time.sleep(2)
adb_cmd(["shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "-n", "com.kwm.tradingtitans/.MainActivity"])
time.sleep(4)
screencap("05_after_restart_home.png")

# Check Trade tab after restart
print("7. Checking Trade tab after restart...")
adb_cmd(["shell", "input", "tap", "275", "2170"])
time.sleep(2)
screencap("06_after_restart_trade.png")

print("All tests completed successfully!")
