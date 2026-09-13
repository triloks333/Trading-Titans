"""Place the senior-personnel / beneficial-ownership statement onto the
KASHIVWEALTH MANAGEMENT LLP letterhead.

Draws the text as a transparent overlay and merges it onto the letterhead PDF,
so the artwork stays untouched and the output is real selectable text (not an
image) - which KYC reviewers and OCR checks prefer.

The blank band on the letterhead was measured at y=335..1303 of a 1055x1491pt
page; SAFE_TOP / SAFE_BOTTOM stay inside that.

Usage:
    python scripts/make_letterhead_statement.py
"""

from io import BytesIO
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import RectangleObject
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas

LETTERHEAD = Path("docs/legal/KWM LETTER HEAD (1).pdf")
OUTPUT = Path("docs/KWM-Senior-Personnel-Statement.pdf")

# ----------------------------------------------------------------- content ---
STATEMENT_DATE = "04 August 2026"
PLACE = "Gorakhpur"
SIGNATORY = "Trilok Kumar Singh"
SIGNATORY_TITLE = "Designated Partner (Authorised Signatory)"
PERSONNEL = [
    ("1", "Trilok Kumar Singh", "Designated Partner", "60%"),
    ("2", "Garima Singh", "Designated Partner", "40%"),
]

# ------------------------------------------------------------------ layout ---
PAGE_W, PAGE_H = 1055.0, 1491.0
# The supplied letterhead is a 14.65x20.71in page whose artwork is a 1055x1491px
# JPEG - only 72 DPI, which is why the graphics look soft. Emitting the finished
# document at true A4 keeps the vector text sharp and lifts the artwork to
# ~128 DPI. Real crispness needs a higher-resolution letterhead from the
# designer; pixels that were never captured cannot be recovered here.
A4_W, A4_H = 595.276, 841.89
LEFT, RIGHT = 105.0, 950.0
SAFE_TOP, SAFE_BOTTOM = 360.0, 1275.0
BODY, LEAD = 18.0, 24.0
NAVY = HexColor("#12243F")
GOLD = HexColor("#C0973F")
GREY = HexColor("#5A6273")

FONT = "Helvetica"
BOLD = "Helvetica-Bold"


class Flow:
    """Minimal top-down text cursor over the letterhead's clear band."""

    def __init__(self, pdf: canvas.Canvas) -> None:
        self.c = pdf
        self.y = PAGE_H - SAFE_TOP

    def space(self, amount: float) -> None:
        self.y -= amount

    def line(self, text: str, font: str = FONT, size: float = BODY,
             colour=NAVY, x: float = LEFT) -> None:
        self.c.setFont(font, size)
        self.c.setFillColor(colour)
        self.c.drawString(x, self.y, text)
        self.y -= LEAD

    def paragraph(self, text: str, font: str = FONT, size: float = BODY,
                  colour=NAVY, indent: float = 0.0) -> None:
        width = RIGHT - LEFT - indent
        words, current = text.split(), ""
        for word in words:
            trial = f"{current} {word}".strip()
            if stringWidth(trial, font, size) <= width:
                current = trial
            else:
                self.line(current, font, size, colour, LEFT + indent)
                current = word
        if current:
            self.line(current, font, size, colour, LEFT + indent)

    def numbered(self, index: int, text: str) -> None:
        label = f"{index}."
        self.c.setFont(FONT, BODY)
        self.c.setFillColor(NAVY)
        self.c.drawString(LEFT, self.y, label)
        self.paragraph(text, indent=34.0)


def draw_table(flow: Flow) -> None:
    columns = [("S. No.", 65.0), ("Full Name", 285.0),
               ("Title / Designation", 245.0),
               ("Contribution & Profit Share", 250.0)]
    row_h, pad = 40.0, 10.0
    pdf = flow.c

    # header
    top = flow.y + BODY - 6
    pdf.setFillColor(NAVY)
    pdf.rect(LEFT, top - row_h, RIGHT - LEFT, row_h, stroke=0, fill=1)
    x = LEFT
    pdf.setFont(BOLD, 14.0)
    for title, width in columns:
        pdf.setFillColor(white)
        pdf.drawString(x + pad, top - row_h + 14, title)
        x += width
    y = top - row_h

    # body rows
    pdf.setLineWidth(0.8)
    for row in PERSONNEL:
        pdf.setStrokeColor(HexColor("#C9CEDA"))
        pdf.setFillColor(HexColor("#FFFFFF"))
        pdf.rect(LEFT, y - row_h, RIGHT - LEFT, row_h, stroke=1, fill=0)
        x = LEFT
        for index, (value, (_, width)) in enumerate(zip(row, columns)):
            pdf.setFillColor(NAVY)
            pdf.setFont(BOLD if index == 1 else FONT, BODY - 1)
            pdf.drawString(x + pad, y - row_h + 13, value)
            x += width
        y -= row_h

    # column separators
    pdf.setStrokeColor(HexColor("#C9CEDA"))
    x = LEFT
    for _, width in columns[:-1]:
        x += width
        pdf.line(x, top - row_h, x, y)

    flow.y = y - 18


def build_overlay() -> BytesIO:
    buffer = BytesIO()
    pdf = canvas.Canvas(buffer, pagesize=(PAGE_W, PAGE_H))
    flow = Flow(pdf)

    flow.line(f"Date: {STATEMENT_DATE}", colour=GREY)
    flow.space(14)

    flow.line("STATEMENT OF SENIOR PERSONNEL AND", BOLD, 23.0)
    flow.line("BENEFICIAL OWNERSHIP", BOLD, 23.0)
    pdf.setStrokeColor(GOLD)
    pdf.setLineWidth(2.0)
    pdf.line(LEFT, flow.y + 14, LEFT + 250, flow.y + 14)
    flow.space(20)

    flow.line("To Whom It May Concern,")
    flow.space(10)

    flow.paragraph(
        "We, KASHIVWEALTH MANAGEMENT LLP, a limited liability partnership "
        "incorporated under the Limited Liability Partnership Act, 2008, having "
        "its registered office at 0403/B Hanuman Mandir Road, Betiahata, "
        "Gorakhpur - 273001, Uttar Pradesh, India, hereby confirm that the "
        "following persons constitute the senior personnel and beneficial owners "
        "of the LLP as on the date of this statement:"
    )
    flow.space(18)

    draw_table(flow)
    flow.space(6)

    flow.line("We further confirm that:", BOLD)
    flow.space(6)
    for index, item in enumerate(
        (
            "The persons named above are the only partners of the LLP and "
            "together hold 100% of its contribution and profit-sharing rights.",
            "No other person, natural or legal, holds any direct or indirect "
            "beneficial interest, ownership or controlling stake in the LLP.",
            "The management and control of the LLP vests solely with the "
            "Designated Partners named above.",
            "The information stated herein is true, correct and complete to the "
            "best of our knowledge and belief.",
        ),
        start=1,
    ):
        flow.numbered(index, item)
        flow.space(4)

    flow.space(10)
    flow.paragraph(
        "This statement is issued upon request for the purpose of Know Your "
        "Customer (KYC) and onboarding verification."
    )

    flow.space(26)
    flow.line("For KASHIVWEALTH MANAGEMENT LLP", BOLD)
    flow.space(70)  # room for a physical signature and stamp

    pdf.setStrokeColor(NAVY)
    pdf.setLineWidth(1.0)
    pdf.line(LEFT, flow.y + 16, LEFT + 300, flow.y + 16)
    flow.line(SIGNATORY, BOLD)
    flow.line(SIGNATORY_TITLE, FONT, BODY - 2, GREY)
    flow.line(f"Place: {PLACE}", FONT, BODY - 2, GREY)
    flow.line(f"Date: {STATEMENT_DATE}", FONT, BODY - 2, GREY)

    if flow.y < PAGE_H - SAFE_BOTTOM:
        raise SystemExit(
            f"Content overflows the letterhead's clear band "
            f"(ended at y={flow.y:.0f}, floor is {PAGE_H - SAFE_BOTTOM:.0f})."
        )

    pdf.save()
    buffer.seek(0)
    return buffer


def main() -> None:
    if not LETTERHEAD.exists():
        raise SystemExit(f"Letterhead not found: {LETTERHEAD}")

    page = PdfReader(str(LETTERHEAD)).pages[0]
    page.merge_page(PdfReader(build_overlay()).pages[0])
    page.scale_by(A4_W / PAGE_W)
    page.mediabox = RectangleObject((0, 0, A4_W, A4_H))
    page.cropbox = RectangleObject((0, 0, A4_W, A4_H))

    writer = PdfWriter()
    writer.add_page(page)
    writer.add_metadata(
        {
            "/Title": "Statement of Senior Personnel and Beneficial Ownership",
            "/Author": "KASHIVWEALTH MANAGEMENT LLP",
            "/Subject": "KYC - list of senior personnel and beneficial owners",
        }
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as handle:
        writer.write(handle)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
