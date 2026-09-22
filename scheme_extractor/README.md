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

## The stages

| | | |
|---|---|---|
| 0 | `stages/probe.py` | pages, size, rotation, and how much of the drawing the text layer actually carries |
| 1 | `stages/textlayer.py` | `pdftotext -bbox-layout`, transformed into rendered-pixel space and verified against an anchor |
| 2 | `stages/render.py` | one render per page, then region crops at native resolution |
| 3 | `stages/extract.py` | one call per sheet, Prompt A, structured output |
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
is in `config.py`, never at a call site. A full run of 4382.26-8 costs about
$2.20; one above `$3.00` warns, because the only two ways to get there are a
missed cache or a zoom stage firing on most sheets — both real problems.

Sheets are read by Sonnet 5, and so is the sheet sent with the title block
(the `title` stage). Both were Haiku 4.5 at first; on this drawing Haiku
misread the Hebrew title block wholesale, hung columns on a group RCD and
dropped model numbers, where Sonnet read the same sheets right. Zoom and
audit stay on Haiku.

Every stage's model is overridable from config, the environment
(`SCHEME_MODEL_EXTRACT=claude-haiku-4-5`) and the request body.

## Tests

```bash
SCHEME_REFERENCE_PDF=/path/to/4382.26-8.pdf .venv/bin/python -m pytest scheme_extractor/tests -q
```

`tests/test_stages.py` and `tests/test_pipeline.py` run without an API key and
spend nothing — they cover geometry, hand-offs, arithmetic and flags.
`tests/golden/` holds the four accuracy metrics from the brief §9, which do
spend money and need ground truth; see `tests/golden/README.md`.
