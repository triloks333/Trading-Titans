import os
import subprocess
import time
import json

ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\full_audit"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def adb_cmd(args):
    cmd = [ADB] + args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout.strip()

def screencap(filename):
    remote = f"/sdcard/{filename}"
    local = os.path.join(OUTPUT_DIR, filename)
    adb_cmd(["shell", "screencap", "-p", remote])
    subprocess.run([ADB, "pull", remote, local], capture_output=True, timeout=30)
    print(f"[SCREENSHOT] {filename} -> {local}")
    return local

def tap(x, y, delay=1.5):
    adb_cmd(["shell", "input", "tap", str(x), str(y)])
    time.sleep(delay)

def swipe(x1, y1, x2, y2, duration=400, delay=1.5):
    adb_cmd(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(duration)])
    time.sleep(delay)

def keyevent(code, delay=1.0):
    adb_cmd(["shell", "input", "keyevent", str(code)])
    time.sleep(delay)

print("=== STARTING FULL TESTING AUDIT ON SAMSUNG S23 ===")

# Step 1: Launch App
print("\n--- STEP 1: Launching Trading Titans ---")
adb_cmd(["shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "-n", "com.kwm.tradingtitans/.MainActivity"])
time.sleep(3)
screencap("01_app_home_launch.png")

# Step 2: Test Home News Carousel
print("\n--- STEP 2: Scrolling to Market Intel & News Carousel ---")
# Scroll down on home screen to reveal News section
swipe(540, 1800, 540, 800, 400, delay=2)
screencap("02_home_news_carousel.png")

# Step 3: Click a news card
print("\n--- STEP 3: Tapping News Card 1 ---")
tap(500, 1720, delay=2)
screencap("03_news_reader_screen.png")

# Scroll down inside the reader screen to see the lock card
swipe(540, 1600, 540, 900, 300, delay=1.5)
screencap("04_news_reader_lock_card.png")

# Go back to home
print("\n--- Going back to Home ---")
keyevent(4, delay=2) # Back key
screencap("05_back_to_home.png")

# Step 4: Test Trade Screen
print("\n--- STEP 4: Navigating to Trade Screen ---")
# Trade tab is usually at index 1 in bottom bar (x=378, y=2170)
tap(378, 2170, delay=2.5)
screencap("06_trade_screen.png")

# Step 5: Test Market Selector Dialog
print("\n--- STEP 5: Testing Market Preferences Dialog ---")
# Tap the 3 dots or preferences button in top bar (x=980, y=180 or top right)
tap(990, 180, delay=2)
screencap("07_market_preferences_dialog.png")

# Close preferences dialog
tap(540, 1850, delay=1.5) # Save/Done or close
screencap("08_trade_screen_after_pref.png")

# Step 6: Test Wallet / Top-up Screen (₹29 for 11,000 demo cash)
print("\n--- STEP 6: Navigating to Wallet / Profile Screen ---")
# Profile tab is index 3 (x=945, y=2170) or Wallet via top bar
tap(945, 2170, delay=2.5)
screencap("09_profile_screen.png")

# Check Wallet / Top up button
swipe(540, 1600, 540, 900, 400, delay=1.5)
screencap("10_profile_scrolled.png")

print("=== PARTIAL AUDIT RUN COMPLETE ===")
