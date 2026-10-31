import os
import subprocess
import time

ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\full_audit"

def adb_cmd(args):
    cmd = [ADB] + args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout.strip()

def screencap(filename):
    remote = f"/sdcard/{filename}"
    local = os.path.join(OUTPUT_DIR, filename)
    adb_cmd(["shell", "screencap", "-p", remote])
    subprocess.run([ADB, "pull", remote, local], capture_output=True, timeout=30)
    print(f"[SCREENSHOT] {filename}")
    return local

def tap(x, y, delay=1.5):
    adb_cmd(["shell", "input", "tap", str(x), str(y)])
    time.sleep(delay)

def swipe(x1, y1, x2, y2, duration=400, delay=1.5):
    adb_cmd(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(duration)])
    time.sleep(delay)

# We are on the Profile settings screen.
# 1. Tap Display Currency (approx y=575, x=500 in 17_home_news_section.png)
print("1. Tapping Display Currency...")
tap(500, 575, delay=2)
screencap("18_display_currency_modal.png")

# Tap back / close
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 2. Tap Preferred Markets (approx y=650, x=500 in 17_home_news_section.png)
print("2. Tapping Preferred Markets...")
tap(500, 650, delay=2)
screencap("19_preferred_markets_modal.png")

# Tap back / close
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 3. Tap Trading From (approx y=720, x=500 in 17_home_news_section.png)
print("3. Tapping Trading From...")
tap(500, 720, delay=2)
screencap("20_trading_from_country_modal.png")

# Tap back / close
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 4. Scroll UP on Profile screen to see Plans & top-ups
print("4. Scrolling UP to top of Profile screen...")
swipe(540, 600, 540, 1800, 400, delay=1.5)
screencap("21_profile_screen_top.png")

# Tap 'Plans & top-ups' (approx y=110 in 11_market_preferences_modal.png)
print("5. Tapping Plans & top-ups...")
tap(500, 110, delay=2.5)
screencap("22_plans_and_topups_screen.png")

# Scroll down on Plans & top-ups to see ₹29 pack
swipe(540, 1600, 540, 800, 400, delay=1.5)
screencap("23_plans_and_topups_scrolled.png")

print("=== SETTINGS & PLANS AUDIT COMPLETE ===")
