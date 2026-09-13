"""Register the KASHIVWEALTH vault Android app in the Firebase project that
already sends FCM for Trading Titans, then write its google-services.json.

Idempotent: if the app already exists it just re-downloads the config.
Prints no secret material.

Usage:
    python scripts/register_vault_firebase_app.py
"""

import base64
import json
import pathlib
import sys

import google.auth.transport.requests
from google.oauth2 import service_account

SA_PATH = pathlib.Path("secrets/trading-titans-8375f-firebase-adminsdk.json")
PACKAGE = "com.kashivwealth.vault"
DISPLAY_NAME = "KASHIVWEALTH VAULT"
OUT = pathlib.Path("kashiv_vault/android/app/google-services.json")
API = "https://firebase.googleapis.com/v1beta1"


def main() -> int:
    if not SA_PATH.exists():
        print(f"missing service account: {SA_PATH}")
        return 1

    project = json.loads(SA_PATH.read_text())["project_id"]
    creds = service_account.Credentials.from_service_account_file(
        str(SA_PATH), scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    session = google.auth.transport.requests.AuthorizedSession(creds)
    parent = f"{API}/projects/{project}"

    listed = session.get(f"{parent}/androidApps", params={"pageSize": 100})
    if listed.status_code != 200:
        print(f"list failed: {listed.status_code} {listed.text[:400]}")
        return 2

    apps = listed.json().get("apps", [])
    app = next((a for a in apps if a.get("packageName") == PACKAGE), None)
    print(f"project={project} existing_android_apps={len(apps)}")

    if app is None:
        created = session.post(
            f"{parent}/androidApps",
            json={"packageName": PACKAGE, "displayName": DISPLAY_NAME},
        )
        if created.status_code not in (200, 201):
            print(f"create failed: {created.status_code} {created.text[:600]}")
            return 3
        # Long-running operation: poll until the app resource is returned.
        op = created.json()
        for _ in range(30):
            if op.get("done"):
                break
            name = op.get("name")
            polled = session.get(f"{API}/{name}")
            if polled.status_code != 200:
                print(f"poll failed: {polled.status_code} {polled.text[:400]}")
                return 4
            op = polled.json()
            if not op.get("done"):
                import time

                time.sleep(2)
        if "error" in op:
            print(f"create operation error: {json.dumps(op['error'])[:600]}")
            return 5
        app = op.get("response", {})
        print(f"created app for {PACKAGE}")
    else:
        print(f"app already registered for {PACKAGE}")

    app_name = app.get("name")
    if not app_name:
        print("no app resource name returned")
        return 6

    cfg = session.get(f"{API}/{app_name}/config")
    if cfg.status_code != 200:
        print(f"config fetch failed: {cfg.status_code} {cfg.text[:400]}")
        return 7

    contents = base64.b64decode(cfg.json()["configFileContents"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(contents)
    parsed = json.loads(contents)
    print(f"wrote {OUT} project_id={parsed['project_info']['project_id']}")
    print(f"clients={[c['client_info']['android_client_info']['package_name'] for c in parsed['client']]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
