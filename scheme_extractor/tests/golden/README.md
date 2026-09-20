# Golden set

Ground truth for one drawing set you have already checked by hand, and the
four metrics that decide whether a model can be trusted on the rest.

These tests spend real money — they run the pipeline for real. They are not
part of the default suite. Run them on every prompt change and every model
change, and never on a whim.

## Files

```
golden/
├── <drawing>.pdf              the drawing set itself (not committed — see below)
├── <drawing>.truth.json       the verified ground truth
└── README.md
```

The PDFs are customers' IP and are not committed. Keep them wherever your
team keeps drawings and point `SCHEME_GOLDEN_DIR` at it.

## `<drawing>.truth.json`

```json
{
  "drawing_no": "4382.26-8",
  "sheets": 35,
  "device_units": 523,
  "bom": [
    {"device_class": "mcb", "poles": "1P", "rating": "10A",  "qty": 29},
    {"device_class": "mcb", "poles": "1P", "rating": "16A",  "qty": 119},
    {"device_class": "mcb", "poles": "1P", "rating": "20A",  "qty": 6},
    {"device_class": "mcb", "poles": "1P", "rating": "32A",  "qty": 4},
    {"device_class": "mcb", "poles": "3P", "rating": "3X16A", "qty": 11},
    {"device_class": "mcb", "poles": "3P", "rating": "3X40A", "qty": 7},
    {"device_class": "mcb", "poles": "3P", "rating": "3X63A", "qty": 1},
    {"device_class": "rcd", "poles": "2P", "rating": "2X40A", "sensitivity": "30mA", "qty": 44},
    {"device_class": "motor_protection", "model": "MS116", "qty": 8},
    {"device_class": "mccb", "model": "XT1C", "qty": 10},
    {"device_class": "mccb", "model": "XT3N", "qty": 1},
    {"device_class": "lamp", "qty": 13}
  ],
  "circuits": {"total": 174, "spare": 54, "unlabelled": 7},
  "cells": [
    {"sheet": "06", "terminal": "X361", "destination_he": "ח. תקשורת \"ש\"\n2kW",
     "span_terminals": ["X361"], "is_spare": false}
  ],
  "findings": [
    {"type": "duplicate_tag",  "item": "F381",     "sheets": ["06", "24"]},
    {"type": "duplicate_tag",  "item": "FB04.1",   "sheets": ["08", "30"]},
    {"type": "contradiction",  "item": "XU497",    "sheets": ["17", "21"]},
    {"type": "suspected_typo", "item": "FU10.2",   "sheets": ["12"]},
    {"type": "model_mismatch", "item": "TM3DQ16",  "sheets": ["18", "22"]},
    {"type": "bom_list_gap",   "item": "equipment list", "sheets": ["35"]}
  ]
}
```

`cells` is the expensive part to build and the one that matters most: every
destination cell in the set, with its verbatim Hebrew and its true span.
Merged-span accuracy and Hebrew fidelity are both measured against it.

## The four metrics

| Metric | Definition | Gate |
|---|---|---|
| Merged-span accuracy | destination cells with exactly the right `span_terminals` | ≥ 99% |
| Hebrew fidelity | exact string match on `destination_he`, quote marks and abbreviations included | ≥ 99% |
| Tag recall | tags in the text layer that appear in the extraction | 100% |
| Spare discipline | cells marked `is_spare` where שמור is actually printed | 100% |

**Tag recall does not apply to this producer's drawings.** The brief calls it
"objective and un-gameable", and it is — when the text layer carries the
drawing. On `4382.26-8.pdf` the text layer carries the sheet frame and nothing
else, so the denominator is close to zero and the metric passes no matter what
the model does. `run_golden.py` reports it as `n/a` with the token count that
made it so, rather than printing a meaningless 100%. Substitute the ground
truth's own tag list: `tag_recall_vs_truth` below is the real check.

## Running

```bash
SCHEME_GOLDEN_DIR=/path/to/drawings \
ANTHROPIC_API_KEY=… \
python -m scheme_extractor.tests.golden.run_golden 4382.26-8
```

Swap a stage's model with `--model audit=claude-sonnet-5` and compare the
scorecards. Upgrade stage 7 before stage 3: the audit is where extra
capability converts into caught errors, and stage 3 is the bulk of the bill.
