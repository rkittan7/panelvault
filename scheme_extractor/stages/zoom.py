"""Stage 4 — go back at 600 DPI and settle the spans.

Not optional. On the reference set this pass corrected two merged spans that
the first pass read wrongly — `X11–X14` read as X11–X13 plus a spare, and
`X21–X22` read as X21–X23. Both would have shipped as silent data errors,
and neither would have tripped any check further down.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from pydantic import ValidationError

from ..config import Config
from ..models.client import Call, LLMClient, image_block, text_block
from ..models.schema import SPARE_WORDS, CircuitRow, SheetExtraction, ZoomResult, tool_schema
from .render import PageRegions, zoom_crop

PROMPTS = Path(__file__).resolve().parent.parent / "prompts"


@dataclass
class ZoomTarget:
    page: int
    tag: str
    reason: str
    bbox_pct: tuple[float, float, float, float]
    terminals: list[str]


def targets_for(sheet: SheetExtraction, regions: PageRegions) -> list[ZoomTarget]:
    """Everywhere the first pass admitted, or implied, that it was unsure."""
    band = regions.regions.get("table_band")
    table_bbox = band.bbox_pct if band else (0.0, 0.6, 1.0, 1.0)
    found: list[ZoomTarget] = []

    for index, region in enumerate(sheet.needs_zoom_regions):
        found.append(
            ZoomTarget(
                sheet.sheet.page_number,
                f"region{index}",
                region.reason,
                tuple(region.bbox_pct),  # type: ignore[arg-type]
                list(region.terminals),
            )
        )

    # Rows the model flagged, or left below `high` confidence, that no emitted
    # region already covers.
    covered = {t for target in found for t in target.terminals}
    loose = [
        row for row in sheet.circuit_table
        if (row.needs_zoom or row.span_confidence != "high") and row.terminal not in covered
    ]
    if loose:
        found.append(
            ZoomTarget(
                sheet.sheet.page_number,
                "table",
                "row-level uncertainty without an explicit region",
                tuple(table_bbox),  # type: ignore[arg-type]
                [row.terminal for row in loose],
            )
        )
    return found


def build_call(target: ZoomTarget, chunks: list[Path]) -> Call:
    system = (PROMPTS / "prompt_b.md").read_text(encoding="utf-8")
    overlap_note = (
        "The crop arrives in several overlapping pieces, left to right; the shared strip "
        "exists so a merged cell is never cut without context. Treat them as one table."
        if len(chunks) > 1
        else "The crop arrives as a single image."
    )
    system = system.replace("{{REGION_GUIDANCE}}", overlap_note)
    content: list[dict] = [
        text_block(
            f"reason: {target.reason}\n"
            f"terminal columns believed to lie in this crop: {', '.join(target.terminals) or 'unknown'}"
        )
    ]
    content.extend(image_block(chunk) for chunk in chunks)
    return Call(
        key=f"zoom-{target.page:03d}-{target.tag}",
        system=system,
        content=content,
        tool_name="zoom_result",
        schema=tool_schema(ZoomResult),
    )


def apply(sheet: SheetExtraction, result: ZoomResult) -> None:
    """Merge a resolved region back in, by terminal.

    `is_spare` is recomputed here in code rather than taken from the model:
    the destination text has just changed, and whether a circuit is spare is
    a property of whether שמור is printed in it — not a judgement call.
    """
    rows = {row.terminal: row for row in sheet.circuit_table}

    for cell in result.cells:
        for terminal in cell.span_terminals:
            row = rows.get(terminal)
            if row is None:
                row = CircuitRow(terminal=terminal, sheet_label=sheet.sheet.sheet_label)
                sheet.circuit_table.append(row)
                rows[terminal] = row
            row.destination_he = cell.destination_he
            row.span_terminals = list(cell.span_terminals)
            row.span_confidence = cell.confidence
            row.is_spare = any(word in (cell.destination_he or "") for word in SPARE_WORDS)
            row.needs_zoom = False

    for terminal, cable in result.cable_row.items():
        if row := rows.get(terminal):
            row.cable = cable
    for terminal, inc in result.inc_row.items():
        if row := rows.get(terminal):
            row.inc = inc

    for terminal in result.unresolved:
        if row := rows.get(terminal):
            row.needs_human = True
            if "span_unresolved" not in row.flags:
                row.flags.append("span_unresolved")


def resolve(
    client: LLMClient,
    config: Config,
    pdf: Path,
    sheet: SheetExtraction,
    regions: PageRegions,
    cache,
) -> int:
    """Run up to `max_zoom_passes` on this sheet. Returns the passes spent.

    A third attempt on the same region does not converge — it produces a
    third opinion, not a better one. What is still unresolved goes to a human.
    """
    passes = 0
    while passes < config.max_zoom_passes:
        targets = targets_for(sheet, regions)
        if not targets:
            break
        passes += 1
        for target in targets:
            chunks = zoom_crop(
                pdf, target.page, target.bbox_pct, cache, config.render,
                tag=f"{target.tag}-p{passes}", timeout=config.poppler_timeout_s,
            )
            try:
                payload, _ = client.complete("zoom", build_call(target, chunks))
                apply(sheet, ZoomResult.model_validate(payload))
            except (ValidationError, Exception) as error:  # noqa: BLE001
                sheet.notes.append(f"zoom {target.tag}: {error}")
                for terminal in target.terminals:
                    for row in sheet.circuit_table:
                        if row.terminal == terminal:
                            row.needs_human = True
                break
    # Anything still asking to be zoomed has had its two chances.
    for row in sheet.circuit_table:
        if row.needs_zoom or row.span_confidence != "high":
            row.needs_human = True
            if "span_unconfirmed" not in row.flags:
                row.flags.append("span_unconfirmed")
    sheet.zoom_passes = passes
    return passes
