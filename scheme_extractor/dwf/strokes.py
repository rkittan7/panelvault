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
READABLE = re.compile(
    r"[A-Z][A-Z0-9./+-]{2,15}"           # a tag or a model: FU491, IRLA04S, SOCOMEC
    r"|\d+[xX]\d+[A-Z0-9./+-]*"          # a rating written by poles: 3X40A
    r"|\d{1,4}(?:\.\d+)?A(?:\+N)?"      # or by current, with a neutral: 16A+N
)
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
    """Glyph-sized runs grouped into words: one baseline, no wide gap.

    A letter is not always one stroke — some exports draw A's and F's bar
    apart from the rest — so flat pieces are collected too and given to the
    word whose box holds them.
    """
    runs, bars = [], []
    for index, run in enumerate(page.lines):
        xs = [p[0] for p in run]
        ys = [p[1] for p in run]
        width, height = max(xs) - min(xs), max(ys) - min(ys)
        piece = (min(xs), min(ys), max(xs), max(ys), run, index)
        if min_height <= height <= max_height and width <= 2 * height:
            runs.append(piece)
        elif height < min_height and min_height * 0.2 <= width <= max_height:
            bars.append(piece)
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
            # A letter's gap in these fonts runs to about half its height;
            # anything wider is the space between two labels.
            if word and run[0] > max(r[2] for r in word) + 0.75 * size:
                words.append(word)
                word = []
            word.append(run)
        if word:
            words.append(word)
    full = []
    for word in words:
        if len(word) < 2:
            continue
        left = min(r[0] for r in word)
        right = max(r[2] for r in word)
        base = min(r[1] for r in word)
        top = max(r[3] for r in word)
        full.append(word + [b for b in bars if left <= b[0] and b[2] <= right and base <= b[1] <= top])
    return full


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


def _hinted(hints: list[whip.Text], left: float, base: float, size: float) -> str | None:
    """A single character written over this glyph names it."""
    near = sorted(
        ((abs(t.x - left) + abs(t.y - base), t) for t in hints
         if abs(t.x - left) < 0.5 * size and abs(t.y - base) < 1.2 * size),
        key=lambda pair: pair[0],
    )
    if not near or (len(near) > 1 and near[1][0] < 1.5 * near[0][0] + 0.2 * size):
        return None          # two characters as close: neither names this glyph
    return near[0][1].text.strip()


def read(page: whip.Page) -> list[whip.Text]:
    """The page's stroke-drawn labels, as text with a position.

    Some exports keep one character of a label as text and draw the whole
    label anyway (a lone `F` over the strokes of `FU491`). Such a character
    names the glyph under it, so it is used where the shape is unknown.
    """
    table = font()
    written = [(t.x, t.y, len(t.text.strip())) for t in page.texts if t.text.strip("? ")]
    hints = [t for t in page.texts if len(t.text.strip()) == 1 and t.text.strip().isalnum()]
    found = []
    for word in _words(page):
        base = min(r[1] for r in word)
        left = min(r[0] for r in word)
        size = max(r[3] for r in word) - base
        if not size:
            continue
        glyphs = _glyphs(word)
        # Text already written over the label: an export that kept the whole
        # label needs no reading. A stray character of one it lost (a lone
        # `F` where `FU491` is drawn) does not count as the label.
        if any(abs(x - left) < 1.5 * size and abs(y - base) < size and 2 * length >= len(glyphs)
               for x, y, length in written):
            continue
        # Two shaped characters at least: a pair of plain strokes is not `II`.
        if sum(1 for g in glyphs if sum(len(run) for run in g) >= 4) < 2:
            continue
        characters = []
        hinted = 0
        for glyph in glyphs:
            left_edge = min(p[0] for r in glyph for p in r)
            char = table.get(_signature(glyph, left_edge, base, size))
            if char is None:
                char = _hinted(hints, left_edge, base, size)
                hinted += 1
            characters.append(char)
        # One character may be named by the text written over it, and only in
        # a label the font already reads: a row of identical symbols under a
        # phase marker is not the word `RRRRRR`.
        if not all(characters) or hinted > 1 or len(glyphs) - hinted < 2:
            continue
        text = "".join(characters)
        if not READABLE.fullmatch(text):
            continue
        # Part of a label the export did keep: `Inc=100A` is written there,
        # and only its `100A` was drawn in a font this table knows.
        if any(text in t.text and abs(t.x - left) < 4 * size and abs(t.y - base) < 1.5 * size
               for t in page.texts):
            continue
        layers = [page.line_layers[r[5]] for r in word]
        found.append(whip.Text(int(left), int(base), text, max(set(layers), key=layers.count),
                               int(size / CAP_HEIGHT), 0))
    return found
