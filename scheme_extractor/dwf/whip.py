"""A reader for WHIP! 2D streams (`.w2d`), the page format inside a DWF 6.

Only what the scheme reader needs: every piece of text with its position,
layer and font, and the line work, so a sheet can be laid out and checked.
Opcode layouts follow Autodesk's DWF Toolkit (whiptk). Drawing opcodes carry
coordinates relative to the previous point, so every one of them is decoded
in order even when its content is thrown away; an opcode this reader does not
know stops it loudly rather than guessing a length and drifting.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field


class WhipError(ValueError):
    pass


@dataclass(eq=False)   # identity: two labels may carry the same words
class Text:
    x: int
    y: int
    text: str
    layer: str
    height: int
    rotation: int          # 1/65536 of a full turn; 16384 is 90 degrees


@dataclass
class Page:
    texts: list[Text] = field(default_factory=list)
    # Line work as point runs, for drawing the page back out.
    lines: list[list[tuple[int, int]]] = field(default_factory=list)
    view: tuple[int, int, int, int] | None = None   # the plotted area


class _Reader:
    def __init__(self, data: bytes):
        self.b = data
        self.i = 0
        self.x = 0
        self.y = 0
        self.layer = ""
        self.height = 0
        self.rotation = 0
        self.page = Page()

    # -- primitives ----------------------------------------------------------

    def byte(self) -> int:
        value = self.b[self.i]
        self.i += 1
        return value

    def _unpack(self, fmt: str, size: int):
        value = struct.unpack_from(fmt, self.b, self.i)[0]
        self.i += size
        return value

    def i16(self) -> int:
        return self._unpack("<h", 2)

    def u16(self) -> int:
        return self._unpack("<H", 2)

    def i32(self) -> int:
        return self._unpack("<i", 4)

    def count(self) -> int:
        """One byte, or zero and a 16-bit count above 255."""
        n = self.byte()
        return n if n else 256 + self.u16()

    def rel32(self) -> tuple[int, int]:
        self.x += self.i32()
        self.y += self.i32()
        return self.x, self.y

    def rel16(self) -> tuple[int, int]:
        self.x += self.i16()
        self.y += self.i16()
        return self.x, self.y

    def run_of(self, n: int, rel) -> list[tuple[int, int]]:
        return [rel() for _ in range(n)]

    def string(self) -> str:
        while self.b[self.i] in b" \t\r\n":
            self.i += 1
        lead = self.b[self.i]
        if lead == ord("{"):                      # 16-bit characters
            self.i += 1
            n = self.i32()
            chars = struct.unpack_from(f"<{n}H", self.b, self.i)
            self.i += 2 * n
            if self.byte() != ord("}"):
                raise WhipError(f"unterminated wide string before {self.i}")
            return "".join(map(chr, chars))
        if lead in (ord("'"), ord('"')):
            self.i += 1
            out = bytearray()
            while True:
                c = self.byte()
                if c == 0x5C:                     # backslash escapes the next byte
                    out.append(self.byte())
                elif c == lead:
                    return out.decode("latin-1")
                else:
                    out.append(c)
        start = self.i
        while self.b[self.i] not in b" \t\r\n()":
            self.i += 1
        return self.b[start:self.i].decode("latin-1")

    # -- extended opcodes ------------------------------------------------------

    def extended_ascii(self) -> None:
        """`(Name ...)`: skip to the matching paren, keeping what matters."""
        start = self.i
        depth = 1
        while depth:
            c = self.byte()
            if c in (ord("'"), ord('"')):
                while True:
                    d = self.byte()
                    if d == 0x5C:
                        self.i += 1
                    elif d == c:
                        break
            elif c == ord("("):
                depth += 1
            elif c == ord(")"):
                depth -= 1
            elif c == ord("{"):
                size = self.i32()   # read first: `self.i += self.i32()` adds to the stale offset
                self.i += size
        body = self.b[start:self.i - 1].decode("latin-1")
        words = body.split(None, 2)
        if not words:
            return
        if words[0] == "Layer" and len(words) == 3:
            self.layer = words[2].strip()
        elif words[0] == "View" and self.page.view is None:
            corners = [tuple(int(v) for v in p.split(",")) for p in body.split()[1:3]]
            (x0, y0), (x1, y1) = corners
            self.page.view = (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))

    def set_font(self) -> None:
        fields = self.u16()
        if fields & 0x0001:
            self.string()                         # name
        for bit in (0x0002, 0x0004, 0x0008, 0x0010):
            if fields & bit:                      # charset, pitch, family, style
                self.byte()
        if fields & 0x0020:
            self.height = self.i32()
        if fields & 0x0040:
            self.rotation = self.u16()
        for bit in (0x0080, 0x0100, 0x0200):      # width scale, spacing, oblique
            if fields & bit:
                self.u16()
        if fields & 0x0400:                       # flags
            self.i32()

    def text(self, position: tuple[int, int], value: str) -> None:
        self.page.texts.append(Text(position[0], position[1], value, self.layer, self.height, self.rotation))

    # -- the stream ------------------------------------------------------------

    def run(self) -> Page:
        b = self.b
        lines = self.page.lines
        while self.i < len(b):
            at = self.i
            op = self.byte()
            if op in b" \t\r\n":
                continue
            if op == ord("("):
                self.extended_ascii()
            elif op == ord("{"):                  # extended binary: size, then body
                size = self.i32()
                self.i += size
            elif op == ord("x"):
                self.text(self.rel32(), self.string())
            elif op == 0x18:                      # text with options
                position = self.rel32()
                value = self.string()
                # Option counts are stored plus one: a byte of 1 means none.
                for _ in range(2):                # overscore, underscore positions
                    for _ in range(self.count() - 1):
                        self.count()
                self.i += 32                      # bounding box: 4 points
                for _ in range(self.count() - 1): # reserved
                    self.count()
                self.text(position, value)
            elif op == 0x06:
                self.set_font()
            elif op == 0x0C:
                lines.append(self.run_of(2, self.rel16))
            elif op == ord("l"):
                lines.append(self.run_of(2, self.rel32))
            elif op == 0x10:
                lines.append(self.run_of(self.count(), self.rel16))
            elif op == ord("p"):
                lines.append(self.run_of(self.count(), self.rel32))
            elif op in (0x14, 0x8D):              # polytriangle, macro draw (16-bit)
                self.run_of(self.count(), self.rel16)
            elif op in (ord("t"), ord("m")):
                self.run_of(self.count(), self.rel32)
            elif op in (0x07, 0x11, ord("g"), ord("q")):   # Gouraud: point, RGBA
                rel = self.rel16 if op in (0x07, 0x11) else self.rel32
                for _ in range(self.count()):
                    rel()
                    self.i += 4
            elif op == 0x12:                      # circle: centre, radius
                self.rel16(); self.u16()
            elif op == ord("r"):
                self.rel32(); self.i32()
            elif op == 0x92:                      # arc: centre, radius, start, end
                self.rel32(); self.i32(); self.u16(); self.u16()
            elif op == ord("e"):                  # ellipse: centre, axes, angles
                self.rel32(); self.i32(); self.i32(); self.u16(); self.u16(); self.u16()
            elif op in (0x0B, ord("k")):          # contour set
                rel = self.rel16 if op == 0x0B else self.rel32
                sizes = [self.count() for _ in range(self.count())]
                for size in sizes:
                    lines.append(self.run_of(size, rel))
            elif op == ord("c"):
                self.byte()
            elif op == 0x03:
                self.i += 4
            elif op in (0x17, ord("N"), ord("s")):  # line weight, node, macro scale
                self.i32()
            elif op in (0xAC, 0xCC):              # layer, line pattern
                self.count()
            elif op == ord("n"):
                self.i16()
            elif op == ord("O"):                  # origin: absolute
                self.x = self.i32()
                self.y = self.i32()
            elif op in (0x0E, ord("V"), ord("v"), ord("F"), ord("f")):
                pass
            else:
                raise WhipError(f"unknown opcode 0x{op:02x} at byte {at}")
        return self.page


def read(data: bytes) -> Page:
    if not data.startswith(b"(W2D V"):
        raise WhipError("not a W2D stream")
    return _Reader(data).run()
