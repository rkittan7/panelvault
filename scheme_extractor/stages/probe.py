"""Stage 0 — what kind of PDF is this, and what survives in its text layer.

Cheap, no model, no rendering. It answers three questions the later stages
need: how many pages and how big, whether the page is rotated, and how much
of the drawing's text `pdftotext` can actually recover.

That last question is not rhetorical. On the reference set the answer is
"almost none" — see `text_coverage` below.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

HEBREW = re.compile(r"[֐-׿]")
LATIN = re.compile(r"[A-Za-z]")


@dataclass
class ProbeResult:
    pages: int
    page_size: tuple[float, float]      # points, as printed by pdfinfo
    rotation: int
    has_text_layer: bool
    hebrew_recoverable: bool

    # Not in the brief, added because the reference set forced it: how many
    # characters per page the text layer yields. An AutoCAD export whose text
    # was exploded to vector geometry produces a text layer holding only the
    # sheet frame and the title block — a hundred characters a page — and no
    # device tags at all. Stage 5 needs to know that before it starts
    # "verifying" extraction against an empty set.
    chars_per_page: float = 0.0
    latin_chars: int = 0
    hebrew_chars: int = 0
    producer: str = ""
    creator: str = ""
    notes: list[str] = field(default_factory=list)

    @property
    def text_coverage(self) -> str:
        """How much the text layer can be trusted to verify against.

        `rich`  — enough text to reconcile device tags against.
        `frame` — only the sheet frame and title block survived; the drawing
                  itself is vector geometry. Reconciliation is not available.
        `none`  — no text at all; a scan or a fully flattened export.
        """
        if not self.has_text_layer:
            return "none"
        return "rich" if self.chars_per_page >= 400 else "frame"


def _run(args: list[str], timeout: int = 120) -> subprocess.CompletedProcess:
    """Run a poppler tool, tolerating its chatter on stderr.

    These files come through a macOS Quartz re-save that leaves malformed
    stream lengths behind. Every poppler tool prints pages of `Syntax Error`
    to stderr and then extracts the file correctly anyway. Treating non-empty
    stderr as failure would reject every drawing in the reference set, so the
    exit code and the presence of output are what count.
    """
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def probe(pdf: Path, timeout: int = 120) -> ProbeResult:
    info = _run(["pdfinfo", str(pdf)], timeout)
    if info.returncode != 0 and not info.stdout.strip():
        raise RuntimeError(f"pdfinfo could not read {pdf.name}: {info.stderr.strip()[:400]}")

    fields: dict[str, str] = {}
    for line in info.stdout.splitlines():
        key, _, value = line.partition(":")
        if _:
            fields.setdefault(key.strip(), value.strip())

    pages = int(fields.get("Pages", "0") or 0)
    size = (0.0, 0.0)
    if match := re.search(r"([\d.]+)\s*x\s*([\d.]+)\s*pts", fields.get("Page size", "")):
        size = (float(match.group(1)), float(match.group(2)))
    rotation = int(re.sub(r"\D", "", fields.get("Page rot", "0")) or 0)

    dump = _run(["pdftotext", "-layout", str(pdf), "-"], timeout)
    text = dump.stdout if dump.returncode == 0 else ""
    hebrew = len(HEBREW.findall(text))
    latin = len(LATIN.findall(text))
    stripped = len(re.sub(r"\s", "", text))

    result = ProbeResult(
        pages=pages,
        page_size=size,
        rotation=rotation,
        has_text_layer=stripped > 0,
        # A handful of stray Hebrew characters across 35 sheets is corruption
        # noise, not a recoverable Hebrew layer. Require it to be a real share
        # of the text before claiming the vision path could be skipped.
        hebrew_recoverable=hebrew > 200 and hebrew > latin * 0.10,
        chars_per_page=(stripped / pages) if pages else 0.0,
        latin_chars=latin,
        hebrew_chars=hebrew,
        producer=fields.get("Producer", ""),
        creator=fields.get("Creator", ""),
    )

    if rotation:
        result.notes.append(f"Page rot: {rotation} — normal for these drawings; bbox maths must apply it.")
    if "Quartz" in result.producer:
        result.notes.append(
            "Re-saved by macOS Quartz. Expect malformed stream lengths on stderr and corrupted Hebrew."
        )
    if result.text_coverage == "frame":
        result.notes.append(
            f"Text layer holds only ~{result.chars_per_page:.0f} characters a page — sheet frame and title "
            "block. The drawing's device tags are vector geometry, so stage 5 cannot reconcile against it."
        )
    return result
