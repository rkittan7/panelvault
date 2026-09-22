"""Stage 7 — one call over the whole reconciled set.

Stage 6 has already done the rollup in code, so this prompt asks for the two
things code cannot produce: the findings, and a consolidated panel record.
Leaving the BOM out is not only cheaper — it removes the temptation for the
model to re-derive numbers that are already known to be right.
"""

from __future__ import annotations

import json
from pathlib import Path

from ..models.client import Call, LLMClient, text_block
from ..models.schema import AuditResult, SheetExtraction, tool_schema

PROMPTS = Path(__file__).resolve().parent.parent / "prompts"

# The audit reasons over structure, not over crops. Trimming the per-sheet
# bookkeeping keeps one call comfortably inside the context window on a set
# several times the size of the reference one.
DROP_FIELDS = {"needs_zoom_regions", "zoom_passes", "notes"}


# Rows as `a|b|c` under one header per table: the same facts as JSON at
# about half the tokens, since JSON repeats every key on every row.
DEVICE_COLUMNS = ("tag", "device_class", "manufacturer", "model", "rating", "poles", "setting",
                  "curve", "fed_from", "description_he")
ROW_COLUMNS = ("terminal", "protective_device", "destination_he", "cable", "inc", "is_spare")
IO_COLUMNS = ("module", "point", "type", "description_he")


def _rows(items: list, columns: tuple[str, ...]) -> list[str]:
    lines = []
    for item in items:
        values = []
        for column in columns:
            value = getattr(item, column, None)
            if column == "tag" and getattr(item, "tags_expanded", None):
                value = f"{value} ({', '.join(item.tags_expanded)})"
            values.append("" if value in (None, False) else str(value).replace("|", "/"))
        lines.append("|".join(values).rstrip("|"))
    return lines


def compact(sheet: SheetExtraction) -> str:
    parts = [f"## Sheet {sheet.sheet.sheet_label} ({sheet.layout_kind})"]
    if sheet.devices:
        parts += ["devices: " + "|".join(DEVICE_COLUMNS), *_rows(sheet.devices, DEVICE_COLUMNS)]
    if sheet.circuit_table:
        parts += ["circuits: " + "|".join(ROW_COLUMNS), *_rows(sheet.circuit_table, ROW_COLUMNS)]
    if sheet.io_points:
        parts += ["io: " + "|".join(IO_COLUMNS), *_rows(sheet.io_points, IO_COLUMNS)]
    rest = sheet.model_dump(
        mode="json", exclude_none=True,
        include={"busbars", "cross_references", "gaps", "anomalies", "equipment_list", "board_data"},
    )
    rest = {key: value for key, value in rest.items() if value}
    if rest:
        parts.append(json.dumps(rest, ensure_ascii=False))
    return "\n".join(parts)


def build_call(sheets: list[SheetExtraction]) -> Call:
    title = next((s.sheet.title_block for s in sheets if s.sheet.title_block.drawing_no), None)
    header = f"title block: {title.model_dump_json(exclude_none=True)}\n\n" if title else ""
    return Call(
        key="audit",
        system=(PROMPTS / "prompt_c.md").read_text(encoding="utf-8"),
        content=[text_block(header + "\n\n".join(compact(sheet) for sheet in sheets))],
        tool_name="audit_result",
        schema=tool_schema(AuditResult),
    )


def run(client: LLMClient, sheets: list[SheetExtraction]) -> tuple[AuditResult, str]:
    try:
        payload, _ = client.complete("audit", build_call(sheets))
        return AuditResult.model_validate(payload), ""
    except Exception as error:  # noqa: BLE001 — a failed audit must not lose the extraction
        return AuditResult(), f"Cross-sheet audit failed: {error}"
