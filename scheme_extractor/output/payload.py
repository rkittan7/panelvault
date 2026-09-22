"""The JSON PanelVault stores, and the board draft its phone already decodes.

Two shapes come out of a run. `run` is the full audited record — sheets,
BOM with per-sheet breakdown, circuit schedule, findings, cost. `board_draft`
is the same information reduced to the contract `POST /api/ai/board-scheme`
already returns, so the existing review screen can show this pipeline's
output without the app changing first.
"""

from __future__ import annotations

from typing import Any

from ..models.schema import BOMLine, ExtractionRun

# PanelVault's own device vocabulary, which is what the catalogue matches on.
PANELVAULT_TYPE = {
    "mccb": "MCCB",
    "mcb": "MCB",
    "rcd": "RCD",
    "contactor": "Contactor",
    "motor_protection": "Motor Protection",
    "switch": "Switch",
    "fuse": "Fuse",
    "spd": "Surge Protection",
    "lamp": "Pilot Light",
    "relay": "Relay",
    "step_relay": "Step Relay",
    "shunt_trip": "Shunt Trip",
    "plc": "PLC",
    "plc_module": "PLC Module",
    "psu": "Power Supply",
    "terminal": "Terminal",
    "alarm_interface": "Alarm Interface",
    "enclosure": "Enclosure",
    "label": "Label",
    "external": "External",
}


# Drawing furniture, not parts: a destination terminal (`XU497`) is a place a
# cable lands, and matching it against the catalogue only filled the review
# list with "Terminal ×39". They stay in the workbook's BOM.
NOT_PARTS = {"terminal", "label", "external"}


def _component(line: BOMLine, board_number: str, main_tag: str) -> dict[str, Any]:
    kind = PANELVAULT_TYPE.get(line.device_class, line.device_class)
    poles = f"{line.poles}P" if line.poles and line.poles.isdigit() else line.poles
    # Name the line by what it is before what it is rated: "MCB 3X40A 3P C",
    # not "3X40A 3", which gave the reviewer and the matcher nothing to go on.
    raw = " ".join(
        part for part in (line.manufacturer, line.model, kind, line.rating, poles, line.curve) if part
    )
    is_main = bool(main_tag) and main_tag in line.tags
    return {
        "rawText": raw,
        "description": raw,
        "manufacturer": line.manufacturer or "",
        "model": line.model or "",
        "type": kind,
        "rating": line.rating or "",
        "poles": line.poles or "",
        "curve": line.curve or "",
        "sensitivity": line.sensitivity or "",
        "quantity": line.qty,
        "reference": ", ".join(line.tags[:60]),
        "sourcePage": 0,
        "boardNumber": board_number,
        # Only the audited incomer is the board main. Marking every single
        # MCCB `board_main` made the site stamp the main breaker's rating
        # onto all of them.
        "supplyRole": "board_main" if is_main and line.qty == 1 else "downstream",
        "isMainBreaker": is_main and line.qty == 1,
        # Not in the old contract, and deliberately added: a reviewer must be
        # able to see which lines nobody has verified.
        "flags": line.flags,
        "needsHuman": line.needs_human,
        "breakdown": line.breakdown,
    }


def _title_block(run: ExtractionRun) -> dict[str, str]:
    """The title block as read at native resolution in stage 3.

    Every sheet repeats it and one sheet (the first) is sent with its crop,
    so the most complete reading wins, field by field.
    """
    fields: dict[str, str] = {}
    for sheet in sorted(run.sheets, key=lambda s: s.sheet.page_number):
        block = sheet.sheet.title_block
        for name in ("project", "panel", "panel_builder", "client", "consultant", "drawing_no"):
            value = (getattr(block, name) or "").strip()
            if value and name not in fields:
                fields[name] = value
    return fields


# Rows of the switchboard data table (ת"י 61439) by the words that label
# them, in the order they are tried. The table is printed the same way by
# every Israeli producer; its labels, not their position, identify a row.
BOARD_DATA = {
    "enclosure_manufacturer": ("יצרן מקורי", "ייצרן מקורי", "מקורי", "יצרן"),
    "ip_rating": ("דרגת הגנה", "IP"),
    "form_separation": ("מידור", "FORM"),
    "enclosure_size": ("מידה כללית", "מידות"),
    "rated_current": ("זרם הלוח", "InA"),
    "earthing_system": ("שיטת הארקה",),
    "supply_voltage": ("מתח רשת", "Un"),
    "frequency": ("תדר", "fn"),
}


def _board_data(run: ExtractionRun) -> dict[str, str]:
    found: dict[str, str] = {}
    rows = [row for sheet in run.sheets for row in sheet.board_data]
    for field, labels in BOARD_DATA.items():
        for label in labels:
            row = next(
                (r for r in rows if label in r.label_he or (r.symbol or "").strip() == label),
                None,
            )
            if row and row.value.strip():
                found[field] = row.value.strip()
                break
    return found


def board_draft(run: ExtractionRun) -> dict[str, Any]:
    facts: dict[str, str] = {}
    for fact in run.audit.panel:
        if fact.value and fact.field not in facts:
            facts[fact.field] = fact.value.strip()
    title = _title_block(run)
    # The data table is read directly; the audit's copy only fills gaps.
    for field, value in _board_data(run).items():
        facts[field] = value

    def pick(title_key: str | None, fact_key: str) -> str:
        return (title.get(title_key) if title_key else None) or facts.get(fact_key, "")

    number = pick("drawing_no", "drawing_no")
    main_tag = facts.get("main_breaker_reference", "")
    main_line = next((line for line in run.bom if main_tag and main_tag in line.tags), None)
    enclosure = facts.get("enclosure_manufacturer", "")
    components = [
        _component(line, number, main_tag) for line in run.bom if line.device_class not in NOT_PARTS
    ]
    return {
        "board": {
            "number": number,
            "name": pick("panel", "board_name"),
            "customer": pick("client", "client"),
            "project": pick("project", "project"),
            "type": facts.get("board_type", ""),
            "typeConfidence": "low",
            "typeEvidence": "",
            # The site's "board manufacturer" is who made the enclosure (the
            # data table's יצרן מקורי), not the panel builder in the title
            # block — the role tells it so.
            "manufacturer": enclosure,
            "manufacturerRole": "enclosure" if enclosure else None,
            "panelBuilder": pick("panel_builder", "panel_builder"),
            "mainBreakerType": facts.get("main_breaker_type", "")
                or (PANELVAULT_TYPE.get(main_line.device_class, "") if main_line else ""),
            "mainBreakerModel": facts.get("main_breaker_model", "") or (main_line.model or "" if main_line else ""),
            "mainBreakerAmpere": facts.get("main_breaker_rating", "") or (main_line.rating or "" if main_line else ""),
            "mainBreakerReference": main_tag,
            "mainBreakerEvidence": "",
            "cabinetCount": 1,
            "jobNumber": facts.get("job_number", ""),
            "revision": facts.get("revision", ""),
            "supplyVoltage": facts.get("supply_voltage", ""),
            "frequency": facts.get("frequency", ""),
            "earthingSystem": facts.get("earthing_system", ""),
            "ipRating": facts.get("ip_rating", ""),
            "formSeparation": facts.get("form_separation", ""),
            "enclosureSize": facts.get("enclosure_size", ""),
            "standards": [],
            "notes": "",
        },
        "components": components,
        "unmatched": [],
        "warnings": run.warnings[:20],
    }


def payload(run: ExtractionRun) -> dict[str, Any]:
    return {
        "job_id": run.job_id,
        "source_hash": run.source_hash,
        "counts": run.counts.model_dump(),
        "bom": [line.model_dump(mode="json") for line in run.bom],
        "circuits": [row.model_dump(mode="json") for row in run.circuits],
        "sheets": [sheet.model_dump(mode="json") for sheet in run.sheets],
        "audit": run.audit.model_dump(mode="json"),
        "cost": run.cost,
        "warnings": run.warnings,
        "notes": run.notes,
        "board_draft": board_draft(run),
    }
