"""A DWF 6 package: a `(DWF V06.00)` header in front of a zip of sheets."""

from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree

from . import hebrew, whip

MAGIC = b"(DWF V"


def is_dwf(data: bytes) -> bool:
    return data.startswith(MAGIC)


@dataclass
class Sheet:
    number: int            # plot order, from 1
    title: str             # as published: `4382.26-1-15`
    page: whip.Page


def _decoded(page: whip.Page) -> whip.Page:
    """Hebrew decoded, and texts drawn twice at one spot kept once.

    AutoCAD plots a title block's fixed text on two layers at the same
    position; one copy is enough.
    """
    seen: set[tuple[int, int, str]] = set()
    texts = []
    for text in page.texts:
        key = (text.x, text.y, text.text)
        if key in seen:
            continue
        seen.add(key)
        text.text = hebrew.decode(text.text).strip()
        if text.text:
            texts.append(text)
    page.texts = texts
    return page


def read(source: Path | bytes) -> list[Sheet]:
    data = source if isinstance(source, bytes) else Path(source).read_bytes()
    if not is_dwf(data):
        raise whip.WhipError("not a DWF package")
    # The zip follows the 12-byte header; zipfile finds it from the end.
    archive = zipfile.ZipFile(io.BytesIO(data))
    names = {name.replace("\\", "/"): name for name in archive.namelist()}
    manifest = ElementTree.fromstring(archive.read(names["manifest.xml"]))
    sheets = []
    for section in manifest.iter():
        if not section.tag.endswith("Section") or section.get("type") != "com.autodesk.dwf.ePlot":
            continue
        href = next(
            (r.get("href") for r in section.iter() if r.tag.endswith("Resource")
             and r.get("mime") == "application/x-w2d"),
            None,
        )
        if href is None:
            continue
        page = whip.read(archive.read(names[href.replace("\\", "/")]))
        sheets.append(Sheet(len(sheets) + 1, section.get("title") or "", _decoded(page)))
    if not sheets:
        raise whip.WhipError("the DWF holds no 2D sheets")
    return sheets


def board_number(sheets: list[Sheet]) -> str:
    """`4382.26-1-15` -> `4382.26-1`: the published sheet title less its page."""
    titles = [re.sub(r"-\d+$", "", s.title) for s in sheets if s.title]
    return max(set(titles), key=titles.count) if titles else ""
