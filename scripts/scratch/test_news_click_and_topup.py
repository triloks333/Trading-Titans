import os
import sys
import subprocess
import time

sys.stdout.reconfigure(encoding='utf-8')

ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\live_flow"
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
    print(f"[SCREENSHOT] {filename}")
    return local

def tap(x, y, delay=2.0):
    adb_cmd(["shell", "input", "tap", str(x), str(y)])
    time.sleep(delay)

def swipe(x1, y1, x2, y2, dur=400, delay=1.5):
    adb_cmd(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(dur)])
    time.sleep(delay)

print("1. Tapping Italy Stocks News Card on Home...")
# Card is at (500, 1700)
tap(500, 1700, delay=2.5)
screencap("20_news_reader_italy.png")

# Scroll down to lock card
print("2. Scrolling to lock card...")
swipe(540, 1600, 540, 900, 300, delay=1.5)
screencap("21_news_reader_italy_lock.png")

# Tap 'Read Full Article on Website'
print("3. Tapping 'Read Full Article on Website'...")
# Button is at bottom around (540, 2220)
tap(540, 2220, delay=4.0)
screencap("22_chrome_website_article.png")

# Dump URL / Activity
act = adb_cmd(["shell", "dumpsys", "activity", "activities"])
for l in act.splitlines():
    if "topResumedActivity" in l or "mCurrentFocus" in l:
        print(f"   Activity: {l.strip()}")

# Go back to Trading Titans
print("4. Returning to Trading Titans app...")
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1.5)
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1.5)
screencap("23_back_in_app.png")

# 5. Tap Wallet Tab (x=620, y=2187)
print("5. Tapping Wallet Tab...")
tap(620, 2187, delay=2.0)
screencap("24_wallet_tab.png")

# 6. Tap 'Top Up Demo Capital' blue button (x=540, y=300 in 01_wallet_screen.png)
# Wait! In 01_wallet_screen.png, 'Top Up Demo Capital' button is between y=270 and y=320 (or bounds [108, 631][972, 757])
print("6. Tapping 'Top Up Demo Capital' button...")
tap(540, 694, delay=2.5)
screencap("25_topup_modal_packs.png")

# Scroll down inside top-up modal to view all packs
swipe(540, 1600, 540, 1000, 400, delay=1.5)
screencap("26_topup_modal_scrolled.png")

print("=== DONE ===")
