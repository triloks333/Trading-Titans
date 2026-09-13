"""Find and optionally repair UTF-8 text that was round-tripped through Latin-1.

Symptom: a rupee sign renders as "â‚¹" instead of "₹". That happens when a UTF-8
file is read as ANSI/CP1252 and written back as UTF-8, so each original byte
becomes its own character.

Detection: decode the text as CP1252 and re-decode as UTF-8. If that succeeds and
changes the string, the file is mojibake.

    python scripts/find_mojibake.py            # report only
    python scripts/find_mojibake.py --fix      # repair in place
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = ["app/lib", "app/test", "supabase/functions", "website/src"]
EXTENSIONS = {".dart", ".ts", ".tsx", ".sql", ".md"}

# Sequences that only appear when UTF-8 has been mis-decoded.
MARKERS = ["\u00e2\u201a\u00b9", "\u00e2\u20ac", "\u00c3\u00a9", "\u00e2\u0080"]


def unmojibake(text: str) -> str | None:
    """Return the repaired text, or None when nothing needs repairing."""
    try:
        fixed = text.encode("cp1252", errors="strict").decode("utf-8", errors="strict")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return None
    return fixed if fixed != text else None


def main() -> int:
    fix = "--fix" in sys.argv
    damaged: list[tuple[Path, int]] = []

    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in EXTENSIONS:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            hits = sum(text.count(m) for m in MARKERS)
            if hits == 0:
                continue
            rel = path.relative_to(ROOT)
            damaged.append((path, hits))
            repaired = unmojibake(text)
            if repaired is None:
                print(f"  MOJIBAKE (manual)  {rel}  ({hits} marker(s))")
                continue
            if fix:
                path.write_text(repaired, encoding="utf-8", newline="")
                print(f"  FIXED              {rel}  ({hits} marker(s))")
            else:
                print(f"  MOJIBAKE           {rel}  ({hits} marker(s))")

    print()
    if not damaged:
        print("No mojibake found.")
        return 0
    print(f"{len(damaged)} file(s) affected." + ("" if fix else "  Re-run with --fix to repair."))
    return 0 if fix else 1


if __name__ == "__main__":
    sys.exit(main())
