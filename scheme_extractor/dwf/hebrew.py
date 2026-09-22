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
# A size or a quantity with a unit: 4x150, 10mm, 2.5kw.
_MEASURE = re.compile(r"^[\d.,*/+-]*\d[\d.,x*/+-]*(?:mm|cm|m|kw|kva|kv|v|a|ma|hz)?$")


def decode_word(word: str) -> str:
    if (
        word.lower() in LATIN
        or "@" in word
        or any(c.isupper() for c in word)
        or not any("a" <= c <= "z" for c in word)
        or _MEASURE.match(word.lower())
    ):
        return word
    return "".join(KEYS.get(c, c) for c in word)


# A word with no letter key can still be Hebrew: `,/` is ת. (the ת key is
# the comma). It is read as Hebrew only beside a Hebrew word.
_LETTERLESS = re.compile(r"^[,;][/.]?$")


def decode(text: str) -> str:
    """A label's Hebrew decoded. The Hebrew font draws the whole label right
    to left, so a Latin or number word inside a Hebrew label is typed
    backwards to read forwards on paper (`AK01` is 10KA, `SPU` is UPS)."""
    words = _WORD.findall(text)
    hebrew = any(decode_word(w) != w for w in words)

    def one(word: str) -> str:
        if not hebrew:
            return word
        if _LETTERLESS.match(word):
            return "".join(KEYS[c] for c in word)
        decoded = decode_word(word)
        if decoded == word and len(word) > 1 and any(c.isalnum() for c in word) and not re.search(r"[֐-׿]", word):
            return word[::-1]
        return decoded

    return _WORD.sub(lambda m: one(m.group()), text)
