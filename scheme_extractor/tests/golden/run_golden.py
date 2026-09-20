"""Score a real run against verified ground truth (§9).

This spends money. It runs the whole pipeline on a drawing set you have
already checked by hand, then reports the four metrics that decide whether a
model can be trusted, plus the known-good totals and the known findings.

    python -m scheme_extractor.tests.golden.run_golden 4382.26-8 \
        --model audit=claude-sonnet-5
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from ...config import Config
from ...models.schema import SPARE_WORDS, ExtractionRun
from ...pipeline import run as run_pipeline
from ...stages.probe import probe
from ...stages.reconcile import DRAWING_TOKEN

GATES = {
    "merged_span_accuracy": 0.99,
    "hebrew_fidelity": 0.99,
    "tag_recall_vs_truth": 1.00,
    "spare_discipline": 1.00,
}


@dataclass
class Metric:
    name: str
    hits: int
    total: int
    note: str = ""

    @property
    def score(self) -> float | None:
        return self.hits / self.total if self.total else None

    def line(self) -> str:
        gate = GATES.get(self.name)
        if self.score is None:
            return f"  {self.name:<24} n/a      {self.note}"
        verdict = "" if gate is None else ("PASS" if self.score >= gate else "FAIL")
        gate_text = "" if gate is None else f" (gate {gate:.0%})"
        return (
            f"  {self.name:<24} {self.score:>6.1%} {verdict:<5}"
            f"{self.hits}/{self.total}{gate_text} {self.note}"
        )


def score(result: ExtractionRun, truth: dict, pdf: Path) -> list[Metric]:
    metrics: list[Metric] = []
    by_key = {(row.sheet_label, row.terminal): row for row in result.circuits}

    cells = truth.get("cells", [])
    span_hits = sum(
        1 for cell in cells
        if (row := by_key.get((cell["sheet"], cell["terminal"])))
        and row.span_terminals == cell["span_terminals"]
    )
    metrics.append(Metric("merged_span_accuracy", span_hits, len(cells)))

    hebrew_hits = sum(
        1 for cell in cells
        if (row := by_key.get((cell["sheet"], cell["terminal"])))
        and (row.destination_he or "") == (cell.get("destination_he") or "")
    )
    metrics.append(Metric("hebrew_fidelity", hebrew_hits, len(cells)))

    # Tag recall against the text layer is the brief's metric. It is only
    # meaningful when the text layer carries the drawing, so say so when it
    # does not rather than printing a 100% that measures nothing.
    meta = probe(pdf)
    if meta.text_coverage == "rich":
        from ...stages.textlayer import page_tokens
        layer: set[str] = set()
        for page in range(1, meta.pages + 1):
            tokens = page_tokens(pdf, page, page_size=meta.page_size, rotation=meta.rotation, dpi=220)
            layer |= {t.text for t in tokens.tokens if DRAWING_TOKEN.match(t.text)}
        extracted = {tag for line in result.bom for tag in line.tags}
        metrics.append(Metric("tag_recall_text_layer", len(layer & extracted), len(layer)))
    else:
        metrics.append(Metric(
            "tag_recall_text_layer", 0, 0,
            note=f"text layer holds ~{meta.chars_per_page:.0f} chars/page — frame only, nothing to recall against",
        ))

    truth_tags = {tag for line in truth.get("bom", []) for tag in line.get("tags", [])}
    if truth_tags:
        extracted = {tag for line in result.bom for tag in line.tags}
        metrics.append(Metric("tag_recall_vs_truth", len(truth_tags & extracted), len(truth_tags)))

    marked = [row for row in result.circuits if row.is_spare]
    honest = sum(1 for row in marked if any(w in (row.destination_he or "") for w in SPARE_WORDS))
    metrics.append(Metric("spare_discipline", honest, len(marked)))
    return metrics


def compare_totals(result: ExtractionRun, truth: dict) -> list[str]:
    """§9's known-good totals. Any run that misses them has a bug."""
    problems: list[str] = []
    units = sum(line.qty for line in result.bom)
    if (expected := truth.get("device_units")) and units != expected:
        problems.append(f"device units: {units}, expected {expected}")
    for key, actual in (
        ("total", result.counts.total),
        ("spare", result.counts.spare),
        ("unlabelled", result.counts.unlabelled),
    ):
        expected = truth.get("circuits", {}).get(key)
        if expected is not None and actual != expected:
            problems.append(f"circuits.{key}: {actual}, expected {expected}")
    for line in truth.get("bom", []):
        matches = [
            l for l in result.bom
            if all(getattr(l, field) == value for field, value in line.items() if field not in {"qty", "tags"})
        ]
        got = sum(l.qty for l in matches)
        if got != line["qty"]:
            label = " ".join(str(v) for k, v in line.items() if k not in {"qty", "tags"})
            problems.append(f"{label}: {got}, expected {line['qty']}")
    return problems


def compare_findings(result: ExtractionRun, truth: dict) -> list[str]:
    found = {(f.type, f.item) for f in result.audit.findings}
    missed = []
    for expected in truth.get("findings", []):
        key = (expected["type"], expected["item"])
        if key not in found and not any(expected["item"] in item for _, item in found):
            missed.append(f"{expected['type']}: {expected['item']}")
    return missed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("drawing", help="basename of the drawing under SCHEME_GOLDEN_DIR")
    parser.add_argument("--model", action="append", default=[], metavar="STAGE=MODEL")
    args = parser.parse_args(argv)

    folder = Path(os.environ.get("SCHEME_GOLDEN_DIR", Path(__file__).parent))
    pdf = folder / f"{args.drawing}.pdf"
    truth_file = folder / f"{args.drawing}.truth.json"
    if not pdf.is_file() or not truth_file.is_file():
        print(f"Need both {pdf} and {truth_file}.", file=sys.stderr)
        return 2

    overrides = {"models": dict(pair.split("=", 1) for pair in args.model)} if args.model else None
    config = Config.from_env().with_overrides(overrides)
    truth = json.loads(truth_file.read_text(encoding="utf-8"))

    result = run_pipeline(pdf, config)

    print(f"\n{args.drawing} — {len(result.sheets)} sheets")
    print("  models: " + ", ".join(f"{s}={m.model}" for s, m in config.models.items()))
    print(f"  cost:   ${result.cost.get('total_usd', 0):.4f}\n")

    metrics = score(result, truth, pdf)
    print("metrics")
    for metric in metrics:
        print(metric.line())

    problems = compare_totals(result, truth)
    print("\nknown-good totals")
    print("  all reproduced" if not problems else "\n".join(f"  MISS {p}" for p in problems))

    missed = compare_findings(result, truth)
    print("\nreference findings")
    print("  all surfaced" if not missed else "\n".join(f"  MISSED {m}" for m in missed))

    failed = [
        m for m in metrics
        if m.score is not None and m.name in GATES and m.score < GATES[m.name]
    ]
    return 1 if (failed or problems or missed) else 0


if __name__ == "__main__":
    raise SystemExit(main())
