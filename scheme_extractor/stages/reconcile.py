"""Stage 5 — assert against the text layer, where there is one to assert against.

The brief's version of this stage reads every tag out of the PDF's own text
layer and treats an absence as a hallucination. That works when the text
layer carries the drawing. On this producer's exports it carries the sheet
frame and the title block and nothing else, so an unconditional version of
that check would flag all 523 devices and mean nothing by it.

So the check is coverage-aware. Where the page's text layer has tokens to
compare against, a mismatch is a real finding. Where it has none, the value
is marked unverifiable and carried through as such. Either way nothing
unverified reaches the BOM silently — the difference is that a reviewer can
now tell the two situations apart.
"""

from __future__ import annotations

import re

from ..models.schema import SheetExtraction
from .textlayer import PageTokens

# Tokens shaped like a device tag or a rating: what a text layer would carry
# if it carried the drawing at all.
DRAWING_TOKEN = re.compile(r"^(?:[A-Z]{1,4}[-.]?\d|[\d.]+[xX][\d.]+|\d+(?:\.\d+)?[AaVvkK])")


def page_has_drawing_text(tokens: PageTokens) -> bool:
    return sum(1 for t in tokens.tokens if DRAWING_TOKEN.match(t.text)) >= 5


PROTECTIVE_CLASSES = {"mcb", "mccb", "rcd", "motor_protection", "fuse"}


def reconcile(sheet: SheetExtraction, tokens: PageTokens, protective_devices: int | None = None) -> None:
    known = tokens.texts()
    verifiable = page_has_drawing_text(tokens)

    for device in sheet.devices:
        device.sheet_label = sheet.sheet.sheet_label
        for tag in device.tags_expanded or [device.tag]:
            if tag in known:
                continue
            device.flags.append("tag_not_in_text_layer" if verifiable else "tag_unverifiable")
        for field in ("rating", "model", "setting"):
            value = getattr(device, field)
            if not value:
                continue
            if not any(part in known for part in value.split()):
                device.flags.append(f"{field}_unverified" if verifiable else f"{field}_unverifiable")
        # Only a contradiction of present evidence makes a device need a human.
        # "The text layer does not carry this sheet" is a property of the file.
        if any(flag.endswith(("_not_in_text_layer", "_unverified")) for flag in device.flags):
            device.needs_human = True

    for row in sheet.circuit_table:
        row.sheet_label = sheet.sheet.sheet_label
        if row.terminal not in known:
            row.flags.append("terminal_not_in_text_layer" if verifiable else "terminal_unverifiable")
            if verifiable:
                row.needs_human = True

    for point in sheet.io_points:
        point.sheet_label = sheet.sheet.sheet_label

    # One destination column per FINAL protective device: the last one on
    # each line. A feeder breaker above a busbar, an RCD above a group of
    # MCBs, or the MCB above a circuit's own RCD feeds another device and has
    # no column — counting every device flagged nearly every sheet of
    # 4382.26-8, all of them read correctly.
    if protective_devices is None:
        protective_devices = final_protective_devices(sheet)
    columns = len({row.terminal for row in sheet.circuit_table})
    if (
        sheet.layout_kind == "table"
        and columns
        and protective_devices is not None
        and columns != protective_devices
    ):
        sheet.notes.append(
            f"Sheet {sheet.sheet.sheet_label}: {columns} destination columns against "
            f"{protective_devices} final protective devices — the table may be misread."
        )
        for row in sheet.circuit_table:
            if "column_count_mismatch" not in row.flags:
                row.flags.append("column_count_mismatch")


def final_protective_devices(sheet: SheetExtraction) -> int | None:
    """Protective devices that nothing else on the sheet is fed from.

    Tags are counted once: the table arrives in overlapping pieces, so the
    same breaker can be listed twice. Returns None when the reading carries
    no feed links at all — without them a feeder cannot be told from a final
    circuit, and a count would only raise a false alarm.
    """
    protective = [d for d in sheet.devices if d.device_class in PROTECTIVE_CLASSES]
    tags = {tag for d in protective for tag in (d.tags_expanded or [d.tag])}
    upstream = {d.fed_from.strip() for d in sheet.devices if d.fed_from} & tags
    if not upstream:
        return None
    return len(tags - upstream)


def unverified(sheet: SheetExtraction) -> list[str]:
    return [
        f"{device.tag}: {', '.join(device.flags)}"
        for device in sheet.devices
        if device.flags
    ]
