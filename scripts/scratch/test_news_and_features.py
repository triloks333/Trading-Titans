import os
import subprocess
import time

ADB = r"C:\Users\manav\AppData\Local\Android\Sdk\platform-tools\adb.exe"
SERIAL = "adb-RZCX91T406D-5onACz._adb-tls-connect._tcp"
OUTPUT_DIR = r"c:\Users\manav\startups\Trading-Titans\scratch\screenshots\news_test"

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

# Tap Home tab to be sure
adb_cmd(["shell", "input", "tap", "135", "2170"])
time.sleep(1)

print("2. Scrolling to Market Intel & News on Home...")
adb_cmd(["shell", "input", "swipe", "540", "1800", "540", "800", "400"])
time.sleep(2)
screencap("01_home_news_carousel.png")

# Tap first visible news card
print("3. Tapping first news card...")
adb_cmd(["shell", "input", "tap", "500", "1720"])
time.sleep(2)
screencap("02_news_reader_card1.png")

# Scroll down inside the reader screen to see the lock box clearly
adb_cmd(["shell", "input", "swipe", "540", "1600", "540", "900", "300"])
time.sleep(1)
screencap("03_news_reader_lock_visible.png")

# Tap 'Read Full Article on Website' button
# In screen_04_news_reader.png, the button was near the bottom
print("4. Tapping 'Read Full Article on Website'...")
# Tap the blue button at approx (500, 2220) or (500, 2180)
adb_cmd(["shell", "input", "tap", "500", "2200"])
time.sleep(4)

print("5. Checking browser destination...")
screencap("04_browser_destination.png")
focus = adb_cmd(["shell", "dumpsys", "activity", "activities"])
for line in focus.splitlines():
    if "topResumedActivity" in line or "mCurrentFocus" in line or "ResumedActivity" in line:
        print("  ", line.strip())

# Go back to Trading Titans
print("6. Returning to Trading Titans...")
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(2)

# Verify we're back on Home
screencap("05_back_on_home.png")

# Swipe carousel horizontally to see other market news
print("7. Swiping news carousel horizontally...")
adb_cmd(["shell", "input", "swipe", "850", "1720", "200", "1720", "400"])
time.sleep(2)
screencap("06_carousel_swiped.png")

# Tap the second news card
print("8. Tapping next news card...")
adb_cmd(["shell", "input", "tap", "500", "1720"])
time.sleep(2)
screencap("07_news_reader_card2.png")

# Go back
adb_cmd(["shell", "input", "keyevent", "4"])
time.sleep(1)

print("Test complete!")
