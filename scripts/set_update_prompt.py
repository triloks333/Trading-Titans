"""Turns the in-app "update available" dialog on, or off.

The dialog is driven by `app_config`, NOT by the app binary. There is no call to
Google Play anywhere in the app, so shipping a build to Play does not by itself
tell anyone an update exists — this row does:

    soft update fires when  min_supported_version <= installed < latest_version

So `latest_version` must be raised to the version you just published, every
release. Forget it and the window stays empty (`installed < latest` is false for
everyone already on the previous build) and nobody is ever prompted. This is the
single most common reason "the update popup doesn't work".

Run with no arguments and it uses the version name in `app/pubspec.yaml`, which
is the version you just built — no retyping, no typos:

    python scripts/set_update_prompt.py            # arm at the pubspec version
    python scripts/set_update_prompt.py 1.1.3      # arm at an explicit version
    python scripts/set_update_prompt.py --show     # read current values, dry-run the notes
    python scripts/set_update_prompt.py --off      # back to non-gating

The dialog's release notes are read from the newest entry in
`docs/release-notes.md`, so that file is the only place the copy is written.

Run it AFTER the Play rollout is live, not before: users prompted to update to a
build Play has not served them yet can only fail.

Deliberately does NOT touch `min_supported_version`. That one is the hard gate:
raising it locks every older client out of the app immediately, before a Play
rollout has reached them.
"""

from __future__ import annotations

import json
import pathlib
import sys
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parents[1]

url = key = ""
for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip().strip('"').rstrip("/")
    elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
        key = line.split("=", 1)[1].strip().strip('"')

HEAD = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

WATCH = (
    "latest_version",
    "min_supported_version",
    "latest_version_notes",
    "update_url",
)


def show(label: str) -> dict[str, str]:
    req = urllib.request.Request(
        f"{url}/rest/v1/app_config?select=key,value", headers=HEAD
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        rows = {x["key"]: x["value"] for x in json.loads(r.read())}
    print(f"\n{label}")
    for k in WATCH:
        v = (rows.get(k) or "").replace("\n", " | ")
        print(f"  {k:24s} {v[:80] or '(empty)'}")
    return rows


def put(config_key: str, value: str) -> None:
    req = urllib.request.Request(
        f"{url}/rest/v1/app_config?key=eq.{config_key}",
        data=json.dumps({"value": value}).encode("utf-8"),
        headers=HEAD,
        method="PATCH",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        if not json.loads(r.read()):
            raise SystemExit(f"no app_config row matched key={config_key}")


def pubspec_version() -> str:
    """The version name from app/pubspec.yaml ('1.1.3' out of '1.1.3+35').

    The build number is dropped: the app compares version *names* via
    PackageInfo.version, and a '+35' suffix would fail the x.y.z validation in
    auth_service and silently disable gating.
    """
    pubspec = ROOT / "app" / "pubspec.yaml"
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+")[0].strip()
    raise SystemExit(f"no 'version:' line found in {pubspec}")


def release_notes() -> str:
    """The current release's bullets, read out of docs/release-notes.md.

    That file is ordered newest-first and every entry puts its copy in the first
    fenced block after its "Play Store" heading, so the first such block in the
    file is the release being shipped.

    Read rather than retyped because the copy that used to live here as a
    constant went stale: it still held the 1.1.2 bullets, so arming the prompt
    for any later release showed users the wrong changelog. One source, and it is
    the one that already had to be written for the Play console.
    """
    notes = ROOT / "docs" / "release-notes.md"
    lines = notes.read_text(encoding="utf-8").splitlines()

    heading = next(
        (i for i, ln in enumerate(lines)
         if ln.startswith("###") and "Play Store" in ln),
        None,
    )
    if heading is None:
        raise SystemExit(f"no '### Play Store' heading found in {notes}")

    body: list[str] = []
    inside = False
    for ln in lines[heading + 1:]:
        if ln.strip().startswith("```"):
            if inside:
                break
            inside = True
            continue
        if inside:
            body.append(ln)

    text = "\n".join(body).strip()
    if not text:
        raise SystemExit(f"empty Play Store block under line {heading + 1} of {notes}")
    return text


def valid(v: str) -> bool:
    # auth_service validates against ^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$ before
    # parsing; anything else makes the field unavailable and gating stays off.
    parts = v.split(".")
    return len(parts) == 3 and all(p.isdigit() and len(p) <= 6 for p in parts)


args = sys.argv[1:]
if args and args[0] in {"-h", "--help"}:
    print(__doc__)
    print("\nOptions:")
    print("  --compulsory, --force  Set both latest_version and min_supported_version (mandatory update)")
    print("  --show                 Inspect current remote config and staged release notes")
    print("  --off                  Disable gating")
    sys.exit(0)

is_compulsory = any(arg in {"--compulsory", "--force", "-f"} for arg in args)
filtered_args = [arg for arg in args if arg not in {"--compulsory", "--force", "-f"}]

if filtered_args and filtered_args[0] == "--show":
    show("current app_config")
    print(f"\nwould arm at        {pubspec_version()}  (app/pubspec.yaml)")
    print("would write notes:")
    for ln in release_notes().splitlines():
        print(f"  {ln}")
    sys.exit(0)

if filtered_args and filtered_args[0] == "--off":
    before = show("before")
    put("latest_version", "1.0.0")
    put("latest_version_notes", "")
    show("after (prompt disabled)")
    print("\nmin_supported_version left at", before.get("min_supported_version"))
    sys.exit(0)

if filtered_args:
    target = filtered_args[0]
else:
    target = pubspec_version()
    print(f"no version given; using app/pubspec.yaml version {target}")

if not valid(target):
    sys.exit(f"'{target}' is not a valid x.y.z version the app will parse")

before = show("before")
put("latest_version", target)
put("latest_version_notes", release_notes())

if is_compulsory:
    put("min_supported_version", target)
    after = show("after (COMPULSORY UPDATE ARMED)")
    print(
        f"\nCOMPULSORY update gate armed at {target}."
        f"\nmin_supported_version has been set to {target}."
        f"\nEVERY user on a version below {target} will be blocked by a mandatory"
        f"\nupdate popup and cannot use the app until updated."
    )
else:
    after = show("after")
    print(
        f"\nSoft-update prompt armed at {target}."
        f"\nAnyone on a version name below {target} sees the dialog ~2s after the"
        f"\nhome screen loads. Anyone on {target} or above sees nothing."
    )
    print(f"min_supported_version untouched at {after.get('min_supported_version')} "
          "(no hard gate).")
