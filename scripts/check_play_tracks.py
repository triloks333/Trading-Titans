"""Reports which Play tracks have a live release, and their status.

Answers "why is there no Install button?" definitively instead of guessing:
a release sitting only in internal/closed testing, or a listing still in
pre-registration, shows no Install button to ordinary users.

Requires the service account to be granted access in Play Console
(Users and permissions -> invite the service account email). If it has not been
granted, this exits with a clear message rather than a stack trace.

    python scripts/check_play_tracks.py
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys

PACKAGE = "com.kwm.tradingtitans"
KEY = pathlib.Path(__file__).resolve().parents[1] / (
    "secrets/trading-titans-498803-2ebd82f2f13a.json"
)


def ensure(mod: str, pip_name: str | None = None):
    try:
        __import__(mod)
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", pip_name or mod]
        )


ensure("google.oauth2", "google-auth")
ensure("googleapiclient", "google-api-python-client")

from google.oauth2 import service_account  # noqa: E402
from googleapiclient.discovery import build  # noqa: E402
from googleapiclient.errors import HttpError  # noqa: E402

SCOPE = "https://www.googleapis.com/auth/androidpublisher"

if not KEY.exists():
    sys.exit(f"service account key not found at {KEY}")

creds = service_account.Credentials.from_service_account_file(
    str(KEY), scopes=[SCOPE]
)
api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

try:
    edit = api.edits().insert(body={}, packageName=PACKAGE).execute()
except HttpError as e:
    detail = ""
    try:
        detail = json.loads(e.content.decode())["error"]["message"]
    except Exception:
        detail = str(e)[:300]
    sys.exit(
        "Could not reach the Play Developer API.\n"
        f"  {detail}\n\n"
        "Most likely this service account has not been granted access in Play\n"
        "Console (Users and permissions), or the Play Developer API is not\n"
        "enabled for the GCP project. This key was probably created for Firebase\n"
        "messaging, not Play publishing."
    )

edit_id = edit["id"]
try:
    tracks = api.edits().tracks().list(
        packageName=PACKAGE, editId=edit_id
    ).execute()
    print("Tracks with releases:\n")
    for t in tracks.get("tracks", []):
        print(f"  track: {t['track']}")
        for r in t.get("releases", []):
            frac = r.get("userFraction")
            print(
                f"    status={r.get('status'):12s} "
                f"name={r.get('name')} "
                f"versionCodes={r.get('versionCodes')} "
                f"rollout={'100%' if frac is None else f'{frac * 100:.0f}%'}"
            )
        print()
finally:
    try:
        api.edits().delete(packageName=PACKAGE, editId=edit_id).execute()
    except Exception:
        pass
