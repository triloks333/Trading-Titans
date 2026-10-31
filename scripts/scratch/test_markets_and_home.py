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

# 1. Tap 'Change Market Preferences' from the open menu
print("1. Tapping 'Change Market Preferences'...")
tap(650, 95, delay=2)
screencap("11_market_preferences_modal.png")

# Close preferences dialog by tapping Save or outside
tap(540, 1850, delay=1.5)

# 2. Tap Pakistan Stocks Tab (x=795, y=150)
print("2. Tapping Pakistan Stocks tab...")
tap(795, 150, delay=2.5)
screencap("12_pakistan_stocks_list.png")

# 3. Tap on first Pakistan stock (OGDC) to open StockActionSheet
print("3. Tapping first Pakistan stock...")
tap(500, 360, delay=2)
screencap("13_pakistan_stock_action_sheet.png")

# Close action sheet
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 4. Tap Italy Stocks Tab (x=900, y=150)
print("4. Tapping Italy Stocks tab...")
tap(900, 150, delay=2.5)
screencap("14_italy_stocks_list.png")

# 5. Tap on first Italy stock (ENI) to open StockActionSheet
print("5. Tapping first Italy stock...")
tap(500, 360, delay=2)
screencap("15_italy_stock_action_sheet.png")

# Close action sheet
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

# 6. Tap HOME tab (x=130, y=2250)
print("6. Navigating to Home tab...")
tap(130, 2250, delay=2.5)
screencap("16_home_screen_top.png")

# 7. Scroll down to reveal Market Intel & News
print("7. Scrolling down to Market Intel & News...")
swipe(540, 1800, 540, 700, 400, delay=2)
screencap("17_home_news_section.png")

print("=== SCRIPT FINISHED ===")
