"""Render the Trading Titans monetisation & pricing plan as a designed PDF.

Source of truth for the prose is docs/monetisation-pricing.md; the money figures
here are COMPUTED from the assumptions in `Model` rather than copied, so the PDF
cannot drift from the arithmetic. `python scripts/make_pricing_pdf.py --check`
runs the model against known-good totals and prints nothing else - that is the
runnable check for this file.

Uses Segoe UI rather than a built-in Type1 face for one hard reason: Helvetica has
no rupee glyph, and this document is nothing but rupee figures.

Usage:
    python scripts/make_pricing_pdf.py
    python scripts/make_pricing_pdf.py --check
"""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

from reportlab.lib.colors import HexColor, white
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    Image,
    KeepTogether,
    NextPageTemplate,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "app" / "assets" / "logo" / "logo.png"
OUTPUT = ROOT / "docs" / "Trading-Titans-Pricing-Plan.pdf"

# ------------------------------------------------------------------ palette ---
# Lifted from app/lib/core/theme.dart so the document matches the product.
BLUE = HexColor("#1A73E8")
BLUE_DEEP = HexColor("#0B5FBF")
NAVY = HexColor("#0B1B2B")
INK2 = HexColor("#102A43")
INK3 = HexColor("#334E68")
INK4 = HexColor("#627D98")
INK5 = HexColor("#9FB3C8")
PARCHMENT = HexColor("#F4F7FB")
CREAM = HexColor("#EEF4FB")
SAND = HexColor("#E6EEF7")
PALE = HexColor("#EAF2FC")
BORDER = HexColor("#A8C6EC")
HAIRLINE = HexColor("#DDE7F2")
BULL = HexColor("#0F9D58")
BEAR = HexColor("#D93025")
AMBER = HexColor("#B45309")
AMBER_PALE = HexColor("#FEF6E7")
VIOLET = HexColor("#6D28D9")

# -------------------------------------------------------------------- fonts ---
WIN_FONTS = Path("C:/Windows/Fonts")
FONT, BOLD, LIGHT, SEMI = "SegoeUI", "SegoeUI-Bold", "SegoeUI-Light", "SegoeUI-Semi"
# Segoe UI proper has the rupee sign but no U+2713 check mark or U+2588 block;
# Segoe UI Symbol has those two but no rupee. Both are needed, so tick and bar
# glyphs get wrapped in SYM and everything else stays in the text face.
SYM = "SegoeUI-Sym"
ITALIC = "SegoeUI-Italic"


def register_fonts() -> None:
    faces = {
        FONT: "segoeui.ttf",
        BOLD: "segoeuib.ttf",
        LIGHT: "segoeuil.ttf",
        SEMI: "segoeuisl.ttf",
        ITALIC: "segoeuii.ttf",
        SYM: "seguisym.ttf",
    }
    for name, filename in faces.items():
        path = WIN_FONTS / filename
        if not path.exists():  # fall back rather than crash on a non-Windows box
            raise SystemExit(f"Missing font {path}. Segoe UI is required for the rupee glyph.")
        pdfmetrics.registerFont(TTFont(name, str(path)))
    # Without this, <b> and <i> markup in Paragraph text is silently ignored -
    # reportlab has no way to know these separately-registered faces are one family.
    pdfmetrics.registerFontFamily(FONT, normal=FONT, bold=BOLD, italic=ITALIC,
                                  boldItalic=BOLD)


# -------------------------------------------------------------------- model ---
class Model:
    """The whole revenue model. Change assumptions here, not in the prose."""

    GST = 1.18
    RAZORPAY_PRE = 0.0236   # 2% + 18% GST on the fee, before GST registration
    RAZORPAY_POST = 0.02    # fee GST becomes input credit once registered
    PLAY = 0.15             # Google Play service fee, India, first $1M/yr

    CONVERSION = 0.02       # share of registered users who subscribe
    TITAN_SHARE = 0.20      # share of subscribers on the premium tier
    ANNUAL_SHARE = 0.30     # share of each tier billed annually
    MONTHS_ALIVE = 10       # 10% monthly churn -> ~10-month life
    TOPUP_RATE = 0.04       # share of registered users buying one top-up a year

    PRO_MO, PRO_YR = 149, 1199
    TITAN_MO, TITAN_YR = 799, 5999
    TOPUPS = ((199, 0.50), (599, 0.35), (999, 0.15))

    @property
    def avg_topup(self) -> float:
        return sum(price * weight for price, weight in self.TOPUPS)

    def web_pre(self, price: float) -> float:
        return price * (1 - self.RAZORPAY_PRE)

    def web_post(self, price: float) -> float:
        return price / self.GST - price * self.RAZORPAY_POST

    def play(self, price: float) -> float:
        return price / self.GST * (1 - self.PLAY)

    def subscription_revenue(self, users: int, conversion=None, titan_share=None) -> float:
        conversion = self.CONVERSION if conversion is None else conversion
        titan_share = self.TITAN_SHARE if titan_share is None else titan_share
        subs = users * conversion
        pro, titan = subs * (1 - titan_share), subs * titan_share
        monthly = 1 - self.ANNUAL_SHARE
        return (
            pro * monthly * self.PRO_MO * self.MONTHS_ALIVE
            + pro * self.ANNUAL_SHARE * self.PRO_YR
            + titan * monthly * self.TITAN_MO * self.MONTHS_ALIVE
            + titan * self.ANNUAL_SHARE * self.TITAN_YR
        )

    def topup_revenue(self, users: int) -> float:
        return users * self.TOPUP_RATE * self.avg_topup

    def gross(self, users: int, conversion=None, titan_share=None) -> float:
        return self.subscription_revenue(users, conversion, titan_share) + self.topup_revenue(users)

    def net(self, users: int) -> float:
        gross = self.gross(users)
        registered = gross >= 2_000_000  # GST threshold for services
        return gross * (1 / self.GST - self.RAZORPAY_POST) if registered else self.web_pre(gross)

    @property
    def arpu(self) -> float:
        return self.gross(10_000) / 10_000

    @property
    def titan_share_of_sub_revenue(self) -> float:
        subs = 10_000 * self.CONVERSION * self.TITAN_SHARE
        titan = (
            subs * (1 - self.ANNUAL_SHARE) * self.TITAN_MO * self.MONTHS_ALIVE
            + subs * self.ANNUAL_SHARE * self.TITAN_YR
        )
        return titan / self.subscription_revenue(10_000) * 100

    @property
    def net_per_subscriber(self) -> float:
        monthly = 1 - self.ANNUAL_SHARE
        pro = monthly * self.web_pre(self.PRO_MO) * self.MONTHS_ALIVE + self.ANNUAL_SHARE * self.web_pre(self.PRO_YR)
        titan = monthly * self.web_pre(self.TITAN_MO) * self.MONTHS_ALIVE + self.ANNUAL_SHARE * self.web_pre(self.TITAN_YR)
        return (1 - self.TITAN_SHARE) * pro + self.TITAN_SHARE * titan

    def gst_cliff_users(self) -> int:
        return round(2_000_000 / self.arpu)

    def single_tier_arpu(self) -> float:
        """ARPU if only the ₹149 tier existed - the comparison that justifies Titan."""
        return self.gross(10_000, titan_share=0.0) / 10_000


M = Model()


def check() -> None:
    """Assert the model still produces the figures the plan was written against."""
    assert round(M.avg_topup, 2) == 459.00, M.avg_topup
    assert round(M.web_pre(199), 2) == 194.30
    assert round(M.web_post(149), 2) == 123.29
    assert round(M.play(5999), 2) == 4321.31
    assert round(M.gross(10_000)) == 703_740, M.gross(10_000)
    assert round(M.arpu, 2) == 70.37, M.arpu
    assert round(M.single_tier_arpu(), 2) == 46.41, M.single_tier_arpu()
    assert round(M.titan_share_of_sub_revenue, 1) == 56.9, M.titan_share_of_sub_revenue
    assert round(M.net_per_subscriber) == 2539, M.net_per_subscriber
    assert M.gst_cliff_users() == 28_420, M.gst_cliff_users()
    # Top-up revenue is independent of subscriber conversion, so doubling
    # conversion does not double gross.
    assert round(M.gross(10_000, conversion=0.04)) == 1_223_880, M.gross(10_000, conversion=0.04)
    assert round(M.gross(10_000, conversion=0.01)) == 443_670, M.gross(10_000, conversion=0.01)
    assert round(M.gross(10_000, titan_share=0.30)) == 823_540
    # Holding net revenue flat across GST registration takes exactly +18% on price.
    hold = M.web_pre(1) / (1 / M.GST - M.RAZORPAY_POST)
    assert abs(hold - 1.18) < 0.001, hold


# ------------------------------------------------------------------- styles ---
def styles() -> dict[str, ParagraphStyle]:
    base = ParagraphStyle("base", fontName=FONT, fontSize=9.4, leading=14.4, textColor=INK2)
    return {
        "body": base,
        "lead": ParagraphStyle("lead", parent=base, fontSize=11, leading=16.5, textColor=INK3),
        "small": ParagraphStyle("small", parent=base, fontSize=8.2, leading=12, textColor=INK4),
        "h1": ParagraphStyle("h1", parent=base, fontName=BOLD, fontSize=19, leading=23,
                             textColor=NAVY, spaceAfter=2),
        "h2": ParagraphStyle("h2", parent=base, fontName=BOLD, fontSize=12.5, leading=16,
                             textColor=NAVY, spaceBefore=13, spaceAfter=5),
        "h3": ParagraphStyle("h3", parent=base, fontName=BOLD, fontSize=9.8, leading=13,
                             textColor=BLUE_DEEP, spaceBefore=10, spaceAfter=3),
        "kicker": ParagraphStyle("kicker", parent=base, fontName=BOLD, fontSize=7.6, leading=10,
                                 textColor=BLUE, spaceAfter=3),
        "bullet": ParagraphStyle("bullet", parent=base, leftIndent=11, bulletIndent=1,
                                 spaceBefore=1.5, bulletFontName=FONT),
        "th": ParagraphStyle("th", parent=base, fontName=BOLD, fontSize=8.1, leading=10.5,
                             textColor=white),
        "td": ParagraphStyle("td", parent=base, fontSize=8.6, leading=11.6),
        "tdr": ParagraphStyle("tdr", parent=base, fontSize=8.6, leading=11.6, alignment=TA_RIGHT),
        "tdb": ParagraphStyle("tdb", parent=base, fontName=BOLD, fontSize=8.6, leading=11.6),
        "tdrb": ParagraphStyle("tdrb", parent=base, fontName=BOLD, fontSize=8.6, leading=11.6,
                               alignment=TA_RIGHT),
        "tdc": ParagraphStyle("tdc", parent=base, fontSize=8.6, leading=11.6, alignment=TA_CENTER),
        "note": ParagraphStyle("note", parent=base, fontSize=8.8, leading=13),
        "noteb": ParagraphStyle("noteb", parent=base, fontName=BOLD, fontSize=9, leading=13),
    }


S = styles()
CONTENT_W = A4[0] - 100


def money(value: float, decimals: int = 0) -> str:
    """Indian-format a rupee figure: 7037400 -> 70,37,400."""
    negative = value < 0
    value = abs(value)
    whole = int(value)
    frac = f"{value - whole:.{decimals}f}"[2:] if decimals else ""
    digits = str(whole)
    if len(digits) > 3:
        head, tail = digits[:-3], digits[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:])
            head = head[:-2]
        if head:
            parts.insert(0, head)
        digits = ",".join(parts + [tail])
    out = f"\u20b9{digits}" + (f".{frac}" if decimals else "")
    return f"-{out}" if negative else out


# -------------------------------------------------------------- custom bits ---
class Rule(Flowable):
    def __init__(self, width=CONTENT_W, thickness=0.6, colour=HAIRLINE, pad=0.0):
        super().__init__()
        self.width, self.thickness, self.colour, self.pad = width, thickness, colour, pad
        self.height = thickness + pad

    def draw(self):
        self.canv.setStrokeColor(self.colour)
        self.canv.setLineWidth(self.thickness)
        self.canv.line(0, self.pad / 2, self.width, self.pad / 2)


class Callout(Flowable):
    """Accent-barred box for the handful of findings that carry the document."""

    PAD_X, PAD_Y, BAR = 12.0, 9.0, 3.0

    def __init__(self, body: str, title: str | None = None, accent=BLUE, fill=PALE,
                 width=CONTENT_W):
        super().__init__()
        self.accent, self.fill, self.width = accent, fill, width
        inner = width - self.PAD_X * 2 - self.BAR
        self.parts: list[Paragraph] = []
        if title:
            self.parts.append(Paragraph(title, ParagraphStyle(
                "ct", parent=S["body"], fontName=BOLD, fontSize=9.4, leading=12.6,
                textColor=accent, spaceAfter=3)))
        self.parts.append(Paragraph(body, ParagraphStyle(
            "cb", parent=S["body"], fontSize=8.9, leading=13, textColor=INK2)))
        self._inner = inner

    def wrap(self, availWidth, availHeight):
        self.width = min(self.width, availWidth)
        self._inner = self.width - self.PAD_X * 2 - self.BAR
        self.height = sum(p.wrap(self._inner, availHeight)[1] + p.getSpaceAfter()
                          for p in self.parts) + self.PAD_Y * 2
        return self.width, self.height

    def draw(self):
        c = self.canv
        c.setFillColor(self.fill)
        c.rect(0, 0, self.width, self.height, stroke=0, fill=1)
        c.setFillColor(self.accent)
        c.rect(0, 0, self.BAR, self.height, stroke=0, fill=1)
        y = self.height - self.PAD_Y
        for part in self.parts:
            h = part.wrap(self._inner, self.height)[1]
            part.drawOn(c, self.BAR + self.PAD_X, y - h)
            y -= h + part.getSpaceAfter()


class StatBand(Flowable):
    """Row of headline numbers. The three things a reader should leave with."""

    H = 62.0

    def __init__(self, items: list[tuple[str, str, str]], width=CONTENT_W):
        super().__init__()
        self.items, self.width, self.height = items, width, self.H

    def wrap(self, availWidth, availHeight):
        self.width = min(self.width, availWidth)
        return self.width, self.height

    def draw(self):
        c = self.canv
        n = len(self.items)
        gap = 9.0
        w = (self.width - gap * (n - 1)) / n
        for i, (value, label, sub) in enumerate(self.items):
            x = i * (w + gap)
            c.setFillColor(NAVY)
            c.roundRect(x, 0, w, self.H, 5, stroke=0, fill=1)
            c.setFillColor(HexColor("#3B8BF2"))
            c.roundRect(x, self.H - 3.4, w, 3.4, 1.6, stroke=0, fill=1)
            c.setFillColor(white)
            c.setFont(BOLD, 20)
            c.drawCentredString(x + w / 2, self.H - 30, value)
            c.setFillColor(HexColor("#BBD7F8"))
            c.setFont(BOLD, 7.1)
            c.drawCentredString(x + w / 2, self.H - 42, label.upper())
            c.setFillColor(HexColor("#91A3B8"))
            c.setFont(FONT, 6.9)
            c.drawCentredString(x + w / 2, self.H - 52.5, sub)


class PriceCards(Flowable):
    """The catalogue as cards. A pricing ladder reads as shapes, not as a table."""

    H = 152.0

    def __init__(self, cards: list[dict], width=CONTENT_W):
        super().__init__()
        self.cards, self.width, self.height = cards, width, self.H

    def wrap(self, availWidth, availHeight):
        self.width = min(self.width, availWidth)
        return self.width, self.height

    def draw(self):
        c = self.canv
        n = len(self.cards)
        gap = 8.0
        w = (self.width - gap * (n - 1)) / n
        for i, card in enumerate(self.cards):
            x = i * (w + gap)
            featured = card.get("featured", False)
            c.setFillColor(NAVY if featured else white)
            c.setStrokeColor(NAVY if featured else HAIRLINE)
            c.setLineWidth(1.0 if featured else 0.7)
            c.roundRect(x, 0, w, self.H, 6, stroke=1, fill=1)

            if featured:
                c.setFillColor(BLUE)
                c.roundRect(x + w / 2 - 34, self.H - 11, 68, 13, 6.5, stroke=0, fill=1)
                c.setFillColor(white)
                c.setFont(BOLD, 6.4)
                c.drawCentredString(x + w / 2, self.H - 7.4, "HIGHEST VALUE")

            y = self.H - 27
            c.setFillColor(HexColor("#BBD7F8") if featured else BLUE)
            c.setFont(BOLD, 7.4)
            c.drawCentredString(x + w / 2, y, card["tier"].upper())

            y -= 21
            c.setFillColor(white if featured else NAVY)
            c.setFont(BOLD, 17.5)
            c.drawCentredString(x + w / 2, y, card["price"])

            y -= 11
            c.setFillColor(HexColor("#91A3B8") if featured else INK4)
            c.setFont(FONT, 7.2)
            c.drawCentredString(x + w / 2, y, card["period"])

            y -= 13
            if card.get("annual"):
                c.setFillColor(BULL)
                c.setFont(BOLD, 7.2)
                c.drawCentredString(x + w / 2, y, card["annual"])

            y -= 12
            c.setStrokeColor(HexColor("#233A66") if featured else HAIRLINE)
            c.setLineWidth(0.6)
            c.line(x + 12, y, x + w - 12, y)

            y -= 12
            c.setFillColor(HexColor("#E2ECF7") if featured else INK3)
            c.setFont(FONT, 6.9)
            for line in card["points"]:
                c.drawCentredString(x + w / 2, y, line)
                y -= 9.6


def table(rows, widths, align=None, highlight_last=False, header_fill=NAVY, pad=4.2):
    """Styled table: filled header, zebra body, hairline rules, no heavy grid."""
    align = align or ["L"] + ["R"] * (len(widths) - 1)
    data = []
    for r, row in enumerate(rows):
        out = []
        for col, cell in enumerate(row):
            if r == 0:
                style = ParagraphStyle("h", parent=S["th"],
                                       alignment=TA_RIGHT if align[col] == "R"
                                       else TA_CENTER if align[col] == "C" else 0)
            else:
                bold = highlight_last and r == len(rows) - 1
                key = {"R": "tdrb" if bold else "tdr",
                       "C": "tdc", "L": "tdb" if bold else "td"}[align[col]]
                style = S[key]
            out.append(Paragraph(str(cell), style))
        data.append(out)

    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), header_fill),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), pad),
        ("BOTTOMPADDING", (0, 0), (-1, -1), pad),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("LINEBELOW", (0, 1), (-1, -2), 0.4, HAIRLINE),
        ("ROUNDEDCORNERS", [3, 3, 0, 0]),
    ]
    for r in range(2, len(rows), 2):
        cmds.append(("BACKGROUND", (0, r), (-1, r), PARCHMENT))
    if highlight_last:
        cmds += [("BACKGROUND", (0, -1), (-1, -1), PALE),
                 ("LINEABOVE", (0, -1), (-1, -1), 0.8, BORDER)]
    t.setStyle(TableStyle(cmds))
    return t


def bullets(items: list[str]) -> list[Paragraph]:
    return [Paragraph(text, S["bullet"], bulletText="\u2022") for text in items]


def h2(text: str, kicker: str | None = None) -> list:
    out = []
    if kicker:
        out.append(Paragraph(kicker.upper(), S["kicker"]))
    out += [Paragraph(text, S["h2"]), Rule(pad=5)]
    return out


# ------------------------------------------------------------- page canvas ---
def cover_page(canv, doc):
    canv.saveState()
    w, h = A4
    canv.setFillColor(NAVY)
    canv.rect(0, 0, w, h, stroke=0, fill=1)

    # Diagonal accent wash, kept faint so the type stays dominant.
    canv.setFillColor(HexColor("#122A4D"))
    canv.setStrokeColor(HexColor("#122A4D"))
    p = canv.beginPath()
    p.moveTo(0, h * 0.30)
    p.lineTo(w, h * 0.46)
    p.lineTo(w, 0)
    p.lineTo(0, 0)
    p.close()
    canv.drawPath(p, stroke=0, fill=1)

    canv.setFillColor(BLUE)
    canv.rect(0, h - 5, w, 5, stroke=0, fill=1)

    if LOGO.exists():
        canv.drawImage(str(LOGO), 50, h - 152, width=62, height=62,
                       mask="auto", preserveAspectRatio=True)

    canv.setFillColor(HexColor("#BBD7F8"))
    canv.setFont(BOLD, 9)
    canv.drawString(50, h - 176, "TRADING TITANS")
    canv.setFillColor(HexColor("#627D98"))
    canv.setFont(FONT, 8.4)
    canv.drawString(50, h - 190, "Kashivwealth Management LLP")

    canv.setStrokeColor(BLUE)
    canv.setLineWidth(2.4)
    canv.line(50, h - 214, 96, h - 214)

    canv.setFillColor(white)
    canv.setFont(LIGHT, 39)
    canv.drawString(50, h - 268, "Monetisation &")
    canv.setFont(BOLD, 39)
    canv.drawString(50, h - 310, "Pricing Plan")

    canv.setFillColor(HexColor("#91A3B8"))
    canv.setFont(FONT, 12.5)
    canv.drawString(50, h - 340, "Top-ups  \u00b7  Subscriptions  \u00b7  Enterprise")

    canv.setFillColor(HexColor("#3B8BF2"))
    canv.setFont(BOLD, 8.2)
    canv.drawString(50, h - 372, "COMMERCIAL PLAN \u2014 PRICE POINTS, TIER INCLUSIONS AND UNIT ECONOMICS")

    # Footer block
    canv.setStrokeColor(HexColor("#233A66"))
    canv.setLineWidth(0.7)
    canv.line(50, 108, w - 50, 108)
    canv.setFillColor(HexColor("#BBD7F8"))
    canv.setFont(BOLD, 8.4)
    canv.drawString(50, 88, date.today().strftime("%d %B %Y").upper())
    canv.setFillColor(HexColor("#627D98"))
    canv.setFont(FONT, 8.2)
    canv.drawString(50, 74, "Internal \u2014 commercial planning. Figures are projections, not commitments.")
    canv.setFillColor(HexColor("#627D98"))
    canv.setFont(FONT, 8.2)
    canv.drawRightString(w - 50, 88, "Revision 1")
    canv.restoreState()


def content_page(canv, doc):
    canv.saveState()
    w, h = A4
    canv.setFillColor(white)
    canv.rect(0, 0, w, h, stroke=0, fill=1)

    canv.setFillColor(BLUE)
    canv.rect(0, h - 3.2, w, 3.2, stroke=0, fill=1)

    if LOGO.exists():
        canv.drawImage(str(LOGO), 50, h - 46, width=15, height=15,
                       mask="auto", preserveAspectRatio=True)
    canv.setFillColor(NAVY)
    canv.setFont(BOLD, 7.8)
    canv.drawString(70, h - 41, "TRADING TITANS")
    canv.setFillColor(INK5)
    canv.setFont(FONT, 7.8)
    canv.drawString(146, h - 41, "Monetisation & Pricing Plan")

    canv.setStrokeColor(HAIRLINE)
    canv.setLineWidth(0.6)
    canv.line(50, h - 54, w - 50, h - 54)
    canv.line(50, 46, w - 50, 46)

    canv.setFillColor(INK5)
    canv.setFont(FONT, 7.6)
    canv.drawString(50, 34, date.today().strftime("%d %B %Y"))
    canv.setFillColor(INK3)
    canv.setFont(BOLD, 8.4)
    canv.drawRightString(w - 50, 34, str(canv.getPageNumber() - 1))
    canv.restoreState()


# -------------------------------------------------------------------- story ---
def build_story() -> list:
    st: list = [NextPageTemplate("content"), PageBreak()]

    # ---- 1. At a glance -----------------------------------------------------
    st.append(Paragraph("The plan at a glance", S["h1"]))
    st.append(Spacer(1, 3))
    st.append(Paragraph(
        "Two axes. <b>Top-ups sell simulated cash; subscriptions sell capability.</b> "
        "Keeping them separate is what stops the funnel collapsing into one confusing "
        "ladder \u2014 and it means a top-up buyer still has a reason to subscribe.",
        S["lead"]))
    st.append(Spacer(1, 12))

    st.append(PriceCards([
        {"tier": "Free", "price": "\u20b90", "period": "forever",
         "points": ["Equity + crypto", "Web & Android", "Leaderboard top 10",
                    "3 autopsies", "Community support"]},
        {"tier": "Pro", "price": money(M.PRO_MO), "period": "per month",
         "annual": f"{money(M.PRO_YR)}/yr \u2014 save 33%",
         "points": ["Index F&O", "US stocks", "Unlimited autopsies",
                    "Full leaderboard", "Analytics + export"]},
        {"tier": "Titan", "price": money(M.TITAN_MO), "period": "per month",
         "annual": f"{money(M.TITAN_YR)}/yr \u2014 save 37%", "featured": True,
         "points": ["Real-time ticks", "Full stock F&O", "Greeks + IV surface",
                    "Backtesting", "Strategy builder"]},
        {"tier": "Enterprise", "price": "\u20b9299+", "period": "per seat / year",
         "points": ["Cohort admin view", "Private leaderboards", "Branded reports",
                    "Data export API", "Dedicated SLA"]},
    ]))
    st.append(Spacer(1, 14))

    st.append(StatBand([
        (money(M.arpu, 2), "gross per user / year", "at 2% conversion"),
        (f"{M.titan_share_of_sub_revenue:.1f}%", "of sub revenue is Titan",
         "from 20% of subscribers"),
        (money(M.net_per_subscriber), "net per subscriber / year",
         "blended, web checkout"),
    ]))
    st.append(Spacer(1, 14))

    st.append(Callout(
        f"Adding the {money(M.TITAN_MO)} tier lifts revenue <b>"
        f"{(M.arpu / M.single_tier_arpu() - 1) * 100:.1f}%</b> at the same conversion rate "
        f"\u2014 ARPU goes from {money(M.single_tier_arpu(), 2)} to {money(M.arpu, 2)} per "
        f"registered user per year. One Titan annual subscriber is worth five Pro annuals, "
        f"which makes <b>moving a Pro user up worth roughly 5\u00d7 more than converting a "
        f"new free user</b>.",
        title="Why the second subscription tier earns its keep"))
    st.append(Spacer(1, 8))
    st.append(Callout(
        "At today's 176 users this model is worth about "
        f"{money(M.gross(176) / 12)}/month. Monetisation is not a revenue event at this "
        "scale \u2014 it is plumbing built now so it is ready when the user base justifies "
        "it. <b>Distribution matters far more than pricing.</b>",
        title="Honest read on scale", accent=INK3, fill=PARCHMENT))
    st.append(Spacer(1, 8))
    st.append(Callout(
        f"One 400-seat institution at {money(399)}/seat is {money(159600)} a year \u2014 "
        f"roughly the entire subscription revenue from <b>3,000 registered consumer users</b>, "
        f"with no Play fee, no app-store review, no per-user support, and paid up front rather "
        f"than dribbling in against 10% monthly churn. If the goal is revenue rather than user "
        f"count, <b>enterprise is the priority and B2C is the funnel that makes enterprise "
        f"credible</b>. Detail in section 05.",
        title="The tier that changes the shape of the business", accent=BULL,
        fill=HexColor("#E9F7EF")))

    # ---- 2. Catalogue -------------------------------------------------------
    st.append(PageBreak())
    st += h2("The catalogue", "section 01")

    st.append(Paragraph("Tier 1 \u2014 Top-ups (one-time, keep forever)", S["h3"]))
    st.append(Paragraph(
        "Already priced in the codebase as <font face='%s'>titan_1l/5l/pro</font>, so nothing "
        "is wasted. The declining \u20b9-per-lakh is deliberate: it makes trading up feel like "
        "a discount rather than an upsell. No feature access attached, no expiry, no renewal."
        % FONT, S["body"]))
    st.append(Spacer(1, 6))
    st.append(table(
        [["SKU", "Virtual cash", "Price", "\u20b9 per lakh"],
         ["topup_boost", money(100000), money(199), money(199)],
         ["topup_plus", money(500000), money(599), money(120)],
         ["topup_max", money(1000000), money(999), money(100)]],
        [140, 130, 110, 110]))

    st.append(Paragraph("Tier 2 \u2014 Subscriptions (recurring, two levels)", S["h3"]))
    st.append(Spacer(1, 2))
    st.append(table(
        [["SKU", "Monthly", "Annual", "Effective /mo", "Annual saving"],
         ["pro_monthly / pro_annual", money(M.PRO_MO), money(M.PRO_YR),
          money(M.PRO_YR / 12, 2), f"33% ({money(M.PRO_MO * 12 - M.PRO_YR)})"],
         ["titan_monthly / titan_annual", money(M.TITAN_MO), money(M.TITAN_YR),
          money(M.TITAN_YR / 12, 2), f"37% ({money(M.TITAN_MO * 12 - M.TITAN_YR)})"]],
        [166, 78, 82, 88, 90]))
    st.append(Spacer(1, 8))
    st += bullets([
        f"<b>Pro {money(M.PRO_MO)}</b> sits deliberately <i>below</i> the cheapest top-up. "
        f"A recurring {money(199)} is a harder ask than a one-time {money(199)}, so pricing "
        f"Pro under the impulse price makes it the obvious-value option. Annual lands under "
        f"{money(100)}/mo, which is the number that closes.",
        f"<b>Titan {money(M.TITAN_MO)}</b> is a different customer, not a bigger version of "
        f"the same one. Pro is for someone learning; Titan is for someone treating this as "
        f"practice for a real options desk.",
        "The heavier annual discount on Titan is intentional \u2014 churn risk rises with "
        "ticket size, so locking a Titan user into a year is worth more than the margin "
        "given up.",
    ])

    st.append(Paragraph("Tier 3 \u2014 Enterprise (contact us only)", S["h3"]))
    st.append(Paragraph(
        "Per-seat, annual, invoiced directly. No self-serve checkout, no price on the page. "
        "Targets: colleges and B-schools, coaching institutes, prop-desk training, corporate "
        "L&amp;D, finance-club competitions.", S["body"]))
    st.append(Spacer(1, 6))
    st.append(table(
        [["Band", "Seats", "Price / seat / yr", "Example deal"],
         ["Campus", "50 \u2013 249", money(499), f"100 seats = {money(49900)}"],
         ["Institution", "250 \u2013 999", money(399), f"400 seats = {money(159600)}"],
         ["Scale", "1,000+", money(299), f"2,000 seats = {money(598000)}"]],
        [110, 100, 130, 150], align=["L", "R", "R", "R"]))
    st.append(Spacer(1, 8))
    st += bullets([
        f"<b>Minimum contract {money(25000)}/yr</b> \u2014 keeps out deals that cost more to "
        f"service than they earn.",
        f"Optional one-time <b>onboarding &amp; branding {money(10000)}</b>: branded reports, "
        f"custom starting capital, cohort setup.",
    ])
    st.append(Spacer(1, 14))
    st.append(Callout(
        "Purchased cash must be <b>floored and never reset</b>. If seasons or challenges ever "
        "wipe wallets, clearing cash somebody paid for is a refund conversation and a "
        "chargeback risk \u2014 and it is far cheaper to decide now than to unwind later. This "
        "is the one catalogue decision that cannot wait until after the first sale.",
        title="One rule the top-up tier depends on", accent=VIOLET,
        fill=HexColor("#F3EFFE")))

    # ---- 3. Feature matrix --------------------------------------------------
    st.append(PageBreak())
    st += h2("What each tier includes", "section 02")
    st.append(Paragraph(
        "The two-tier split only works if features actually move up. Pro keeps everything "
        "that upgrades a <i>learner</i>; Titan takes everything that costs real money or real "
        "compute \u2014 which is also what a serious trader will pay for.", S["body"]))
    st.append(Spacer(1, 8))

    Y = f"<font face='{SYM}' color='#0F9D58' size='10'>\u2714</font>"
    N = "<font color='#9FB3C8'>\u2014</font>"
    st.append(table(
        [["", "Free", "Pro", "Titan", "Ent."],
         ["Indian equity, market &amp; limit orders", Y, Y, Y, Y],
         ["Crypto", Y, Y, Y, Y],
         ["Web app", Y, Y, Y, Y],
         ["Leaderboard", "Top 10", "Full + history", "Full + history", "Private"],
         ["Trade autopsies", "3", "Unlimited", "Unlimited", "Unlimited"],
         ["Price alerts / watchlists", "3 / 1", "Unlimited", "Unlimited", "Unlimited"],
         ["Chart timeframes", "1 month", "Up to 5 years", "Up to 5 years", "Up to 5 years"],
         ["P&amp;L history", "7 days", "Full + CSV", "Full + CSV", "Full + API"],
         ["US stocks", N, Y, Y, Y],
         ["Index F&amp;O (NIFTY / BANKNIFTY)", "View only", Y, Y, Y],
         ["Full stock F&amp;O", N, N, Y, Y],
         ["Real-time tick data", N, N, Y, Y],
         ["Options Greeks + IV surface", N, N, Y, Y],
         ["Multi-leg strategy builder", N, N, Y, Y],
         ["Backtesting on NSE F&amp;O history", N, N, Y, Y],
         ["Risk analytics (Sharpe, VaR, drawdown)", N, N, Y, Y],
         ["Parallel portfolios", "1", "1", "5", "Custom"],
         ["Monthly cash stipend", N, money(50000), money(500000), "Custom"],
         ["Read-only data API", N, N, Y, Y],
         ["Cohort / instructor view", N, N, N, Y],
         ["Support", "Community", "Priority", "Dedicated", "SLA"]],
        [196, 66, 78, 78, 72],
        align=["L", "C", "C", "C", "C"], pad=3.1))
    st.append(Spacer(1, 11))

    st.append(Callout(
        f"At {money(M.TITAN_MO)}/mo you are priced against <b>Sensibull (~{money(800)}/mo)</b>, "
        "a real options analytics product, where users compare feature lists line by line. "
        "Four of Titan's headline features do not exist yet, and one is a known open bug \u2014 "
        "<b>option premiums currently use a flat 25% implied volatility across all three "
        f"clients</b>. Shipping Titan at {money(M.TITAN_MO)} on today's feature set invites "
        "refunds from exactly the customers you most want. Pro can launch on close to what "
        "exists now; Titan should be a second release.",
        title="Titan cannot launch at this price on today's feature set",
        accent=AMBER, fill=AMBER_PALE))
    st.append(Spacer(1, 11))
    st.append(KeepTogether([
        Paragraph("Two placement calls worth defending", S["h3"]),
        *bullets([
            "<b>The web app stays free.</b> It is the only rail where you keep ~83% instead of "
            "~72%. Gating it means a free user can never reach a web checkout, pushing every "
            "sale into Play and costing 11 points of margin on all of it.",
            "<b>The leaderboard is only partly gated.</b> Free keeps the top 10 and own rank. "
            "A leaderboard no free user can see stops being a retention loop and stops being "
            "social proof. The full 100 plus history and percentile still sells something real.",
        ]),
    ]))

    # ---- 4. Take rates ------------------------------------------------------
    st.append(PageBreak())
    st += h2("What you actually keep", "section 03")
    st += bullets([
        f"<b>GST 18%</b> on digital services in India, and B2C prices must display inclusive "
        f"of it. {money(M.PRO_MO)} is not {money(M.PRO_MO)} of revenue \u2014 it is "
        f"{money(M.PRO_MO / M.GST, 2)} plus {money(M.PRO_MO - M.PRO_MO / M.GST, 2)} you owe.",
        "<b>Razorpay 2%</b> + 18% GST on that fee. Once GST-registered the fee's GST is input "
        "credit, so the real cost is 2%; before registration, 2.36%.",
        "<b>Google Play 15%</b> on the first $1M/yr for India.",
    ])
    st.append(Spacer(1, 10))

    st.append(Paragraph("Take rate by rail", S["h3"]))
    st.append(table(
        [["Rail", "You keep"],
         ["Web / Razorpay, <b>before</b> GST registration", "97.6%"],
         ["Web / Razorpay, after GST registration", "82.7%"],
         ["Google Play Billing, India", "~72.0%"],
         ["Play + India alternative billing (15% \u2212 4% + own gateway 2%)", "~71.7%"]],
        [370, 120]))
    st.append(Spacer(1, 8))
    st += bullets([
        "<b>India's alternative-billing route is pointless.</b> Knocking 4% off the Play fee "
        "then paying your own gateway 2% lands within a rounding error of just using Play "
        "Billing, for a great deal more work. Skip it.",
        f"<b>Web is worth 11 points over Play</b> \u2014 and it matters most on the expensive "
        f"SKU. On a {money(M.TITAN_YR)} Titan annual that is "
        f"<b>{money(M.web_post(M.TITAN_YR) - M.play(M.TITAN_YR))} per subscriber per year</b>.",
    ])

    st.append(Paragraph("Net per SKU", S["h3"]))
    rows = [["SKU", "Price", "Web, pre-GST", "Web, post-GST", "Play Billing"]]
    for name, price in [("Boost top-up", 199), ("Plus top-up", 599), ("Max top-up", 999),
                        ("Pro monthly", M.PRO_MO), ("Pro annual", M.PRO_YR),
                        ("Titan monthly", M.TITAN_MO), ("Titan annual", M.TITAN_YR)]:
        rows.append([name, money(price), money(M.web_pre(price), 2),
                     money(M.web_post(price), 2), money(M.play(price), 2)])
    st.append(table(rows, [116, 78, 104, 104, 98]))

    st.append(PageBreak())
    st += h2(f"The {money(2000000)} GST cliff", "section 03 \u00b7 continued")
    st.append(Paragraph(
        f"Registration is mandatory for services above <b>{money(2000000)}</b> aggregate "
        f"annual turnover ({money(1000000)} in special-category states). The day you cross it "
        f"you lose 15.25% of every rupee \u2014 so the revenue curve goes <i>backwards</i> "
        f"across the threshold. This is the one part of the model that punishes growth, and "
        f"the only defence is deciding what to do before you arrive.", S["lead"]))
    st.append(Spacer(1, 12))

    cliff_lo, cliff_hi = 1_990_000, 2_010_000
    net_lo = M.web_pre(cliff_lo)
    post_rate = 1 / M.GST - M.RAZORPAY_POST
    st.append(table(
        [["Gross turnover", "GST status", "Net kept", "Effective rate"],
         [money(cliff_lo), "Below threshold", money(net_lo), "97.6%"],
         [money(cliff_hi), "<b>Registered</b>", money(cliff_hi * post_rate), "82.7%"],
         [money(net_lo / post_rate), "Registered", money(net_lo), "82.7%"]],
        [120, 130, 120, 120], align=["R", "L", "R", "R"], highlight_last=True))
    st.append(Spacer(1, 6))
    st.append(Paragraph(
        f"The bottom row is the point: <b>{money(net_lo / post_rate)} of gross is needed just "
        f"to match {money(cliff_lo)} of gross.</b> Roughly {money(net_lo / post_rate - cliff_lo)} "
        f"of extra sales buys you nothing.", S["body"]))
    st.append(Spacer(1, 14))

    st.append(Paragraph("Option A \u2014 raise prices to coincide with registration", S["h3"]))
    st.append(Paragraph(
        "Holding net revenue flat across the transition takes exactly +18% on every price. "
        "Rounded to sensible price points:", S["body"]))
    st.append(Spacer(1, 6))
    rows = [["SKU", "Price now", "Net now", "Net after GST", "New price", "Net at new price"]]
    for name, price, rounded in [("Pro monthly", M.PRO_MO, 179),
                                 ("Pro annual", M.PRO_YR, 1449),
                                 ("Titan monthly", M.TITAN_MO, 949),
                                 ("Titan annual", M.TITAN_YR, 7099),
                                 ("Boost top-up", 199, 239),
                                 ("Max top-up", 999, 1179)]:
        rows.append([name, money(price), money(M.web_pre(price)), money(M.web_post(price)),
                     f"<b>{money(rounded)}</b>", money(M.web_post(rounded))])
    st.append(table(rows, [90, 66, 66, 78, 76, 96]))
    st.append(Spacer(1, 12))

    st.append(Paragraph("Option B \u2014 absorb it", S["h3"]))
    st.append(Paragraph(
        f"Keep prices as they are and accept the margin drop. At the point of crossing, that "
        f"costs roughly {money(cliff_lo * (M.web_pre(1) - post_rate))} a year in net revenue "
        f"and grows with turnover. Defensible if you are chasing users over margin, but it "
        f"means the price rise happens later, to an audience that has already anchored on the "
        f"old number \u2014 which is the harder conversation.", S["body"]))
    st.append(Spacer(1, 14))
    st.append(Callout(
        f"On Play, Google is merchant of record for GST in India, so the ~72% take applies "
        f"whether or not you are registered \u2014 no cliff, but no cheap early phase either. "
        f"<b>Confirm the exact Play/GST mechanics with a CA before modelling on them.</b> The "
        f"recommendation stands regardless: launch at the higher price on web, because raising "
        f"a live price is materially harder than starting there.",
        title="Recommendation", accent=AMBER, fill=AMBER_PALE))

    # ---- 5. Scenarios -------------------------------------------------------
    st.append(PageBreak())
    st += h2("Revenue scenarios", "section 04")
    st.append(Paragraph("Assumptions, stated so you can argue with them:", S["body"]))
    st.append(Spacer(1, 4))
    st += bullets([
        "<b>2% of registered users subscribe.</b> Consumer freemium runs 1\u20133%. Bear 1%, bull 4%.",
        "<b>80% take Pro, 20% take Titan.</b> Typical for a ~5\u00d7 price gap; the premium tier "
        "usually lands at 10\u201325% of the paid base.",
        "<b>70/30 monthly-to-annual</b> split within each tier.",
        "<b>10% monthly churn</b> \u2192 ~10-month average life on monthly plans.",
        f"<b>4% buy one top-up per year</b>, average ticket {money(M.avg_topup)} "
        f"(50% Boost, 35% Plus, 15% Max).",
    ])
    st.append(Spacer(1, 10))

    rows = [["Registered users", "Subscribers", "Subscriptions", "Top-ups", "Gross / yr", "Gross / mo"]]
    for users in (176, 1_000, 5_000, 10_000, 50_000, 100_000):
        label = f"{users:,}" + (" (today)" if users == 176 else "")
        subs = users * M.CONVERSION
        rows.append([label, f"{subs:,.0f}", money(M.subscription_revenue(users)),
                     money(M.topup_revenue(users)), money(M.gross(users)),
                     money(M.gross(users) / 12)])
    st.append(table(rows, [96, 74, 92, 76, 84, 74]))
    st.append(Spacer(1, 10))

    st.append(Paragraph("What the Titan tier is worth", S["h3"]))
    st.append(table(
        [["", f"Single tier ({money(M.PRO_MO)} only)", f"Two tiers ({money(M.PRO_MO)} + {money(M.TITAN_MO)})"],
         ["ARPU / registered user / yr", money(M.single_tier_arpu(), 2), money(M.arpu, 2)],
         ["Gross at 10,000 users", money(M.gross(10_000, titan_share=0.0)), money(M.gross(10_000))]],
        [190, 150, 150], highlight_last=True))
    st.append(Spacer(1, 10))
    st.append(Paragraph(
        f"<b>Adding Titan lifts revenue "
        f"{(M.arpu / M.single_tier_arpu() - 1) * 100:.1f}% at the same conversion rate.</b> The "
        f"split inside that is the real story: Titan is 20% of subscribers but "
        f"{M.titan_share_of_sub_revenue:.1f}% of subscription revenue. One Titan annual "
        f"subscriber is worth five Pro annuals \u2014 which means <b>moving an existing Pro user "
        f"up is worth roughly 5\u00d7 more than converting a new free user to Pro</b>. That is a "
        f"different growth motion from the one most freemium products run, and a cheaper one, "
        f"because the audience is already paying and already reachable in-product.", S["body"]))

    st.append(PageBreak())
    st += h2("Where the revenue actually lands", "section 04 \u00b7 continued")
    st.append(Paragraph("Net, after the right rail", S["h3"]))
    rows = [["Registered users", "Gross / yr", "Net (web)", "Note"]]
    for users in (1_000, 5_000, 10_000, 50_000, 100_000):
        gst = M.gross(users) >= 2_000_000
        rows.append([f"{users:,}", money(M.gross(users)), money(M.net(users)),
                     "<b>GST applies</b>" if gst else "pre-GST"])
    st.append(table(rows, [110, 120, 120, 130], align=["L", "R", "R", "L"]))
    st.append(Spacer(1, 10))

    st.append(Paragraph("Sensitivity", S["h3"]))
    sens = Table([[
        table([["Conversion", "Gross / yr"]]
              + [[lbl, money(M.gross(10_000, conversion=c))]
                 for lbl, c in [("1% (bear)", 0.01), ("2% (base)", 0.02), ("4% (bull)", 0.04)]],
              [92, 92]),
        "",
        table([["Titan share", "Gross / yr"]]
              + [[lbl, money(M.gross(10_000, titan_share=t))]
                 for lbl, t in [("10%", 0.10), ("20% (base)", 0.20), ("30%", 0.30)]],
              [92, 92]),
    ]], colWidths=[194, 22, 194], hAlign="LEFT")
    sens.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                              ("LEFTPADDING", (0, 0), (-1, -1), 0),
                              ("RIGHTPADDING", (0, 0), (-1, -1), 0)]))
    st.append(sens)
    st.append(Spacer(1, 10))
    mix_delta = M.gross(10_000, titan_share=0.30) - M.gross(10_000, titan_share=0.20)
    st.append(Callout(
        f"Ten points of tier mix is worth <b>{money(mix_delta)}/yr</b> at 10,000 users \u2014 "
        f"comparable to a whole point of overall conversion. <b>Tier mix is now as strong a "
        f"lever as conversion</b>, and it is the cheaper one to move, because those users are "
        f"already paying. Higher ARPU has a cost, though: the GST threshold now arrives at "
        f"about <b>{M.gst_cliff_users():,} registered users</b> instead of "
        f"{round(2_000_000 / M.single_tier_arpu()):,}.",
        title="Where to spend effort"))
    st.append(Spacer(1, 14))

    st.append(Paragraph("Lifetime value, and what you can afford to pay for a user",
                        S["h3"]))
    st.append(Paragraph(
        "Net of gateway fees, pre-GST, on the churn assumption above. These are the numbers "
        "any paid-acquisition decision has to clear.", S["body"]))
    st.append(Spacer(1, 6))
    rows = [["Subscriber type", "Net LTV", "vs Pro monthly"]]
    base_ltv = M.web_pre(M.PRO_MO) * M.MONTHS_ALIVE
    for name, ltv in [
        ("Pro monthly (10 months)", base_ltv),
        ("Pro annual (first year)", M.web_pre(M.PRO_YR)),
        ("Titan monthly (10 months)", M.web_pre(M.TITAN_MO) * M.MONTHS_ALIVE),
        ("Titan annual (first year)", M.web_pre(M.TITAN_YR)),
        ("Blended, at the 80/20 mix", M.net_per_subscriber),
    ]:
        rows.append([name, money(ltv), f"{ltv / base_ltv:.2f}\u00d7"])
    st.append(table(rows, [200, 130, 130], highlight_last=True))
    st.append(Spacer(1, 10))
    st.append(Callout(
        f"At 2% conversion, every registered user is worth about "
        f"<b>{money(M.arpu, 2)} gross / {money(M.arpu * (1 - M.RAZORPAY_PRE), 2)} net per "
        f"year</b>. That is the ceiling on blended cost per registered user \u2014 paid "
        f"acquisition above roughly {money(70)} a signup loses money on a one-year view, and "
        f"only works if you believe in multi-year retention this model does not yet assume. "
        f"<b>A Titan subscriber, by contrast, justifies "
        f"{money(M.web_pre(M.TITAN_YR))} of acquisition cost in year one alone</b> \u2014 which "
        f"is the argument for targeting serious traders directly rather than buying broad "
        f"installs.",
        title="The CAC ceiling this model implies", accent=VIOLET,
        fill=HexColor("#F3EFFE")))

    # ---- 6. Costs -----------------------------------------------------------
    st.append(PageBreak())
    st += h2("Cost side and break-even", "section 05")
    st.append(Paragraph(
        "Fill in your actual figures; the structure is the point.", S["body"]))
    st.append(Spacer(1, 6))
    st.append(table(
        [["Line", "Est. / month", "Scales with users?"],
         ["Supabase Pro", "~\u20b92,100 ($25)", "Yes \u2014 DB, egress, function calls"],
         ["Vercel", "\u20b90 \u2013 1,700", "Mildly"],
         ["Market data (Upstox / Fyers)", "<b>?</b>", "Depends on contract"],
         ["Domain + email", "~\u20b9200", "No"],
         ["FCM push", "\u20b90", "No"],
         ["Play developer account", "$25 one-time", "No"],
         ["Estimated current burn", "<b>\u20b95,000 \u2013 15,000</b>", ""]],
        [180, 130, 180], align=["L", "R", "L"], highlight_last=True))
    st.append(Spacer(1, 10))

    st.append(Paragraph(
        f"Blended net revenue per subscriber per year, at the 80/20 tier and 70/30 billing "
        f"mix (pre-GST, web): <b>{money(M.net_per_subscriber)}</b>.", S["body"]))
    st.append(Spacer(1, 6))
    rows = [["Monthly burn", "Subscribers needed", "\u2248 registered users at 2%"]]
    for burn in (5_000, 10_000, 15_000):
        subs = burn * 12 / M.net_per_subscriber
        rows.append([money(burn), f"{subs:,.0f}", f"{subs / M.CONVERSION:,.0f}"])
    st.append(table(rows, [130, 150, 170]))
    st.append(Spacer(1, 10))
    st.append(Callout(
        f"<b>Break-even lands around 1,200 \u2013 3,600 registered users</b> \u2014 roughly "
        f"half what the single-tier model needed. Titan does that, not Pro. One caveat: Titan "
        f"promises <b>real-time tick data</b>, the only benefit here with a genuine variable "
        f"cost attached. Price what live ticks actually cost per user under your Upstox/Fyers "
        f"contract before locking {money(M.TITAN_MO)}, or Titan's margin is not the "
        f"{money(M.web_pre(M.TITAN_MO), 2)} in the table.",
        title="The milestone, and the one cost that could move it"))
    st.append(Spacer(1, 12))

    st.append(Paragraph("Enterprise changes the shape completely", S["h3"]))
    titan_yr_net = M.web_pre(M.TITAN_YR)
    rows = [["Deal", "Annual value", "Equivalent in B2C"]]
    for seats, rate in ((100, 499), (400, 399), (2000, 299)):
        value = seats * rate
        rows.append([f"{seats:,}-seat @ {money(rate)}", money(value),
                     f"{value / M.avg_topup:,.0f} top-ups / {value / titan_yr_net:,.0f} Titan annuals"])
    st.append(table(rows, [150, 120, 220], align=["L", "R", "L"]))
    st.append(Spacer(1, 8))
    st.append(Paragraph(
        "One 400-seat institution \u2248 the entire subscription revenue from 3,000 registered "
        "consumer users. No Play fee, no app-store review, no per-user support, invoiced "
        "directly, paid annually up front instead of dribbling in with 10% monthly churn. "
        "<b>If the goal is revenue rather than user count, enterprise is the priority and B2C "
        "is the funnel that makes enterprise credible.</b>", S["body"]))

    # ---- 7. Competitive ----------------------------------------------------
    st.append(PageBreak())
    st += h2("Competitive price context", "section 06")
    rows = [["Service", "Price / month", "Relative to the most expensive"]]
    market = [("Spotify India", 119, False), ("YouTube Premium India", 149, False),
              ("Netflix mobile India", 149, False),
              ("Trading Titans Pro", M.PRO_MO, True),
              ("Neostox paper trading", 500, False),
              ("Sensibull (options analytics)", 800, False),
              ("Trading Titans Titan", M.TITAN_MO, True),
              ("TradingView Essential India", 1200, False)]
    peak = max(p for _, p, _ in market)
    for name, price, ours in market:
        bar = "\u2588" * max(1, round(price / peak * 22))
        colour = "#1A73E8" if ours else "#C3D2E2"
        rows.append([f"<b>{name}</b>" if ours else name,
                     f"<b>{money(price)}</b>" if ours else f"~{money(price)}",
                     f"<font face='{SYM}' color='{colour}' size='7'>{bar}</font>"])
    st.append(table(rows, [190, 100, 180], align=["L", "R", "L"]))
    st.append(Spacer(1, 10))
    st += bullets([
        f"<b>Pro at {money(M.PRO_MO)}</b> sits in the casual-app band, which is the right "
        f"band \u2014 most competing simulators (StockGro, Dhan) are free, so the paid pitch "
        f"has to be cheap enough not to think about.",
        f"<b>Titan at {money(M.TITAN_MO)}</b> sits in the <i>tools</i> band, against "
        f"Sensibull. Coherent, but exacting: at that price users compare feature lists "
        f"directly.",
    ])
    st.append(Spacer(1, 10))

    st.append(Paragraph(
        f"On the {M.TITAN_MO / M.PRO_MO:.1f}\u00d7 gap between tiers", S["h3"]))
    st.append(Paragraph(
        f"Standard SaaS ladders step 2\u20133\u00d7. {money(M.PRO_MO)} \u2192 "
        f"{money(M.TITAN_MO)} is a big leap, and it works only because the two tiers target "
        f"genuinely different people rather than different appetites. Watch one signal after "
        f"launch: if Titan conversion sits below ~10% of subscribers while Pro users hit their "
        f"limits often, the gap is too wide and a middle tier is being asked for. "
        f"<b>{money(399)}/mo</b> \u2014 stock F&amp;O and Greeks, without real-time data, "
        f"backtesting or the API \u2014 is the natural insert. Don't build it pre-emptively.",
        S["body"]))
    st.append(Spacer(1, 12))
    st.append(Callout(
        "Google's June 2026 Billing Choice programme (10% fee, external payment links) "
        "launched for the <b>EEA, UK and US</b>, expanding to Australia, Japan and South "
        "Korea. <b>India is not included</b>, so the 15% India rate is what applies here. "
        "Re-check before committing to Play Billing. Rates verified against Razorpay, Google "
        "Play and Indian GST published guidance.",
        title="Source note", accent=INK4, fill=PARCHMENT))

    # ---- 8. Decisions ------------------------------------------------------
    st.append(PageBreak())
    st += h2("Decisions needed to finalise the numbers", "section 07")
    st.append(Paragraph(
        "Ten open calls. The two that move the numbers most are D1 and D9.", S["body"]))
    st.append(Spacer(1, 8))

    decisions = [
        ("D1", "Cash stipends per tier",
         f"Proposed {money(50000)}/mo on Pro and {money(500000)}/mo on Titan, "
         f"<b>non-cumulative</b> so unused stipend lapses. Non-cumulative is the important "
         f"word: it drives monthly re-engagement without inflating balances or creating a "
         f"\u201ccancel and keep the cash\u201d exit."),
        ("D2", "Is purchased cash protected from resets?",
         "If seasons or challenges ever reset wallets, wiping paid-for cash is a refund "
         "conversation and a chargeback risk. Recommend purchased cash is floored and never "
         "reset. Decide before the first sale."),
        ("D3", f"Titan annual at {money(5999)} (37% off) or {money(6499)} (32% off)?",
         f"{money(5999)} gives the cleaner {money(500)}/mo effective and pulls harder to "
         f"annual prepay; {money(6499)} keeps the discount consistent with Pro's 33%. Worth "
         f"about {money(500)} per subscriber per year."),
        ("D4", "Free trial?",
         "7 days lifts conversion materially and is the norm. Strongly recommended on "
         f"<b>Titan specifically</b> \u2014 {money(799)} is a real decision, and a trial does "
         f"the selling a feature list cannot."),
        ("D5", "Pre-empt the GST cliff or absorb it?",
         f"Now arriving at ~{M.gst_cliff_users():,} users, sooner than the single-tier model. "
         f"Easier to launch at the higher price than to raise it later."),
        ("D6", "Refund policy",
         "Instantly-delivered virtual goods are normally non-refundable, but Play's rules "
         "override yours on Play purchases."),
        ("D7", "Are there ads?",
         "\u201cAd-free\u201d is listed as a Pro benefit but there are no ads in the product. "
         "Drop the line or plan the ad tier \u2014 a benefit that removes nothing is one "
         "users notice is fake."),
        ("D8", "Web-first or Play-first?",
         f"Web is one integration, no policy risk, 11 points better margin \u2014 worth "
         f"{money(M.web_post(M.TITAN_YR) - M.play(M.TITAN_YR))}/yr on every Titan annual. But "
         f"most users are on mobile and the app cannot legally point them to web. "
         f"Recommendation: launch web checkout, sell enterprise directly, add Play Billing "
         f"once revenue justifies the work."),
        ("D9", "Launch sequence for the two tiers",
         "Pro can ship on close to today's feature set. Titan needs real-time data, Greeks, a "
         "real IV surface, the strategy builder and backtesting first. Recommend <b>Pro at "
         "launch, Titan as a second release</b> \u2014 with Titan announced as "
         "\u201ccoming\u201d so Pro buyers can see the ladder."),
        ("D10", "Founding-member grandfathering",
         "The 176 existing users signed up to a product advertised as free. Recommend "
         "permanent free <b>Pro</b> (not Titan) \u2014 costs \u20b90 in real revenue, makes a "
         "decent announcement, keeps the paid cohort measurable, and leaves Titan as something "
         "they can still be upsold."),
    ]
    data = [[Paragraph(f"<b>{tag}</b>", ParagraphStyle(
        "dt", parent=S["td"], fontName=BOLD, fontSize=9, textColor=BLUE)),
        Paragraph(f"<b>{title}</b><br/>{body}", S["note"])] for tag, title, body in decisions]
    t = Table(data, colWidths=[36, CONTENT_W - 36], hAlign="LEFT")
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, HAIRLINE),
    ]))
    st.append(t)
    return st


def main() -> None:
    if "--check" in sys.argv:
        check()
        return
    check()  # never ship a PDF whose arithmetic has drifted
    register_fonts()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    doc = BaseDocTemplate(
        str(OUTPUT), pagesize=A4,
        leftMargin=50, rightMargin=50, topMargin=64, bottomMargin=56,
        title="Trading Titans \u2014 Monetisation & Pricing Plan",
        author="Kashivwealth Management LLP", subject="Commercial pricing plan",
    )
    full = Frame(50, 56, CONTENT_W, A4[1] - 64 - 56, id="full",
                 leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[full], onPage=cover_page),
        PageTemplate(id="content", frames=[full], onPage=content_page),
    ])
    doc.build(build_story())
    size = OUTPUT.stat().st_size / 1024
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({size:.0f} KB)")


if __name__ == "__main__":
    main()
