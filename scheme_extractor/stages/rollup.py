"""Stage 6 — the arithmetic, in code.

No model adds up 119 breakers. A model that does it is a model that can be
quietly wrong by one, and nothing downstream would catch it.
"""

from __future__ import annotations

import re

from ..models.schema import SPARE_WORDS, BOMLine, CircuitCounts, CircuitRow, SheetExtraction

# `F201-F209`, `FU410.1-.3`, `X11–X14` (en dash included — CAD text uses both).
RANGE = re.compile(r"^(?P<prefix>[A-Za-z]+)(?P<start>\d+(?:\.\d+)?)\s*[-–]\s*(?P<end>[A-Za-z]*\.?\d+(?:\.\d+)?)$")


def expand_range(label: str) -> list[str]:
    """Turn `F201-F209` into nine explicit tags, or return the label as-is.

    Only whole-number series expand. A dotted series (`FU410.1-.3`) expands on
    its last component. Anything that does not parse cleanly is returned
    untouched, because a tag invented by a regex is worse than one left alone.
    """
    match = RANGE.match(label.strip())
    if not match:
        return [label.strip()]
    prefix, start, end = match.group("prefix"), match.group("start"), match.group("end")
    end = end.lstrip(prefix).lstrip(".")

    if "." in start:
        stem, _, first = start.rpartition(".")
        last = end.rpartition(".")[2]
        if first.isdigit() and last.isdigit() and int(last) >= int(first):
            return [f"{prefix}{stem}.{n}" for n in range(int(first), int(last) + 1)]
        return [label.strip()]
    if start.isdigit() and end.isdigit() and int(end) >= int(start):
        width = len(start)
        return [f"{prefix}{str(n).zfill(width)}" for n in range(int(start), int(end) + 1)]
    return [label.strip()]


def device_units(sheet: SheetExtraction) -> list[tuple[str, str]]:
    """Every physical device on this sheet as (tag, sheet_label), deduplicated.

    Deduplication is on `(tag, sheet)` and never on tag alone. The same tag
    used for two different devices on two sheets is a finding for stage 7 to
    report, not two rows for this stage to quietly merge into one.
    """
    label = sheet.sheet.sheet_label
    seen: set[tuple[str, str]] = set()
    units: list[tuple[str, str]] = []
    for device in sheet.devices:
        tags = device.tags_expanded or expand_range(device.tag)
        for tag in tags:
            key = (tag, label)
            if key in seen:
                continue
            seen.add(key)
            units.append(key)
    return units


def build_bom(sheets: list[SheetExtraction]) -> list[BOMLine]:
    grouped: dict[tuple, BOMLine] = {}
    curves: dict[tuple, set[str]] = {}
    for sheet in sheets:
        label = sheet.sheet.sheet_label
        seen_on_sheet: set[str] = set()
        for device in sheet.devices:
            key = (device.device_class, device.manufacturer, device.model, device.rating, device.poles)
            line = grouped.get(key)
            if line is None:
                line = BOMLine(
                    device_class=device.device_class,
                    manufacturer=device.manufacturer,
                    model=device.model,
                    rating=device.rating,
                    poles=device.poles,
                    qty=0,
                )
                grouped[key] = line
            for tag in device.tags_expanded or expand_range(device.tag):
                if tag in seen_on_sheet:
                    continue
                seen_on_sheet.add(tag)
                line.qty += 1
                line.tags.append(tag)
                line.breakdown[label] = line.breakdown.get(label, 0) + 1
            curves.setdefault(key, set()).add(device.curve or "")
            for flag in device.flags:
                if flag not in line.flags:
                    line.flags.append(flag)
            line.needs_human = line.needs_human or device.needs_human

    for key, line in grouped.items():
        seen = {value for value in curves.get(key, set()) if value}
        line.curve = seen.pop() if len(seen) == 1 else None

    lines = sorted(
        grouped.values(),
        key=lambda l: (l.device_class, l.manufacturer or "", l.model or "", l.rating or "", l.poles or ""),
    )
    for line in lines:
        # §11.6: the per-sheet breakdown must sum to the line's quantity, or
        # the line is not auditable and the run should not claim it is.
        assert sum(line.breakdown.values()) == line.qty, f"{line.model}: breakdown does not sum to qty"
    return lines


def flatten_circuits(sheets: list[SheetExtraction]) -> tuple[list[CircuitRow], CircuitCounts]:
    """One row per terminal, with merged spans expanded.

    A span of four terminals sharing one destination becomes four rows that
    each carry that destination and the span they came from — so the schedule
    can be read per circuit without losing the fact that they were drawn as
    one cell.
    """
    rows: dict[tuple[str, str], CircuitRow] = {}
    for sheet in sheets:
        label = sheet.sheet.sheet_label
        for row in sheet.circuit_table:
            terminals = row.span_terminals or [row.terminal]
            for terminal in terminals:
                key = (label, terminal)
                if key in rows and terminal != row.terminal:
                    continue  # a row addressed to itself wins over a span member
                copy = row.model_copy(deep=True)
                copy.terminal = terminal
                copy.sheet_label = label
                rows[key] = copy

    ordered = [rows[key] for key in sorted(rows)]
    counts = CircuitCounts(
        total=len(ordered),
        # Spare means the word was printed. Nothing else counts (§2.4).
        spare=sum(1 for r in ordered if any(w in (r.destination_he or "") for w in SPARE_WORDS)),
        unlabelled=sum(
            1 for r in ordered
            if not (r.destination_he or "").strip()
            and not any(w in (r.destination_he or "") for w in SPARE_WORDS)
        ),
    )
    return ordered, counts
