# scheme_extractor

Turns a multi-sheet AutoCAD switchboard drawing PDF into a device schedule, a
bill of materials with per-sheet quantity breakdowns, an outgoing-circuit
schedule, a PLC I/O list and a findings report — auditable, with every value
either verified or explicitly flagged as unverified.

Runs as its own process because the work needs `poppler-utils` and Pillow. The
Node API in `../webapp` proxies to it; nothing else talks to it directly.

## Running it

```bash
python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt
ANTHROPIC_API_KEY=… .venv/bin/uvicorn scheme_extractor.api:app --port 8100
```

or `docker build -t scheme-extractor . && docker run -p 8100:8100 -e ANTHROPIC_API_KEY=… scheme-extractor`.

Point the Node API at it with `SCHEME_EXTRACTOR_URL` (default
`http://127.0.0.1:8100`), then:

```
POST /api/ai/scheme-extract               { fileName, data: <base64 pdf> } → { job_id }
GET  /api/ai/scheme-extract?job=<id>      → { status, stage, progress, result }
GET  /api/ai/scheme-extract-workbook?job= → the reviewer's xlsx
```

## DWF: the exact path

Send an AutoCAD DWF export instead of a PDF and none of the stages below run.
A DWF keeps every label as text with its position, so `dwf/` reads the set
as geometry, with no model and no rendering: a 42-sheet set in about a second,
for nothing.

| | | |
|---|---|---|
| `dwf/whip.py` | the WHIP! page streams inside the DWF: every text, its position, layer and font, and the line work. Opcode layouts follow Autodesk's DWF Toolkit; an unknown opcode stops the reader rather than letting it drift |
| `dwf/hebrew.py` | Hebrew stored as the keys an Israeli keyboard would press (`ao pruhhey:` is שם פרוייקט:), decoded word by word; Latin words stay |
| `dwf/sheet.py` | devices as stacked labels (`FU411 / 16A / C / ABB`), destination tables down their columns with merged cells from the drawing's rules, the parts list and data table by their ruled rows, the title block by label/value pairs, and the front elevation's cabinets |
| `dwf/strokes.py` | labels AutoCAD could not carry as text and drew as line work (the contactors' `AF38`, `IRLA04S`, `SOCOMEC`), read by matching each glyph against the stroke font in `dwf/strokefont.json` |

Things the reading has to account for:

- Every point in a page stream is relative to the one before, including the
  corners of a text's bounding box and of an embedded image. Missing either
  shifts everything after it (on 4382.26-1 a logo moved half the title block
  and a whole table 8000 units off).
- The Hebrew font draws right to left, so Latin and numbers inside a Hebrew
  label are typed backwards (`AK01` is 10KA); a label's pieces on one line
  read right to left.
- Some cells and labels sit on the frame's layer; they are told from the
  title block by not repeating on the other sheets.
- A font's rotation flag is not what is plotted: labels flagged 90° print
  level, so rotation is ignored.
- Labels the export could not carry as text are drawn as strokes with a `?`
  left in their place; `dwf/strokes.py` reads them, and only when every one
  of a label's glyphs is known, so an unreadable label stays unread rather
  than becoming a guess at a device's model.
- A model beside a device rather than under it (`AF40 / ABB` next to a
  contactor's box) is not a device of its own: it goes to the nearest device
  of its kind that has no model.
- A cabinet-door label can shorten a tag (`QU97` for `QU497`); it is not
  counted twice.

From there the run is the same: grouping, parts-list models, the board draft
and the workbook. The main breaker is the highest-rated breaker or switch.

The front elevation also gives the board's build: the row of widths that adds
up to the board's own width counts the cabinets (`500+600+600+800+800+600` is
six), and the sheet says whether it closes with panels or a plate. Both reach
the board form, which had been filling in one cabinet and Panels by default.

## Terminals from the cables

A destination table's cable is the only place a drawing says what lands on
the rail, and it says it exactly: `3x2.5N2XY` is three cores of 2.5mm. Every
core gets a rail terminal, named by the largest conductor it takes — Klemsan
AVK, nothing below AVK 4 — so 2.5mm lands on AVK 4 and 6mm on AVK 6. The
lines are flagged `from_cable_sizes`, because no drawing printed them.

## The stages

| | | |
|---|---|---|
| 0 | `stages/probe.py` | pages, size, rotation, and how much of the drawing the text layer actually carries |
| 1 | `stages/textlayer.py` | `pdftotext -bbox-layout`, transformed into rendered-pixel space and verified against an anchor |
| 2 | `stages/render.py` | one render per page, then region crops at native resolution |
| 3 | `stages/extract.py` | one call per sheet, Prompt A, structured output |
| 3b | `stages/title.py` | the title block and data table, one call, the board's identity |
| 4 | `stages/zoom.py` | 600 DPI re-crop of anything uncertain, Prompt B |
| 5 | `stages/reconcile.py` | assertions against the text layer — no model |
| 6 | `stages/rollup.py` | grouping and summation — no model |
| 7 | `stages/audit.py` | one call over the whole set, Prompt C |

## Two things worth knowing before changing anything

**Never send a whole sheet as one image and expect a table to be read.** An A4
sheet downscaled to the API's ~1568px cap puts the 5–6pt Hebrew destination
text at three or four pixels tall. The model does not error on that — it
invents plausible room names. Regions are cropped and sent at native
resolution, and wide bands are split into overlapping chunks so a merged cell
is never cut without context.

**The text layer on this producer's exports carries the sheet frame and
nothing else.** `panelvault_scheme_extraction.md` §1 and the implementation
brief §2.2 both say `pdftotext` recovers every tag, rating, model number and
cable spec. On `4382.26-8.pdf` it recovers about 178 characters a page — the
frame letters, the busbar caption, the `Inc` row label, the two designer
emails and the sheet number. Not one of the 174 terminal tags, not one F-tag,
not one `שמור`. AutoCAD exploded the drawing text to vector geometry before
the Quartz re-save.

Three things follow, and they are why this code differs from the brief:

- `probe.text_coverage` reports `rich` or `frame`, and the rest of the
  pipeline branches on it instead of assuming.
- Region detection anchors on the `Inc` row label and the table's own left
  border rule, not on terminal tokens, which do not exist. It finds the table
  on exactly the 20 sheets that have one, including sheet 17's single-column
  table that a percentage crop would have sliced in half.
- `reconcile` marks values `*_unverifiable` where the page has no drawing text
  to check against, and `*_unverified` only where it does and the value is
  missing from it. A device is sent to a human for the second, never the
  first — otherwise all 523 devices would be flagged and the flag would mean
  nothing.

If a future export keeps its text layer intact, `text_coverage` returns
`rich`, the stricter checks switch themselves on, and nothing else changes.

## Cost

Per-stage tokens and dollars land on every run under `cost`. The price table
is in `config.py`, never at a call site. A run above `$3.00` warns.

Every stage runs on Haiku 4.5 except one small call. The sheet reading is
batched on the site (half price) and asks only for what the pipeline uses: no
empty fields, no title block, no data table, no terminal devices. The audit
gets the readings as `|`-separated rows instead of JSON, a quarter of the
tokens.

The board's identity — the title block and the switchboard data table — is
read by `stages/title.py` in one call of its own on Sonnet 5, about two cents.
On 4382.26-8 Haiku paired every title field correctly once asked about nothing
else, but misread the CAD-font Hebrew letters on every attempt (חשמל as
השמחי, ס.מ.ע as ס.ה.ע); Sonnet read every field. `SCHEME_MODEL_TITLE`
moves it back to Haiku.

Every stage's model is overridable from config, the environment and the
request body.

## Tests

```bash
SCHEME_REFERENCE_PDF=/path/to/4382.26-8.pdf .venv/bin/python -m pytest scheme_extractor/tests -q
```

`tests/test_stages.py` and `tests/test_pipeline.py` run without an API key and
spend nothing — they cover geometry, hand-offs, arithmetic and flags.
`tests/golden/` holds the four accuracy metrics from the brief §9, which do
spend money and need ground truth; see `tests/golden/README.md`.
