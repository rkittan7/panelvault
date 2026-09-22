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
| `dwf/sheet.py` | devices as stacked labels (`FU411 / 16A / C / ABB`), destination tables down their columns with merged cells from the drawing's rules, the parts list and data table by their ruled rows, and the title block by label/value pairs |

Two things the geometry has to account for: AutoCAD plots a title block's
labels in paper space and its values in model space, so the offset between
them is measured on the one pair whose value is known (the drawing number);
and a few labels are exported only as strokes, with no text behind them, so
they cannot be read (QU1 on 4382.26-1).

From there the run is the same: grouping, parts-list models, the board draft
and the workbook. The main breaker is the highest-rated breaker or switch.

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
