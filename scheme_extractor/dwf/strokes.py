"""Labels a CAD export drew as line work instead of text.

AutoCAD writes a `?` in place of text it cannot carry to a DWF (a model in
an SHX font, a block's attribute) and draws the characters as strokes. The
glyph shapes of that font are in `strokefont.json`, normalised so a glyph is
the same whatever its size, and a label is read by looking each shape up.

A label is only read when every one of its glyphs is known, nothing else is
already written over it, and what comes out looks like a model or a rating —
better nothing than a guess where a device's model goes.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from functools import lru_cache
from pathlib import Path

from . import whip

# A model (AF38, IRLA04S, SOCOMEC) or a rating (3X40A).
READABLE = re.compile(r"[A-Z][A-Z0-9./+-]{2,15}|\d+[xX]\d+[A-Z0-9./+-]*")
CAP_HEIGHT = 0.77            # a glyph's height as a share of the font's


@lru_cache(maxsize=1)
def font() -> dict[tuple, str]:
    path = Path(__file__).with_name("strokefont.json")
    table = {}
    for char, glyphs in json.loads(path.read_text()).items():
        for glyph in glyphs:
            table[tuple(tuple(tuple(p) for p in run) for run in glyph)] = char
    return table


def _signature(glyph: list, left: float, base: float, size: float) -> tuple:
    """A glyph's strokes in units of its label's height, from its own left."""
    runs = []
    for run in glyph:
        points = tuple((round((x - left) / size, 2), round((y - base) / size, 2)) for x, y in run)
        runs.append(min(points, points[::-1]))
    return tuple(sorted(runs))


def _words(page: whip.Page, min_height: int = 40, max_height: int = 400) -> list[list[tuple]]:
    """Glyph-sized runs grouped into words: one baseline, no wide gap."""
    runs = []
    for index, run in enumerate(page.lines):
        xs = [p[0] for p in run]
        ys = [p[1] for p in run]
        width, height = max(xs) - min(xs), max(ys) - min(ys)
        if min_height <= height <= max_height and width <= 2 * height:
            runs.append((min(xs), min(ys), max(xs), max(ys), run, index))
    bands: dict[int, list] = defaultdict(list)
    for run in runs:
        bands[round(run[1] / 8)].append(run)
    words = []
    for key in sorted(bands):
        band = bands[key] + bands.get(key - 1, []) + bands.get(key + 1, [])
        band = list({id(r[4]): r for r in band}.values())
        band.sort(key=lambda r: r[0])
        size = max((r[3] - r[1] for r in band), default=0)
        word: list = []
        for run in band:
            if word and run[0] > max(r[2] for r in word) + 0.55 * size:
                words.append(word)
                word = []
            word.append(run)
        if word:
            words.append(word)
    return [w for w in words if len(w) >= 2]


def _glyphs(word: list[tuple]) -> list[list]:
    """A word's runs grouped into characters: runs that overlap in x."""
    chars: list[list] = []
    for run in sorted(word, key=lambda r: r[0]):
        if chars and run[0] <= chars[-1][0] + 2:
            chars[-1][0] = max(chars[-1][0], run[2])
            chars[-1][1].append(run[4])
        else:
            chars.append([run[2], [run[4]]])
    return [c[1] for c in chars]


def read(page: whip.Page) -> list[whip.Text]:
    """The page's stroke-drawn labels, as text with a position."""
    table = font()
    written = [(t.x, t.y, t.height) for t in page.texts if t.text.strip("? ")]
    found = []
    for word in _words(page):
        base = min(r[1] for r in word)
        left = min(r[0] for r in word)
        size = max(r[3] for r in word) - base
        if not size or any(abs(x - left) < 1.5 * size and abs(y - base) < 0.8 * size for x, y, _ in written):
            continue
        glyphs = _glyphs(word)
        # Two shaped characters at least: a pair of plain strokes is not `II`.
        if sum(1 for g in glyphs if sum(len(run) for run in g) >= 4) < 2:
            continue
        signatures = [_signature(g, min(p[0] for r in g for p in r), base, size) for g in glyphs]
        if not all(s in table for s in signatures):
            continue
        text = "".join(table[s] for s in signatures)
        if not READABLE.fullmatch(text):
            continue
        layers = [page.line_layers[r[5]] for r in word]
        found.append(whip.Text(int(left), int(base), text, max(set(layers), key=layers.count),
                               int(size / CAP_HEIGHT), 0))
    return found
