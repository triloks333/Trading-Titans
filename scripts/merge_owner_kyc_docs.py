"""Combine both owners' PAN and passport scans into the single PDF that the
gateway KYC form asks for.

Pages are copied verbatim - no scaling, re-compression or overlaid text - so the
documents stay exactly as issued and nothing looks altered.

Order follows the ownership statement: Trilok (60%) first, then Garima (40%),
each with PAN before OVD.

Usage:
    python scripts/merge_owner_kyc_docs.py
"""

from pathlib import Path

from pypdf import PdfReader, PdfWriter

SOURCES = [
    ("Trilok Kumar Singh - PAN", Path("docs/legal/Pancard Trilok.pdf")),
    ("Trilok Kumar Singh - Passport", Path("docs/legal/passport_trilok.pdf")),
    ("Garima Singh - PAN", Path("docs/legal/PAN CARD Garima.pdf")),
    ("Garima Singh - Passport", Path("docs/legal/PassportGarima.pdf")),
]
OUTPUT = Path("docs/KWM-Owners-PAN-and-Passport.pdf")


def main() -> None:
    missing = [str(path) for _, path in SOURCES if not path.exists()]
    if missing:
        raise SystemExit("Missing source file(s): " + ", ".join(missing))

    writer = PdfWriter()
    first_page_of_section = []

    for label, path in SOURCES:
        reader = PdfReader(str(path))
        first_page_of_section.append((label, len(writer.pages)))
        for page in reader.pages:
            writer.add_page(page)
        box = reader.pages[0].mediabox
        print(
            f"{label:32} {len(reader.pages)} page(s)  "
            f"{float(box.width):.0f}x{float(box.height):.0f}pt  <- {path.name}"
        )

    # Bookmarks let a reviewer jump straight to each document.
    for label, index in first_page_of_section:
        writer.add_outline_item(label, index)

    writer.add_metadata(
        {
            "/Title": "KASHIVWEALTH MANAGEMENT LLP - Owner PAN and OVD documents",
            "/Author": "KASHIVWEALTH MANAGEMENT LLP",
            "/Subject": "KYC - PAN and passport of all owners",
        }
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as handle:
        writer.write(handle)

    size_kb = OUTPUT.stat().st_size / 1024
    print(f"\nwrote {OUTPUT}  ({len(writer.pages)} pages, {size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
