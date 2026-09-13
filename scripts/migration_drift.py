"""Report the drift between local migration files and the remote history table.

Parses `supabase migration list --linked` output.

  local-only  : file exists, remote history has no row  -> would be re-run by db push
  remote-only : remote history has a row, no local file -> change made in the dashboard

    python scripts/migration_drift.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROW = re.compile(r"^\s*`?\s*(\d{14})?\s*`?\s*\|\s*`?\s*(\d{14})?\s*`?\s*\|")


def main() -> int:
    out = subprocess.run(
        ["npx", "--yes", "supabase", "migration", "list", "--linked"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        shell=True,
    )
    text = out.stdout + out.stderr

    local_only: list[str] = []
    remote_only: list[str] = []
    both: list[str] = []

    for line in text.splitlines():
        if "|" not in line or "Local" in line:
            continue
        parts = [p.strip().strip("`").strip() for p in line.split("|")]
        if len(parts) < 2:
            continue
        loc, rem = parts[0], parts[1]
        if loc and rem:
            both.append(loc)
        elif loc:
            local_only.append(loc)
        elif rem:
            remote_only.append(rem)

    if not (local_only or remote_only or both):
        print("Could not parse migration list output:\n" + text[:2000])
        return 1

    files = {p.name[:14]: p.name for p in (ROOT / "supabase" / "migrations").glob("*.sql")}

    print(f"in sync     : {len(both)}")
    print(f"local only  : {len(local_only)}  (db push would try to re-run these)")
    print(f"remote only : {len(remote_only)}  (applied outside the CLI, no local file)")

    print("\n--- local only ---")
    for v in local_only:
        print(f"  {v}  {files.get(v, '<no file?>')}")

    print("\n--- remote only ---")
    for v in remote_only:
        print(f"  {v}")

    # Write the repair list so the follow-up command cannot drift from this report.
    target = ROOT / "supabase" / ".temp" / "repair_versions.txt"
    keep = [v for v in local_only if v != "20260805000000"]
    target.write_text("\n".join(keep), encoding="utf-8")
    print(f"\nwrote {len(keep)} candidate version(s) to {target}")
    print("(excludes 20260805000000, the new migration that must actually run)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
