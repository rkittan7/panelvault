"""Hebrew as AutoCAD stores it for a Hebrew SHX font: typed on the Latin keys.

The drawing keeps the keys an Israeli keyboard would have pressed and lets
the font draw the Hebrew glyphs, so `ao pruhhey:` is שם פרויקט:. Words are
decoded one at a time: a word in lowercase letters is keyboard-Hebrew, and
one with a capital or no letter at all (FU461, 16A, XT1C, 30mA) is real
Latin and stays as written.
"""

from __future__ import annotations

import re

KEYS = {
    "t": "א", "c": "ב", "d": "ג", "s": "ד", "v": "ה", "u": "ו", "z": "ז", "j": "ח",
    "y": "ט", "h": "י", "l": "ך", "f": "כ", "k": "ל", "o": "ם", "n": "מ", "i": "ן",
    "b": "נ", "x": "ס", "g": "ע", ";": "ף", "p": "פ", ".": "ץ", "m": "צ", "e": "ק",
    "r": "ר", "a": "ש", ",": "ת", "w": "'", "q": "/", "/": ".", "'": ",",
}

# Lowercase words that are Latin on these drawings: units and e-mail parts.
LATIN = {"mm", "cm", "kg", "kv", "hz", "co", "il", "com", "www", "max", "min"}

_WORD = re.compile(r"\S+")


def decode_word(word: str) -> str:
    if (
        word.lower() in LATIN
        or "@" in word
        or any(c.isupper() for c in word)
        or not any("a" <= c <= "z" for c in word)
    ):
        return word
    return "".join(KEYS.get(c, c) for c in word)


def decode(text: str) -> str:
    return _WORD.sub(lambda m: decode_word(m.group()), text)
