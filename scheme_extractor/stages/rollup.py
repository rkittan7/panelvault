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


def _norm(value: str | None) -> str | None:
    """Grouping key for a printed value: `2x40A`, `2X40A` and `2X 40A` agree."""
    if value is None:
        return None
    compact = re.sub(r"\s+", "", value).upper()
    # CAD text mixes hyphen, en dash and minus: `2.5-4A`, `2.5–4A`.
    compact = re.sub(r"[\u2010-\u2015\u2212]", "-", compact)
    return compact or None


def _poles(value: str | None) -> str | None:
    """`2`, `2P` and `2p` are the same pole count."""
    compact = _norm(value)
    return re.sub(r"P(?=$|\+)", "", compact) if compact else None


def _fold_unnamed(grouped: dict[tuple, BOMLine]) -> None:
    """Fold a line missing its maker or model into the one line it must be.

    One sheet printing `F202 ABB` beside an RCD and another reading only
    `2X40A` split the same part into two BOM lines, and only the named one
    matched the catalogue. Such a line joins a named line only when exactly
    one candidate of the same class, rating and poles exists, and it is
    flagged so the inference stays visible.
    """
    for key in sorted(grouped, key=lambda k: tuple(part or "" for part in k)):
        line = grouped.get(key)
        if line is None:
            continue
        device_class, maker, model, rating, poles = key
        if maker and model:
            continue
        candidates = [
            (other_key, other) for other_key, other in grouped.items()
            if other is not line
            and other_key[0] == device_class and other_key[3] == rating and other_key[4] == poles
            and other_key[2] and (not model or other_key[2] == model)
            and (not maker or other_key[1] == maker)
        ]
        if len(candidates) != 1 or not rating:
            continue
        target_key, target = candidates[0]
        target.qty += line.qty
        target.tags.extend(line.tags)
        for sheet_label, count in line.breakdown.items():
            target.breakdown[sheet_label] = target.breakdown.get(sheet_label, 0) + count
        for flag in [*line.flags, "model_inferred"]:
            if flag not in target.flags:
                target.flags.append(flag)
        target.needs_human = target.needs_human or line.needs_human
        del grouped[key]


PLACEHOLDER = re.compile(r"\.{2,}|…")


def _pole_count(poles: str | None, rating: str | None, device_class: str) -> str | None:
    """Poles as printed, else as the rating implies (`3X16A` is three).

    On these single-lines a breaker printed with a bare current (`16A C ABB`)
    is single-pole; a multi-pole one carries its count in the rating.
    """
    compact = _poles(poles)
    if compact:
        found = re.match(r"\d+", compact)
        return found.group() if found else compact
    rating = _norm(rating) or ""
    match = re.match(r"(\d)X", rating)
    if match:
        return match.group(1)
    if device_class == "mcb" and re.fullmatch(r"\d+(?:\.\d+)?A", rating):
        return "1"
    return None


def _item_poles(item) -> str | None:
    if _poles(item.poles):
        found = re.match(r"\d+", _poles(item.poles))
        return found.group() if found else None
    found = re.search(r"\((\d)\s*P\)", item.description_he or "", re.I)
    return found.group(1) if found else None


def _pattern_covers(pattern: str, tags: list[str]) -> bool:
    """`F...` names F361 and FU461; `IRL` does not name R211.

    Without this, the one relay row on 4382.26-8's parts sheet (GIC IRLA04S,
    pattern `IRL`) named every relay on the set, and a latching relay's row
    (`KSR..`) named two switches.
    """
    prefix = re.match(r"[A-Za-z]+", pattern.strip())
    if not prefix:
        return False
    return all(tag.upper().startswith(prefix.group().upper()) for tag in tags)


def _classes_from_equipment_list(sheets: list[SheetExtraction]) -> dict[str, str]:
    """model -> device class, where the parts list is unambiguous about it."""
    seen: dict[str, set[str]] = {}
    for sheet in sheets:
        for item in sheet.equipment_list:
            if item.model:
                seen.setdefault(_norm(item.model), set()).add(item.device_class)
    return {model: classes.pop() for model, classes in seen.items() if len(classes) == 1}


def _models_from_equipment_list(grouped: dict[tuple, BOMLine], items: list) -> None:
    """Name a model the single-lines leave out, from the set's own parts list.

    4382.26-8 prints `16A C ABB` beside ~150 breakers and names the model
    only on its parts sheet: S201M for single-pole, S203M for three-pole.
    A line takes a model only when exactly one listed family fits its class,
    maker and pole count, and it is flagged so a reviewer sees the source.
    """
    for line in grouped.values():
        if line.model:
            continue
        poles = _pole_count(line.poles, line.rating, line.device_class)
        fits = {
            (item.manufacturer, item.model)
            for item in items
            if item.model
            and item.device_class == line.device_class
            and _pattern_covers(item.tag_pattern, line.tags)
            and (not line.manufacturer or not item.manufacturer or _norm(item.manufacturer) == _norm(line.manufacturer))
            and (_item_poles(item) is None or poles is None or _item_poles(item) == poles)
            and (_item_poles(item) is not None or len([i for i in items if i.device_class == line.device_class and i.model]) == 1)
        }
        if len(fits) != 1:
            continue
        maker, model = fits.pop()
        line.model = model
        line.manufacturer = line.manufacturer or maker
        if "model_from_equipment_list" not in line.flags:
            line.flags.append("model_from_equipment_list")


def _key(device) -> tuple:
    return (
        device.device_class,
        _norm(device.manufacturer),
        _norm(device.model),
        _norm(device.rating),
        _poles(device.poles),
    )


def _compatible(a: tuple, b: tuple) -> bool:
    """Same class, and no field where both say something different."""
    return a[0] == b[0] and all(x is None or y is None or x == y for x, y in zip(a[1:], b[1:]))


def _detail(key: tuple) -> int:
    return sum(1 for part in key[1:] if part)


def build_bom(sheets: list[SheetExtraction]) -> list[BOMLine]:
    """One unit per tag across the whole set.

    A tag names one device in a drawing set, and the same breaker is often
    drawn twice — on an overview sheet and again on its own. Counted once per
    sheet, 4382.26-8 listed QU1, QU4, the SPDs and every contactor twice. The
    most detailed compatible drawing of a tag is the one counted; a tag drawn
    with contradicting specs stays as separate units, flagged `duplicate_tag`,
    because that disagreement is the finding.
    """
    occurrences: dict[str, list[tuple[str, object, tuple]]] = {}
    for sheet in sheets:
        label = sheet.sheet.sheet_label
        for device in sheet.devices:
            for tag in device.tags_expanded or expand_range(device.tag):
                if PLACEHOLDER.search(tag):
                    # `F...`, `Q..`: a family from a parts list, not a device.
                    continue
                occurrences.setdefault(tag, []).append((label, device, _key(device)))

    # An MS116 is motor protection wherever it is drawn; one sheet filing it
    # as an MCCB split it off its own line. The parts list settles the class.
    listed_class = _classes_from_equipment_list(sheets)
    for tag, seen in occurrences.items():
        for index, (label, device, key) in enumerate(seen):
            corrected = listed_class.get(key[2]) if key[2] else None
            if corrected and corrected != device.device_class:
                device = device.model_copy(update={"device_class": corrected})
                seen[index] = (label, device, _key(device))

    grouped: dict[tuple, BOMLine] = {}
    curves: dict[tuple, set[str]] = {}
    for tag, seen in occurrences.items():
        chosen: list[list] = []  # [label, device, key]
        for label, device, key in seen:
            match = next((c for c in chosen if _compatible(c[2], key)), None)
            if match is None:
                chosen.append([label, device, key])
            elif _detail(key) > _detail(match[2]):
                match[:] = [label, device, key]
        for label, device, key in chosen:
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
            line.qty += 1
            line.tags.append(tag)
            line.breakdown[label] = line.breakdown.get(label, 0) + 1
            curves.setdefault(key, set()).add(device.curve or "")
            flags = [*device.flags, *(["duplicate_tag"] if len(chosen) > 1 else [])]
            for flag in flags:
                if flag not in line.flags:
                    line.flags.append(flag)
            line.needs_human = line.needs_human or device.needs_human or len(chosen) > 1

    for key, line in grouped.items():
        seen = {value for value in curves.get(key, set()) if value}
        line.curve = seen.pop() if len(seen) == 1 else None

    _fold_unnamed(grouped)
    _models_from_equipment_list(grouped, [item for sheet in sheets for item in sheet.equipment_list])

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
