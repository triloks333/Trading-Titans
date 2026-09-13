"""Fill DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf for KASHIVWEALTH MANAGEMENT LLP.

The source is a flat (non-fillable) PDF, so the answers are drawn as a
transparent overlay and merged on top. The form artwork is never modified and the
result is selectable text.

Personal data lives in secrets/bo_declaration_data.json (gitignored) so PAN and
date-of-birth values never enter version control.

Geometry was measured from the source PDF:
  page 1  value column x 241.5..569.5 | entity row y 151.5..184.5
          address row y 184.5..216.5  | tick boxes at (246.0,223.3) and (72.0,662.9)
  page 2  column edges  [57.5 81.5 127.5 167.5 231.5 291.5 378.5 445.5 492.5 530.5 579.5]
          data rows     211.5..245.5 and 245.5..286.5

Usage:
    python scripts/fill_bo_declaration.py
"""

import json
from io import BytesIO
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas

SOURCE = Path("docs/legal/DECLARATION_OF_BENEFICIAL_OWNERSHIP.pdf")
DATA = Path("secrets/bo_declaration_data.json")
OUTPUT = Path("docs/KWM-Declaration-of-Beneficial-Ownership-FILLED.pdf")

INK = HexColor("#0B2A4A")
FONT = "Helvetica"
BOLD = "Helvetica-Bold"

# page 1
VALUE_X, VALUE_RIGHT = 247.5, 566.0
ENTITY_ROW = (151.5, 184.5)
ADDRESS_ROW = (184.5, 216.5)
TICK_LLP = (246.0, 223.3, 256.0, 233.3)
TICK_CATEGORY_1 = (72.0, 662.9, 82.0, 672.9)
DATE_BOX = (101.4, 598.8, 164.8, 610.5)

# page 2
COLS = [57.5, 81.5, 127.5, 167.5, 231.5, 291.5, 378.5, 445.5, 492.5, 530.5, 579.5]
DATA_ROWS = [(211.5, 245.5), (245.5, 286.5)]
SIGN_BASELINES = [526.5, 561.0]
SIGN_X = 88.0

# per-column font sizes: the address column is only 40pt wide
COL_FONT = {2: 4.6, 1: 5.6, 3: 5.8, 6: 5.8}
DEFAULT_FONT = 6.2


def wrap(text: str, font: str, size: float, width: float) -> list[str]:
    lines, current = [], ""
    for word in text.split():
        trial = f"{current} {word}".strip()
        if stringWidth(trial, font, size) <= width or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


class Overlay:
    def __init__(self, width: float, height: float) -> None:
        self.buffer = BytesIO()
        self.height = height
        self.c = canvas.Canvas(self.buffer, pagesize=(width, height))
        self.c.setFillColor(INK)
        self.c.setStrokeColor(INK)
        self.fitted: dict[int, float] = {}

    def y(self, top_down: float) -> float:
        """Convert a measured (top-down) coordinate to reportlab's bottom-up space."""
        return self.height - top_down

    def text(self, x: float, top_down: float, value: str,
             font: str = FONT, size: float = 9.0) -> None:
        self.c.setFont(font, size)
        self.c.setFillColor(INK)
        self.c.drawString(x, self.y(top_down), value)

    def tick(self, box: tuple[float, float, float, float]) -> None:
        x0, y0, x1, y1 = box
        self.c.setLineWidth(1.3)
        self.c.setStrokeColor(INK)
        path = self.c.beginPath()
        path.moveTo(x0 + 1.9, self.y(y0 + 5.4))
        path.lineTo(x0 + 3.9, self.y(y1 - 1.9))
        path.lineTo(x1 - 1.1, self.y(y0 + 1.7))
        self.c.drawPath(path, stroke=1, fill=0)

    def cover(self, box: tuple[float, float, float, float]) -> None:
        x0, y0, x1, y1 = box
        self.c.setFillColor(white)
        self.c.rect(x0, self.y(y1), x1 - x0, y1 - y0, stroke=0, fill=1)
        self.c.setFillColor(INK)

    def cell(self, col: int, row: tuple[float, float], value: str) -> None:
        """Draw a table cell, shrinking the type until it fits the printed box.

        The narrow columns on this form (the address column is 40pt wide) cannot
        take a fixed size, so the text auto-fits down to a 3.8pt legibility
        floor and raises rather than silently overflowing the ruled cell.
        """
        if not value:
            return
        left, right = COLS[col], COLS[col + 1]
        top, bottom = row
        pad = 2.0
        usable_w = right - left - 2 * pad
        usable_h = (bottom - top) - 2.0

        size = COL_FONT.get(col, DEFAULT_FONT)
        while size >= 3.8:
            lines = wrap(value, FONT, size, usable_w)
            lead = size * 1.13
            if len(lines) * lead <= usable_h:
                break
            size -= 0.2
        else:
            raise SystemExit(
                f"Column {col} cannot fit even at 3.8pt: {value[:40]}..."
            )

        self.fitted[col] = min(self.fitted.get(col, 99.0), size)
        y = top + pad + size
        for line in lines:
            self.text(left + pad, y, line, FONT, size)
            y += lead

    def save(self) -> BytesIO:
        self.c.save()
        self.buffer.seek(0)
        return self.buffer


def main() -> None:
    for path in (SOURCE, DATA):
        if not path.exists():
            raise SystemExit(f"Missing required file: {path}")

    data = json.loads(DATA.read_text(encoding="utf-8"))
    entity, owners = data["entity"], data["owners"]

    reader = PdfReader(str(SOURCE))
    page_w = float(reader.pages[0].mediabox.width)
    page_h = float(reader.pages[0].mediabox.height)

    # ---------------------------------------------------------------- page 1 ---
    p1 = Overlay(page_w, page_h)
    p1.text(VALUE_X, ENTITY_ROW[0] + 20, entity["name"], BOLD, 9.5)

    address_lines = wrap(entity["registered_address"], FONT, 9.0, VALUE_RIGHT - VALUE_X)
    y = ADDRESS_ROW[0] + 13
    for line in address_lines:
        p1.text(VALUE_X, y, line, FONT, 9.0)
        y += 10.5

    p1.tick(TICK_LLP)
    p1.tick(TICK_CATEGORY_1)

    p1.cover(DATE_BOX)
    p1.text(DATE_BOX[0], DATE_BOX[3] - 2.5, entity["declaration_date"], BOLD, 9.5)

    # ---------------------------------------------------------------- page 2 ---
    p2 = Overlay(page_w, page_h)
    for owner, row in zip(owners, DATA_ROWS):
        p2.cell(0, row, owner["sr"])
        p2.cell(1, row, owner["name"])
        p2.cell(2, row, f"{owner['address']} - {owner['pin']}")
        p2.cell(3, row, owner["designation"])
        p2.cell(4, row, owner["dob"])
        p2.cell(5, row, owner["id_number"])
        p2.cell(6, row, owner["address_proof"])
        p2.cell(7, row, owner["nationality"])
        p2.cell(8, row, owner["dpin"])
        p2.cell(9, row, owner["percentage"])

    for owner, baseline in zip(owners, SIGN_BASELINES):
        p2.text(SIGN_X, baseline, owner["name"], BOLD, 8.5)

    # ----------------------------------------------------------------- merge ---
    overlays = {0: PdfReader(p1.save()).pages[0], 1: PdfReader(p2.save()).pages[0]}
    writer = PdfWriter()
    for index, page in enumerate(reader.pages):
        if index in overlays:
            page.merge_page(overlays[index])
        writer.add_page(page)

    writer.add_metadata(
        {
            "/Title": "Declaration of Beneficial Ownership - KASHIVWEALTH MANAGEMENT LLP",
            "/Author": "KASHIVWEALTH MANAGEMENT LLP",
        }
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as handle:
        writer.write(handle)

    blanks = [o["name"] for o in owners if not o["dpin"]]
    print(f"wrote {OUTPUT} ({len(writer.pages)} pages)")
    print("smallest font used per column:",
          {col: round(size, 1) for col, size in sorted(p2.fitted.items())})
    if blanks:
        print("DPIN left blank for: " + ", ".join(blanks))


if __name__ == "__main__":
    main()
