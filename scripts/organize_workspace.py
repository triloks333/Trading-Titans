"""One-shot workspace root tidy-up.

Moves loose root files/dirs into a small, obvious set of homes and rewrites the
few paths that referenced them. Tracked paths go through `git mv` so rename
history survives; gitignored ones are plain filesystem moves.

ponytail: single-use script, kept in-tree only as the record of what moved.
Re-running it is a no-op because every step checks the source still exists.

    python scripts/organize_workspace.py
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (source, destination) pairs, relative to the repo root.
MOVES: list[tuple[str, str]] = [
    # Broker auto-login jobs live with the other scripts.
    ("upstox_autologin.py", "scripts/upstox_autologin.py"),
    ("zerodha_autologin.py", "scripts/zerodha_autologin.py"),
    ("fyers_autologin.py", "scripts/fyers_autologin.py"),
    # Company / statutory paperwork.
    ("KWM LETTER HEAD (1).pdf", "docs/legal/KWM LETTER HEAD (1).pdf"),
    (
        "DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf",
        "docs/legal/DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf",
    ),
    (
        "FiLLiP_Approval Letter_M31453985 (1).pdf",
        "docs/legal/FiLLiP_Approval Letter_M31453985 (1).pdf",
    ),
    (
        "882052107970950_signed (1)_unlocked.pdf",
        "docs/legal/882052107970950_signed (1)_unlocked.pdf",
    ),
    ("Pancard Trilok.pdf", "docs/legal/Pancard Trilok.pdf"),
    ("passport_trilok.pdf", "docs/legal/passport_trilok.pdf"),
    ("PAN CARD Garima.pdf", "docs/legal/PAN CARD Garima.pdf"),
    ("PassportGarima.pdf", "docs/legal/PassportGarima.pdf"),
    (
        "Stock_Broker_App_Guidebook_for_Developer_Trilok.pdf",
        "docs/legal/Stock_Broker_App_Guidebook_for_Developer_Trilok.pdf",
    ),
    (
        "Stock_Broker_App_Guidebook_for_Developer_Trilok.docx",
        "docs/legal/Stock_Broker_App_Guidebook_for_Developer_Trilok.docx",
    ),
    # Reference docs and media.
    ("design_guidelines.json", "docs/design_guidelines.json"),
    ("promo.mp4", "docs/promo.mp4"),
    ("app-screenshots", "docs/screenshots"),
    # Dev tooling.
    ("scratch", "scripts/scratch"),
    ("load_tests", "scripts/load_tests"),
    # Superseded work.
    ("website final", "archive/website-final-static"),
    ("src/lib/realtime.js", "archive/realtime.js"),
]

# Path strings that must be rewritten because their target moved.
EDITS: list[tuple[str, str, str]] = [
    (
        ".github/workflows/upstox_refresh.yml",
        "python upstox_autologin.py",
        "python scripts/upstox_autologin.py",
    ),
    (
        "scripts/make_letterhead_statement.py",
        'Path("KWM LETTER HEAD (1).pdf")',
        'Path("docs/legal/KWM LETTER HEAD (1).pdf")',
    ),
    (
        "scripts/fill_bo_declaration.py",
        'Path("DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf")',
        'Path("docs/legal/DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf")',
    ),
    (
        "scripts/merge_owner_kyc_docs.py",
        'Path("Pancard Trilok.pdf")',
        'Path("docs/legal/Pancard Trilok.pdf")',
    ),
    (
        "scripts/merge_owner_kyc_docs.py",
        'Path("passport_trilok.pdf")',
        'Path("docs/legal/passport_trilok.pdf")',
    ),
    (
        "scripts/merge_owner_kyc_docs.py",
        'Path("PAN CARD Garima.pdf")',
        'Path("docs/legal/PAN CARD Garima.pdf")',
    ),
    (
        "scripts/merge_owner_kyc_docs.py",
        'Path("PassportGarima.pdf")',
        'Path("docs/legal/PassportGarima.pdf")',
    ),
    ("scripts/load_tests/README.md", "load_tests/", "scripts/load_tests/"),
    ("scripts/load_tests/quote_load_test.js", "load_tests/", "scripts/load_tests/"),
    ("scripts/load_tests/order_stress_test.js", "load_tests/", "scripts/load_tests/"),
]


def is_tracked(rel: str) -> bool:
    out = subprocess.run(
        ["git", "ls-files", "--error-unmatch", rel],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if out.returncode == 0:
        return True
    # Directories: --error-unmatch needs an exact path, so probe the contents.
    listing = subprocess.run(
        ["git", "ls-files", rel], cwd=ROOT, capture_output=True, text=True
    )
    return bool(listing.stdout.strip())


def move(rel_src: str, rel_dst: str) -> str:
    src, dst = ROOT / rel_src, ROOT / rel_dst
    if not src.exists():
        return f"skip (already moved)  {rel_src}"
    if dst.exists():
        return f"SKIP (destination exists)  {rel_dst}"
    dst.parent.mkdir(parents=True, exist_ok=True)
    if is_tracked(rel_src):
        subprocess.run(["git", "mv", rel_src, rel_dst], cwd=ROOT, check=True)
        return f"git mv  {rel_src}  ->  {rel_dst}"
    shutil.move(str(src), str(dst))
    return f"move    {rel_src}  ->  {rel_dst}"


def edit(rel: str, old: str, new: str) -> str:
    path = ROOT / rel
    if not path.exists():
        return f"SKIP (missing)  {rel}"
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return f"skip (already updated)  {rel}: {old}"
    path.write_text(text.replace(old, new), encoding="utf-8", newline="")
    return f"edit    {rel}: {old!r} -> {new!r}"


def drop_empty_tree(rel: str) -> str:
    """Remove a directory only if it contains no files at all."""
    path = ROOT / rel
    if not path.exists():
        return f"skip (already gone)  {rel}"
    files = [p for p in path.rglob("*") if p.is_file()]
    if files:
        return f"KEEP ({len(files)} files found)  {rel}"
    shutil.rmtree(path)
    return f"rmdir   {rel}  (empty build skeleton)"


def main() -> None:
    for src, dst in MOVES:
        print(move(src, dst))
    print()
    for rel, old, new in EDITS:
        print(edit(rel, old, new))
    print()
    print(drop_empty_tree("mobile"))

    gitignore = ROOT / ".gitignore"
    text = gitignore.read_text(encoding="utf-8")
    if ".playwright-mcp/" not in text:
        gitignore.write_text(
            text.rstrip("\n") + "\n\n# Browser-automation scratch output\n.playwright-mcp/\n",
            encoding="utf-8",
            newline="",
        )
        print("edit    .gitignore: ignore .playwright-mcp/")
    else:
        print("skip (already ignored)  .playwright-mcp/")


if __name__ == "__main__":
    main()
