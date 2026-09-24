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
    # `6A+N` is one protected pole beside a switched neutral: the breaker
    # ordered for it is the single-pole one the parts list names.
    if device_class == "mcb" and re.fullmatch(r"\d+(?:\.\d+)?A(?:\+N)?", rating):
        return "1"
    return None


def _item_poles(item) -> str | None:
    if _poles(item.poles):
        found = re.match(r"\d+", _poles(item.poles))
        return found.group() if found else None
    # The count is printed `(1P)`; the model files it under description or
    # rating as the mood takes it.
    text = " ".join(part for part in (item.description_he, item.rating, item.model) if part)
    found = re.search(r"\((\d)\s*P\)|\b(\d)\s*P\b", text, re.I)
    return (found.group(1) or found.group(2)) if found else None


def _amps(rating: str | None) -> str | None:
    """`3X250A` -> `250`."""
    found = re.search(r"(\d+(?:\.\d+)?)\s*A\b", (rating or "").upper())
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
        candidates = [
            item
            for item in items
            # `N.D.S`, `AF -`: a parts list's placeholder where no model was
            # chosen. Every real model number carries a digit.
            if item.model and re.search(r"\d", item.model)
            and item.device_class == line.device_class
            and _pattern_covers(item.tag_pattern, line.tags)
            and (not line.manufacturer or not item.manufacturer or _norm(item.manufacturer) == _norm(line.manufacturer))
            and (_item_poles(item) is None or poles is None or _item_poles(item) == poles)
        ]
        if not candidates:
            # The list names a family the single-lines never use (`KSR..` for
            # step relays the schematics tag `RC211`). A family pattern stands
            # for a whole kind of device, so with one of them listed for the
            # class there is nothing else the line can be. A row that names
            # one device (`IRL`, no dots) speaks only for that device.
            listed = [
                item for item in items
                if item.model and re.search(r"\d", item.model)
                and item.device_class == line.device_class and "." in (item.tag_pattern or "")
                and (not line.manufacturer or not item.manufacturer
                     or _norm(item.manufacturer) == _norm(line.manufacturer))
                and (_item_poles(item) is None or poles is None or _item_poles(item) == poles)
            ]
            if len({(item.manufacturer, item.model) for item in listed}) == 1:
                candidates = listed
        fits = {(item.manufacturer, item.model) for item in candidates}
        if len(fits) > 1:
            # Two MCCB families listed (`XT3N 250 36kA`, `XT1C 160 25kA`):
            # the one naming this line's current is the one it belongs to.
            amps = _amps(line.rating)
            fits = {
                (item.manufacturer, item.model) for item in candidates
                if amps and amps in re.findall(r"\d+(?:\.\d+)?", " ".join(
                    part for part in (item.model, item.rating, item.description_he) if part))
            }
        if len(fits) != 1:
            continue
        maker, model = fits.pop()
        line.model = model
        line.manufacturer = line.manufacturer or maker
        if "model_from_equipment_list" not in line.flags:
            line.flags.append("model_from_equipment_list")


TRIP_CURVE = re.compile(r"^[BCDKZ]$", re.I)


def _true_class(device):
    """A breaker printed with a trip curve (`3X40A C ABB`) is an MCB.

    Curves B/C/D belong to miniature breakers; sheets 28-29 of 4382.26-8
    read four identical `3X40A C` breakers as MCB, MCCB and fuse. Only a
    device with no model is corrected — a named model is trusted.
    """
    amps = re.search(r"(\d+(?:\.\d+)?)\s*A\b", (device.rating or "").upper())
    if (
        device.device_class in {"mccb", "fuse"}
        and not device.model
        and device.curve and TRIP_CURVE.match(device.curve.strip())
        and amps and float(amps.group(1)) <= 63
    ):
        return device.model_copy(update={"device_class": "mcb"})
    return device


def _key(device) -> tuple:
    return (
        device.device_class,
        _norm(device.manufacturer),
        _norm(device.model),
        _norm(device.rating),
        _poles(device.poles),
    )


def _bare(key: tuple) -> bool:
    """A mention without a spec: no model, no rating."""
    return not key[2] and not key[3]


def _compatible(a: tuple, b: tuple) -> bool:
    """No field where both say something different.

    The class must agree too, unless one of them is a bare mention: sheet 33
    of 4382.26-8 is a front-view layout that labels F02 an MCB where its
    single-line gives an MCCB 3X40A, and QC361 is a relay on one sheet and a
    contactor on another. Those are one device each.
    """
    if a[0] != b[0] and not (_bare(a) or _bare(b)):
        return False
    return all(x is None or y is None or x == y for x, y in zip(a[1:], b[1:]))


def _plc_identities(occurrences: dict[str, list]) -> None:
    """One name per PLC module, whatever each sheet called it.

    The drawing prints no tag on a PLC module, so each sheet's reading
    invented one — `PLC-AI8` on the rack sheet, `SLOT-4-TM3AI8` on its I/O
    sheet — and every module was counted twice. A module is its model and
    slot; a mention without a slot joins the model's only slotted module,
    or all mentions of a model become one module when none has a slot.
    Mentions are renamed one by one, because two different parts can share
    a raw tag (`SLOT1` for a module and the cable wired to it).
    """
    # Haiku wrote the slot into the model (`SLOT-4-TM3AI8`), or left the
    # model out and put it in the tag (`TM3DI16`, `SLOT-1TM3DI32K`).
    for tag, seen in occurrences.items():
        for index, (label, device, key) in enumerate(seen):
            if device.device_class in {"plc", "plc_module"} and not device.model:
                from_tag = re.sub(r"^(?:PLC\W*)?SLOT\W*\d+\W*", "", tag, flags=re.I)
                if re.search(r"[A-Z]{2}\d", from_tag.upper()):
                    device = device.model_copy(update={"model": from_tag})
                    seen[index] = (label, device, _key(device))
            if device.device_class in {"plc", "plc_module"} and device.model:
                bare_model = re.sub(r"^SLOT\W*\d+\W*", "", device.model, flags=re.I)
                if bare_model and bare_model != device.model:
                    device = device.model_copy(update={"model": bare_model})
                    seen[index] = (label, device, _key(device))
    entries = [
        (tag, index, key)
        for tag, seen in occurrences.items()
        for index, (_, device, key) in enumerate(seen)
        if device.device_class in {"plc", "plc_module"} and key[2]
    ]
    models = {key[2] for _, _, key in entries}
    # `TM3DQ16` on one sheet is the `TM3DQ16R` its I/O sheet names in full.
    fullest = {model: max((m for m in models if m.startswith(model)), key=len) for model in models}
    slots: dict[str, set[str]] = {}
    for tag, _, key in entries:
        found = re.search(r"SLOT\W*(\d+)", tag, re.I)
        if found:
            slots.setdefault(fullest[key[2]], set()).add(found.group(1))
    moves = []
    for tag, index, key in entries:
        model = fullest[key[2]]
        found = re.search(r"SLOT\W*(\d+)", tag, re.I)
        known = sorted(slots.get(model, ()))
        if found:
            name = f"{model} SLOT{found.group(1)}"
        elif len(known) == 1:
            name = f"{model} SLOT{known[0]}"
        elif not known:
            name = model
        else:
            continue
        moves.append((tag, index, name, model))
    for tag, index, name, model in sorted(moves, key=lambda m: -m[1]):
        label, device, _ = occurrences[tag].pop(index)
        device = device.model_copy(update={"model": model})
        occurrences.setdefault(name, []).append((label, device, _key(device)))
    for tag in [tag for tag, seen in occurrences.items() if not seen]:
        occurrences.pop(tag)


def _detail(key: tuple) -> int:
    return sum(1 for part in key[1:] if part)


def _abbreviates(tag: str, others: set[str]) -> bool:
    """The same device under a shorter or longer number: `QU97` on the door
    for `QU497`, or `FU410.2` on the door for the single-line's `FU10.2`."""
    found = re.fullmatch(r"([A-Z]+)(\d[\d.]*)", tag)
    if not found:
        return False
    letters, number = found.groups()
    for other in others:
        match = re.fullmatch(r"([A-Z]+)(\d[\d.]*)", other)
        if not match or match.group(1) != letters or match.group(2) == number:
            continue
        short, long = sorted((number, match.group(2)), key=len)
        if len(short) >= 2 and long.endswith(short):     # F1 is not short for F11
            return True
    return False


def build_bom(sheets: list[SheetExtraction], *, exact_text: bool = False) -> list[BOMLine]:
    """One unit per tag across the whole set.

    A tag names one device in a drawing set, and the same breaker is often
    drawn twice — on an overview sheet and again on its own. Counted once per
    sheet, 4382.26-8 listed QU1, QU4, the SPDs and every contactor twice. The
    most detailed compatible drawing of a tag is the one counted; a tag drawn
    with contradicting specs stays as separate units, flagged `duplicate_tag`,
    because that disagreement is the finding.
    """
    occurrences: dict[str, list[tuple[str, object, tuple]]] = {}
    from_bare_range: set[str] = set()
    drawn: set[str] = set()
    for sheet in sheets:
        label = sheet.sheet.sheet_label
        for device in sheet.devices:
            device = _true_class(device)
            tags = device.tags_expanded or expand_range(device.tag)
            for tag in tags:
                if PLACEHOLDER.search(tag):
                    # `F...`, `Q..`: a family from a parts list, not a device.
                    continue
                if len(tags) > 1 and _bare(_key(device)):
                    from_bare_range.add(tag)
                else:
                    drawn.add(tag)
                occurrences.setdefault(tag, []).append((label, device, _key(device)))
    # A layout sheet labels a run of breakers `F361——F381`. Expanded, that
    # names every number between, including ones no single-line draws
    # (F370-F380 on 4382.26-8). A tag known only from such a range is not
    # a device.
    for tag in from_bare_range - drawn:
        occurrences.pop(tag, None)
    # A cabinet layout labels every device without a spec (sheet 34 of
    # 4382.26-8: 59 labels, all bare) and its small print is where QU1 was
    # read as QU11. A tag seen only as a bare label on such a sheet is not
    # counted; one also drawn elsewhere keeps that drawing. Text read from a
    # CAD file is not misread, so there a cabinet's label is a device (SH211
    # drawn only as strokes on its single-line) unless it is a short form of
    # a drawn tag: QU97 on the cabinet door is QU497.
    layout_sheets = set()
    for sheet in sheets:
        keys = [_key(d) for d in sheet.devices]
        if len(keys) >= 25 and sum(1 for k in keys if _bare(k)) >= 0.75 * len(keys):
            layout_sheets.add(sheet.sheet.sheet_label)
    layout_only = [tag for tag, seen in occurrences.items()
                   if all(_bare(key) and label in layout_sheets for label, _, key in seen)]
    for tag in layout_only:
        if not exact_text or _abbreviates(tag, set(occurrences) - set(layout_only)):
            occurrences.pop(tag)
    # `SLOT1`, `DI6` in a control schematic point at a PLC input; with no
    # model they name a slot or channel, not a module.
    for tag in list(occurrences):
        if re.fullmatch(r"(?:SLOT\W*\d+|[DA][IQO]\d+)", tag, re.I):
            occurrences[tag] = [
                entry for entry in occurrences[tag]
                if not (entry[1].device_class in {"plc", "plc_module"} and not entry[2][2])
            ]
            if not occurrences[tag]:
                occurrences.pop(tag)
    # `AF38 ABB` printed beside contactor QC190 was read as a device tagged
    # AF38. A "tag" that is some device's model, with no model of its own,
    # is that label, not a device.
    known_models = {key[2] for seen in occurrences.values() for _, _, key in seen if key[2]}
    for tag in list(occurrences):
        if _norm(tag) in known_models and all(not key[2] for _, _, key in occurrences[tag]):
            occurrences.pop(tag)
    for tag in list(occurrences):
        # `SHE/1`, `SHE/2`: the lugs of switch SHE, not devices of their own.
        base = re.match(r"^(.+)/\d+$", tag)
        if base and base.group(1) in occurrences:
            occurrences.pop(tag)
            continue
        # `QO` on a layout sheet is `Q0` misread: the letter for the digit.
        zeroed = re.sub(r"O(?=\d|$)", "0", tag)
        if zeroed != tag and zeroed in occurrences and all(_bare(key) for _, _, key in occurrences[tag]):
            occurrences.pop(tag)

    _plc_identities(occurrences)

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
            elif _bare(match[2]) and not _bare(key) or _detail(key) > _detail(match[2]):
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


# What a circuit's cable needs to land on. Klemsan's rail terminals are named
# by the largest conductor they take, and this shop fits nothing below AVK 4,
# so a 2.5mm cable lands on an AVK 4 and a 6mm one on an AVK 6.
AVK_SIZES = (4, 6, 10, 16, 35, 50, 70, 95, 120, 150, 185, 240)
CABLE = re.compile(r"^(\d+)\s*[xX*×]\s*(\d+(?:[.,]\d+)?)")


def terminal_blocks(circuits: list[CircuitRow]) -> list[BOMLine]:
    """One rail terminal per conductor of every circuit's cable.

    The cable is the only place a drawing says what lands on the rail, and
    it says it exactly: `3x2.5N2XY` is three cores of 2.5mm. The terminals
    are not printed as parts, so every line is flagged as worked out here.
    """
    per_size: dict[int, list[CircuitRow]] = {}
    for row in circuits:
        found = CABLE.match((row.cable or "").strip())
        if not found:
            continue
        cores = int(found.group(1))
        area = float(found.group(2).replace(",", "."))
        size = next((s for s in AVK_SIZES if s >= area), None)
        if size is None or cores > 12:
            continue
        per_size.setdefault(size, []).extend([row] * cores)
    lines = []
    for size, rows in sorted(per_size.items()):
        breakdown: dict[str, int] = {}
        for row in rows:
            label = row.sheet_label or ""
            breakdown[label] = breakdown.get(label, 0) + 1
        lines.append(BOMLine(
            device_class="terminal", manufacturer="Klemsan", model=f"AVK {size}",
            qty=len(rows), tags=sorted({r.terminal for r in rows if r.terminal}),
            breakdown=breakdown, flags=["from_cable_sizes"],
        ))
    return lines


def cabinet_lines(widths: list[int], height: int | None, depth: int | None,
                  manufacturer: str | None, series: str | None, sheet: str = "") -> list[BOMLine]:
    """One line per cabinet size, as the enclosure is ordered.

    A board is bought cabinet by cabinet, and the front elevation dimensions
    each one: 4382.26-1 is 500+600+600+800+800+600 at 1950 high and 500 deep.
    Same size, same line.
    """
    lines = []
    for width in sorted(set(widths)):
        size = "x".join(str(part) for part in (height, width, depth) if part)
        lines.append(BOMLine(
            device_class="enclosure", manufacturer=manufacturer or None,
            model=" ".join(part for part in (series, size) if part) or None,
            rating=f"{size}mm" if size else None,
            qty=sum(1 for w in widths if w == width),
            tags=[], breakdown={sheet: sum(1 for w in widths if w == width)} if sheet else {},
            flags=["from_elevation"],
        ))
    return lines


LOCK_NOTE = "נעילה"           # `עם נעילה`: with a lock
# ABB's padlock device for the S200 family, which clamps the toggle so the
# breaker cannot be switched until the padlock is taken off.
LOCK_PART = ("ABB", "S2C-PD-S200")


def lock_accessories(sheets: list[SheetExtraction], notes: dict[str, int]) -> list[BOMLine]:
    """A lock for every breaker the drawing marks `עם נעילה`.

    The note is the order: the breaker itself is the same one as its
    neighbours. Counted from the notes rather than from the devices that
    carry them, because a note belongs to its breaker even where the label
    beside it could not be read.
    """
    total = sum(notes.values())
    if not total:
        return []
    locked = [d for sheet in sheets for d in sheet.devices
              if d.description_he and LOCK_NOTE in d.description_he]
    makers = {d.manufacturer for d in locked if d.manufacturer}
    maker, model = LOCK_PART if makers <= {"ABB"} else (None, None)
    return [BOMLine(
        device_class="accessory", manufacturer=maker, model=model,
        qty=total, tags=sorted({d.tag for d in locked}),
        breakdown={label: count for label, count in notes.items()}, flags=["from_note"],
    )]


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
