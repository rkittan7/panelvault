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


def build_call(sheets: list[SheetExtraction]) -> Call:
    payload = [
        sheet.model_dump(mode="json", exclude=DROP_FIELDS, exclude_none=True)
        for sheet in sheets
    ]
    return Call(
        key="audit",
        system=(PROMPTS / "prompt_c.md").read_text(encoding="utf-8"),
        content=[text_block(json.dumps(payload, ensure_ascii=False))],
        tool_name="audit_result",
        schema=tool_schema(AuditResult),
    )


def run(client: LLMClient, sheets: list[SheetExtraction]) -> tuple[AuditResult, str]:
    try:
        payload, _ = client.complete("audit", build_call(sheets))
        return AuditResult.model_validate(payload), ""
    except Exception as error:  # noqa: BLE001 — a failed audit must not lose the extraction
        return AuditResult(), f"Cross-sheet audit failed: {error}"
