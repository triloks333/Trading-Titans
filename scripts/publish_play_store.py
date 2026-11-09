"""Uploads an AAB to the Play production track and rolls it out to 100%.

    python scripts/publish_play_store.py [path/to/app-release.aab]

Release name comes from app/pubspec.yaml, "What's new" from the first
### Play Store block in docs/release-notes.md, so nothing is retyped here.
"""
from __future__ import annotations

import pathlib
import re
import sys
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE = "com.kwm.tradingtitans"
ROOT = pathlib.Path(__file__).resolve().parents[1]
KEY = ROOT / ".antigravity/trading-titans-8375f-64a2cd65a182.json"
AAB_PATH = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "app/build/app/outputs/bundle/release/app-release.aab"
VERSION_NAME = re.search(r"^version:\s*([^+\s]+)", (ROOT / "app/pubspec.yaml").read_text(encoding="utf-8"), re.M).group(1)
NOTES = re.search(r"### Play Store.*?```\n(.*?)```", (ROOT / "docs/release-notes.md").read_text(encoding="utf-8"), re.S).group(1).strip()
assert 0 < len(NOTES) <= 500, f"What's new must be 1-500 chars, got {len(NOTES)}"

SCOPE = "https://www.googleapis.com/auth/androidpublisher"

if not KEY.exists():
    sys.exit(f"service account key not found at {KEY}")

if not AAB_PATH.exists():
    sys.exit(f"AAB bundle not found at {AAB_PATH}")

creds = service_account.Credentials.from_service_account_file(
    str(KEY), scopes=[SCOPE]
)
api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

print(f"Creating edit for {PACKAGE}...")
edit = api.edits().insert(body={}, packageName=PACKAGE).execute()
edit_id = edit["id"]
print(f"Edit ID: {edit_id}")

try:
    print(f"Uploading AAB ({AAB_PATH.stat().st_size / (1024*1024):.1f} MB)...")
    media = MediaFileUpload(str(AAB_PATH), mimetype="application/octet-stream", resumable=True)
    bundle_upload = api.edits().bundles().upload(
        packageName=PACKAGE,
        editId=edit_id,
        media_body=media,
    ).execute()
    version_code = bundle_upload["versionCode"]
    print(f"Uploaded AAB with versionCode: {version_code}")

    release_body = {
        "track": "production",
        "releases": [
            {
                "name": f"{version_code} ({VERSION_NAME})",
                "versionCodes": [str(version_code)],
                "status": "completed",
                "releaseNotes": [
                    {
                        "language": "en-US",
                        "text": NOTES
                    },
                    {
                        "language": "en-IN",
                        "text": NOTES
                    }
                ]
            }
        ]
    }

    print("Updating production track...")
    api.edits().tracks().update(
        packageName=PACKAGE,
        editId=edit_id,
        track="production",
        body=release_body,
    ).execute()

    print("Committing edit to rollout update on Play Store...")
    commit_res = api.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
    print("Successfully committed and rolled out on Play Store!")
    print(commit_res)

except Exception as e:
    print(f"Error during publishing: {e}")
    try:
        api.edits().delete(packageName=PACKAGE, editId=edit_id).execute()
    except Exception:
        pass
    sys.exit(1)
