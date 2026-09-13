"""Convert a Markdown file to a styled PDF.

Markdown -> HTML (python-markdown) -> PDF (xhtml2pdf / reportlab).
Both dependencies are pure-Python and install cleanly on Windows with no
system libraries required.

Usage:
    python scripts/md_to_pdf.py docs/real-time-data-analysis.md
    python scripts/md_to_pdf.py <input.md> [output.pdf]
"""

import sys
from pathlib import Path

import markdown
from xhtml2pdf import pisa

CSS = """
@page { size: A4; margin: 2cm 1.8cm; }
body { font-family: Helvetica, Arial, sans-serif; font-size: 10.5pt; color: #1a1a1a; line-height: 1.5; }
h1 { font-size: 20pt; color: #0f172a; margin: 0 0 6pt 0; }
h2 { font-size: 14pt; color: #0f172a; margin: 16pt 0 6pt 0; border-bottom: 1px solid #d0d4df; padding-bottom: 3pt; }
h3 { font-size: 12pt; color: #334155; margin: 12pt 0 4pt 0; }
p  { margin: 5pt 0; }
a  { color: #2563eb; text-decoration: none; }
ul, ol { margin: 5pt 0 5pt 6pt; }
li { margin: 2pt 0; }
strong { color: #0f172a; }
code { font-family: Courier, monospace; background: #f1f5f9; font-size: 9.5pt; padding: 1pt 3pt; }
hr { border: none; border-top: 1px solid #d0d4df; margin: 12pt 0; }
table { width: 100%; border-collapse: collapse; margin: 8pt 0; font-size: 9.5pt; }
th, td { border: 1px solid #cbd5e1; padding: 5pt 7pt; text-align: left; vertical-align: top; }
th { background: #0f172a; color: #ffffff; }
tr:nth-child(even) td { background: #f8fafc; }
"""


def convert(md_path: Path, pdf_path: Path) -> None:
    text = md_path.read_text(encoding="utf-8")
    html_body = markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "sane_lists", "nl2br"],
    )
    html = f"<html><head><style>{CSS}</style></head><body>{html_body}</body></html>"

    with pdf_path.open("wb") as out:
        result = pisa.CreatePDF(src=html, dest=out, encoding="utf-8")

    if result.err:
        raise SystemExit(f"PDF generation failed with {result.err} error(s).")
    print(f"OK -> {pdf_path}  ({pdf_path.stat().st_size:,} bytes)")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python scripts/md_to_pdf.py <input.md> [output.pdf]")

    md_path = Path(sys.argv[1]).resolve()
    if not md_path.exists():
        raise SystemExit(f"Input file not found: {md_path}")

    pdf_path = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else md_path.with_suffix(".pdf")
    convert(md_path, pdf_path)


if __name__ == "__main__":
    main()
