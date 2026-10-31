import os
import sys
import subprocess
import time

sys.stdout.reconfigure(encoding='utf-8')
ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\live_flow"

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

# 1. Tap Wallet tab in bottom bar
print("1. Tapping Wallet tab (x=620, y=2187)...")
adb_cmd(["shell", "input", "tap", "620", "2187"])
time.sleep(2)
screencap("30_wallet_tab.png")

# 2. Tap 'Top Up Demo Capital' blue button (center: 540, 300 or 540, 694 depending on scroll)
# In 01_wallet_screen.png, the blue button was clearly visible!
# Let's tap bounds [108, 631][972, 757] -> (540, 694)
print("2. Tapping 'Top Up Demo Capital' button (540, 694)...")
adb_cmd(["shell", "input", "tap", "540", "694"])
time.sleep(2.5)
screencap("31_subscribe_screen_tab1.png")

# In subscribe screen, if it opened on Tab 0, let's tap Tab 1 'Top-Up Capital' (x=750, y=140)
print("3. Tapping Top-Up Capital tab pill (x=750, y=140)...")
adb_cmd(["shell", "input", "tap", "750", "140"])
time.sleep(2)
screencap("32_topup_tab_mini_pack.png")

# Scroll down to see full pack details
adb_cmd(["shell", "input", "swipe", "540", "1600", "540", "1000", "400"])
time.sleep(1.5)
screencap("33_topup_tab_scrolled.png")

print("Done")
