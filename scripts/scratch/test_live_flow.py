import os
import sys
import subprocess
import time
import xml.etree.ElementTree as ET

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

def dump_ui(label):
    adb_cmd(["shell", "uiautomator", "dump", "/sdcard/v.xml"])
    xml_path = os.path.join(OUTPUT_DIR, f"{label}.xml")
    subprocess.run([ADB, "pull", "/sdcard/v.xml", xml_path], capture_output=True, timeout=30)
    tree = ET.parse(xml_path)
    nodes = []
    def walk(node):
        d = node.attrib.get('content-desc', '')
        t = node.attrib.get('text', '')
        b = node.attrib.get('bounds', '')
        if d or t:
            nodes.append((t, d, b))
        for c in node:
            walk(c)
    walk(tree.getroot())
    return nodes

def tap_bounds(b_str, delay=1.5):
    # b_str is "[x1,y1][x2,y2]"
    parts = b_str.replace("][", ",").replace("[", "").replace("]", "").split(",")
    x1, y1, x2, y2 = map(int, parts)
    cx = (x1 + x2) // 2
    cy = (y1 + y2) // 2
    adb_cmd(["shell", "input", "tap", str(cx), str(cy)])
    time.sleep(delay)

def tap(x, y, delay=1.5):
    adb_cmd(["shell", "input", "tap", str(x), str(y)])
    time.sleep(delay)

def swipe(x1, y1, x2, y2, dur=400, delay=1.5):
    adb_cmd(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(dur)])
    time.sleep(delay)

print("=== STARTING LIVE AUDIT FLOW ===")

# 1. Tap Wallet tab (center 620, 2187)
print("1. Tapping Wallet tab...")
tap(620, 2187, delay=2.5)
screencap("01_wallet_screen.png")
wallet_nodes = dump_ui("01_wallet")
for t, d, b in wallet_nodes:
    if any(k in (t+d).lower() for k in ["cash", "balance", "₹29", "29", "top", "pack", "11,000", "11000", "add"]):
        print(f"   Wallet node: text='{t}' desc='{d}' bounds={b}")

# Scroll down on wallet to see top-up packs
swipe(540, 1600, 540, 800, 400, delay=1.5)
screencap("02_wallet_scrolled.png")
wallet_scroll_nodes = dump_ui("02_wallet_scrolled")
for t, d, b in wallet_scroll_nodes:
    if any(k in (t+d).lower() for k in ["29", "top", "pack", "11,000", "11000", "starter"]):
        print(f"   Wallet pack node: text='{t}' desc='{d}' bounds={b}")

# 2. Go to Profile (center 940, 2187)
print("\n2. Going to Profile tab...")
tap(940, 2187, delay=2)
# Scroll to settings section
swipe(540, 1800, 540, 900, 400, delay=1.5)
screencap("03_profile_settings.png")
prof_nodes = dump_ui("03_profile_settings")

# Find 'Display Currency'
curr_bounds = None
pref_bounds = None
for t, d, b in prof_nodes:
    if "Display Currency" in d:
        curr_bounds = b
        print(f"   Found Display Currency at {b}")
    if "Preferred Markets" in d:
        pref_bounds = b
        print(f"   Found Preferred Markets at {b}")

if curr_bounds:
    print("\n3. Opening Display Currency modal...")
    tap_bounds(curr_bounds, delay=2)
    screencap("04_currency_modal.png")
    curr_nodes = dump_ui("04_currency_modal")
    for t, d, b in curr_nodes:
        if any(c in (t+d).lower() for c in ["rupee", "dollar", "euro", "pakistan", "pkr", "eur", "inr", "usd"]):
            print(f"   Currency option: text='{t}' desc='{d}' bounds={b}")
    # Tap Pakistani Rupee if present
    pkr_bound = next((b for t, d, b in curr_nodes if "Pakistani Rupee" in (t+d) or "PKR" in (t+d)), None)
    if pkr_bound:
        print("   Selecting Pakistani Rupee...")
        tap_bounds(pkr_bound, delay=2)
    else:
        # Close dialog
        adb_cmd(["shell", "input", "keyevent", "4"])
        time.sleep(1)

screencap("05_after_currency_select.png")

# Re-read profile settings
prof_nodes2 = dump_ui("05_profile_after_curr")
for t, d, b in prof_nodes2:
    if "Preferred Markets" in d:
        pref_bounds = b

if pref_bounds:
    print("\n4. Opening Preferred Markets modal from Profile...")
    tap_bounds(pref_bounds, delay=2)
    screencap("06_preferred_markets_modal.png")
    mkt_nodes = dump_ui("06_pref_markets")
    for t, d, b in mkt_nodes:
        if any(m in (t+d).lower() for m in ["indian", "crypto", "us", "pakistan", "italy", "save", "select"]):
            print(f"   Market option: text='{t}' desc='{d}' bounds={b}")
    # Tap Close / Save
    save_bound = next((b for t, d, b in mkt_nodes if "Save" in (t+d) or "Done" in (t+d)), None)
    if save_bound:
        tap_bounds(save_bound, delay=2)
    else:
        adb_cmd(["shell", "input", "keyevent", "4"])
        time.sleep(1)

# 5. Go to Home (center 140, 2187)
print("\n5. Navigating to Home tab...")
tap(140, 2187, delay=2.5)
screencap("07_home_top.png")

# Scroll down to Market Intel & News
print("6. Scrolling to Market Intel & News...")
swipe(540, 1800, 540, 800, 400, delay=2)
screencap("08_home_news_carousel.png")
home_nodes = dump_ui("08_home_news")
for t, d, b in home_nodes:
    if any(k in (t+d).lower() for k in ["intel", "news", "nifty", "bitcoin", "read", "market"]):
        print(f"   News section node: text='{t}' desc='{d}' bounds={b}")

# Tap first news card
news_card_bound = next((b for t, d, b in home_nodes if any(k in (t+d).lower() for k in ["nifty", "bitcoin", "record", "rally", "surges", "pakistan", "italy", "market"])), None)
if news_card_bound:
    print(f"   Tapping news card at {news_card_bound}...")
    tap_bounds(news_card_bound, delay=2.5)
else:
    print("   Tapping default news card location (500, 1600)...")
    tap(500, 1600, delay=2.5)

screencap("09_news_reader.png")

# Scroll down to lock card
swipe(540, 1600, 540, 900, 300, delay=1.5)
screencap("10_news_reader_lock.png")
reader_nodes = dump_ui("10_news_reader")
for t, d, b in reader_nodes:
    if any(k in (t+d).lower() for k in ["full", "website", "lock", "continue", "analysis"]):
        print(f"   Reader lock node: text='{t}' desc='{d}' bounds={b}")

# Tap Read Full Article on Website
read_website_bound = next((b for t, d, b in reader_nodes if "website" in (t+d).lower() or "read full" in (t+d).lower()), None)
if read_website_bound:
    print(f"   Tapping 'Read Full Article on Website' at {read_website_bound}...")
    tap_bounds(read_website_bound, delay=4)
else:
    print("   Tapping default 'Read Full Article' location (500, 2200)...")
    tap(500, 2200, delay=4)

screencap("11_browser_opened.png")

# Check browser URL or activity
act = adb_cmd(["shell", "dumpsys", "activity", "activities"])
for l in act.splitlines():
    if "topResumedActivity" in l or "mCurrentFocus" in l:
        print(f"   Current activity: {l.strip()}")

print("\n=== LIVE FLOW AUDIT COMPLETED ===")
