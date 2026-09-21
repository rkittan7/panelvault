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


def _component(line: BOMLine, board_number: str) -> dict[str, Any]:
    raw = " ".join(
        part for part in (line.manufacturer, line.model, line.rating, line.poles, line.curve) if part
    )
    return {
        "rawText": raw,
        "manufacturer": line.manufacturer or "",
        "model": line.model or "",
        "type": PANELVAULT_TYPE.get(line.device_class, line.device_class),
        "rating": line.rating or "",
        "poles": line.poles or "",
        "curve": line.curve or "",
        "sensitivity": line.sensitivity or "",
        "quantity": line.qty,
        "reference": ", ".join(line.tags[:60]),
        "sourcePage": 0,
        "boardNumber": board_number,
        "supplyRole": "board_main" if line.device_class == "mccb" and line.qty == 1 else "downstream",
        "isMainBreaker": False,
        # Not in the old contract, and deliberately added: a reviewer must be
        # able to see which lines nobody has verified.
        "flags": line.flags,
        "needsHuman": line.needs_human,
        "breakdown": line.breakdown,
    }


def board_draft(run: ExtractionRun) -> dict[str, Any]:
    facts = {fact.field.lower(): (fact.value or "") for fact in run.audit.panel}
    number = facts.get("drawing_no") or facts.get("drawing number") or ""
    return {
        "board": {
            "number": number,
            "name": facts.get("panel", ""),
            "customer": facts.get("client", ""),
            "project": facts.get("project", ""),
            "type": facts.get("type", ""),
            "typeConfidence": "low",
            "typeEvidence": "",
            "manufacturer": facts.get("panel_builder", ""),
            "mainBreakerType": facts.get("main_breaker_type", ""),
            "mainBreakerModel": facts.get("main_breaker_model", ""),
            "mainBreakerAmpere": facts.get("main_breaker_rating", ""),
            "mainBreakerReference": facts.get("main_breaker_reference", ""),
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
        "components": [_component(line, number) for line in run.bom],
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
