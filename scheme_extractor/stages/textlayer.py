"""Stage 1 — the text layer, in rendered-pixel space.

`pdftotext -bbox-layout` gives every word a box in PDF points. Stage 2 crops
regions out of a rendered PNG, so those boxes are only useful once they are
in the same coordinate frame as the image. That conversion is where page
rotation bites: these drawings are A4 portrait pages with `Page rot: 270`,
and poppler and pdftoppm do not agree about whose job it is to apply it.

Rather than trust either, the transform is chosen by measuring the tokens
against both candidate frames, and then verified against a known anchor. A
page whose anchor does not land where it must fails loudly — a silently
misaligned crop sends the model a picture of the wrong part of the sheet,
which is far worse than a missing page.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

WORD = re.compile(
    r'<word xMin="([\d.eE+-]+)" yMin="([\d.eE+-]+)" xMax="([\d.eE+-]+)" yMax="([\d.eE+-]+)">([^<]*)</word>'
)
PAGE = re.compile(r'<page width="([\d.eE+-]+)" height="([\d.eE+-]+)">')

# XHTML escapes poppler emits inside <word>.
ENTITIES = {"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'"}


class AnchorError(RuntimeError):
    """The page's coordinate transform could not be verified."""


@dataclass(frozen=True)
class Token:
    text: str
    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def x(self) -> float:
        return self.x0

    @property
    def y(self) -> float:
        return self.y0

    @property
    def w(self) -> float:
        return self.x1 - self.x0

    @property
    def h(self) -> float:
        return self.y1 - self.y0

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) / 2

    @property
    def cy(self) -> float:
        return (self.y0 + self.y1) / 2


@dataclass
class PageTokens:
    page: int
    tokens: list[Token]
    anchors: dict[str, Token | None]
    width: int                      # rendered pixels
    height: int
    dpi: int
    notes: list[str] = field(default_factory=list)

    def texts(self) -> set[str]:
        return {t.text for t in self.tokens}

    def matching(self, pattern: re.Pattern[str]) -> list[Token]:
        return [t for t in self.tokens if pattern.search(t.text)]


def _unescape(value: str) -> str:
    for entity, char in ENTITIES.items():
        value = value.replace(entity, char)
    return value


def rendered_size(page_size: tuple[float, float], rotation: int, dpi: int) -> tuple[int, int]:
    """What pdftoppm will produce for this page.

    pdftoppm applies `Page rot`, so a 595x842 portrait page rotated 270
    renders as a 842x595 landscape image.
    """
    width, height = page_size
    if rotation % 180 == 90:
        width, height = height, width
    return round(width * dpi / 72), round(height * dpi / 72)


def page_tokens(
    pdf: Path,
    page: int,
    *,
    page_size: tuple[float, float],
    rotation: int,
    dpi: int,
    timeout: int = 120,
) -> PageTokens:
    result = subprocess.run(
        ["pdftotext", "-bbox-layout", "-f", str(page), "-l", str(page), str(pdf), "-"],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    # Poppler's stderr is noise on these files; only the exit code matters.
    if result.returncode != 0 and not result.stdout:
        raise RuntimeError(f"pdftotext failed on page {page}: {result.stderr.strip()[:400]}")

    raw = [
        (float(a), float(b), float(c), float(d), _unescape(text))
        for a, b, c, d, text in WORD.findall(result.stdout)
    ]

    width_px, height_px = rendered_size(page_size, rotation, dpi)
    scale = dpi / 72.0
    notes: list[str] = []

    # Which frame are these boxes already in? Poppler reports the MediaBox in
    # <page>, but on a rotated page it emits word coordinates in the rotated
    # frame. Measure rather than assume: pick whichever orientation actually
    # contains every token.
    page_w, page_h = page_size
    rotated_w, rotated_h = (page_h, page_w) if rotation % 180 == 90 else (page_w, page_h)
    max_x = max((r[2] for r in raw), default=0.0)
    max_y = max((r[3] for r in raw), default=0.0)

    if max_x <= rotated_w + 1 and max_y <= rotated_h + 1:
        # Already rotated — a straight scale is all that is needed.
        def place(x0: float, y0: float, x1: float, y1: float) -> tuple[float, float, float, float]:
            return x0 * scale, y0 * scale, x1 * scale, y1 * scale
    elif max_x <= page_w + 1 and max_y <= page_h + 1 and rotation % 360 == 270:
        notes.append("Token boxes were in unrotated page space; applied Page rot 270.")

        def place(x0: float, y0: float, x1: float, y1: float) -> tuple[float, float, float, float]:
            # 270 clockwise: (x, y) -> (y, page_w - x)
            nx0, nx1 = y0 * scale, y1 * scale
            ny0, ny1 = (page_w - x1) * scale, (page_w - x0) * scale
            return nx0, ny0, nx1, ny1
    elif max_x <= page_w + 1 and max_y <= page_h + 1 and rotation % 360 == 90:
        notes.append("Token boxes were in unrotated page space; applied Page rot 90.")

        def place(x0: float, y0: float, x1: float, y1: float) -> tuple[float, float, float, float]:
            nx0, nx1 = (page_h - y1) * scale, (page_h - y0) * scale
            ny0, ny1 = x0 * scale, x1 * scale
            return nx0, ny0, nx1, ny1
    else:
        raise AnchorError(
            f"Page {page}: token extent {max_x:.0f}x{max_y:.0f}pt fits neither "
            f"{page_w:.0f}x{page_h:.0f} nor {rotated_w:.0f}x{rotated_h:.0f}."
        )

    tokens = [Token(text, *place(x0, y0, x1, y1)) for x0, y0, x1, y1, text in raw]
    anchors = find_anchors(tokens, width_px, height_px)
    verify_anchors(page, anchors, width_px, height_px)
    return PageTokens(page, tokens, anchors, width_px, height_px, dpi, notes)


SHEET_NUMBER = re.compile(r"^\d{1,3}$")
TITLE_BLOCK = re.compile(r"E-Maill|@")


def find_anchors(tokens: list[Token], width: int, height: int) -> dict[str, Token | None]:
    """Two fixed points that every sheet in the set carries.

    The sheet label sits in the bottom-left corner of the frame, and the
    designer's email addresses sit in the title block. Both survive in the
    text layer on every page, which is what makes them usable as anchors.
    """
    bottom_left = [
        t for t in tokens
        if SHEET_NUMBER.match(t.text) and t.cy > height * 0.90 and t.cx < width * 0.15
    ]
    title = [t for t in tokens if TITLE_BLOCK.search(t.text)]
    return {
        "sheet_label": min(bottom_left, key=lambda t: t.cx) if bottom_left else None,
        "title_block": min(title, key=lambda t: t.y0) if title else None,
    }


def verify_anchors(page: int, anchors: dict[str, Token | None], width: int, height: int) -> None:
    """Fail the page rather than crop it wrong.

    A transform that is off by a rotation puts the sheet label somewhere
    other than the bottom-left corner. Catching that here costs one
    comparison; not catching it costs a sheet of fabricated data.
    """
    found = [name for name, token in anchors.items() if token is not None]
    if not found:
        raise AnchorError(
            f"Page {page}: no anchor token found, so the bbox-to-pixel transform cannot be verified."
        )
    label = anchors.get("sheet_label")
    if label is not None and not (label.cx < width * 0.15 and label.cy > height * 0.90):
        raise AnchorError(
            f"Page {page}: sheet label landed at ({label.cx:.0f}, {label.cy:.0f}) in a "
            f"{width}x{height} image, not the bottom-left corner."
        )
    title = anchors.get("title_block")
    if title is not None and title.cy < height * 0.60:
        raise AnchorError(
            f"Page {page}: title block landed at y={title.cy:.0f} in a {height}px image, "
            "which is not the bottom of the sheet."
        )
