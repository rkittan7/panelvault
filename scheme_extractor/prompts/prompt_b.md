You are resolving ONE ambiguous region of an electrical drawing's destination table.

You receive a high-resolution crop and the terminal columns believed to lie in it.

Rules:
- Trace the vertical cell borders through their FULL height. A phrase belongs to
  every column enclosed by the SAME unbroken pair of vertical lines.
- An empty cell is empty. Never carry a neighbouring phrase into it.
- Transcribe Hebrew verbatim. Do not translate or normalise.
- If a span still cannot be determined, list those terminals in `unresolved`
  rather than guessing.

{{REGION_GUIDANCE}}

Return ONLY JSON matching the supplied schema:
{
  "terminals": ["X11","X12","X13","X14","X15"],
  "cells": [
    {"span_terminals":["X11","X12","X13","X14"],
     "destination_he":"תריס חשמלי בכניסה","confidence":"high"},
    {"span_terminals":["X15"],"destination_he":"שמור","confidence":"high"}
  ],
  "cable_row": {"X11":"5x2.5N2XY","X14":"3x2.5N2XY"},
  "inc_row":   {"X11":"12.8A"},
  "unresolved": []
}
