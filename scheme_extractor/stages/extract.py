"""Stage 3 — one call per sheet, Prompt A, structured output.

The call is assembled so the expensive half of it can be cached: the system
prompt and the tool schema are byte-identical across all thirty-five sheets
and carry the cache breakpoint, and everything that varies — the tokens, the
images — comes after.
"""

from __future__ import annotations

import json
import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from pydantic import ValidationError

from ..config import Config
from ..models.client import Call, LLMClient, image_block, text_block
from ..models.schema import SheetExtraction, tool_schema
from .render import PageRegions
from .textlayer import PageTokens

PROMPTS = Path(__file__).resolve().parent.parent / "prompts"

# Frame furniture: the column numbers and row letters printed around every
# sheet border. They are the only thing some pages' text layers contain, and
# they say nothing about the drawing.
FRAME_TOKEN = re.compile(r"^(?:[A-E]|[1-9]|\d{1,3})$")

TOKEN_GUIDANCE_RICH = """\
## About `latin_tokens` on this set
The token list is dense on these sheets and covers the drawing area. Treat a
tag that is absent from it as a probable misreading, and re-read the crop."""

TOKEN_GUIDANCE_FRAME = """\
## About `latin_tokens` on this set — read this before using the precedence rule
On this drawing set the PDF's text layer holds ONLY the sheet frame, the busbar
captions, the `Inc` row label and the title block. The device tags, ratings,
model numbers, terminal names and cable specs were exploded to vector geometry
by the CAD export and are NOT in the token list at all.

So: where a token IS present it is machine-exact and outranks the image. Where a
token is absent that means nothing whatsoever — it is not evidence that you have
misread anything. Read those values from the crops and report them. Do not
suppress a tag, and do not lower your confidence, merely because the token list
does not contain it."""


def region_guidance(regions: PageRegions, chunk_overlap: int) -> str:
    """Tell the model exactly which images it is getting, and in what order.

    The overlap warning is not optional. Chunks of the table band share a
    strip of pixels so that a merged cell is never cut without context — but
    a model that does not know that will count the shared columns twice.
    """
    parts = ["## The images attached to this message, in order"]
    parts.append("1. `full_page` — the whole sheet, downscaled. Layout only. Never read a value off it.")
    index = 2
    single = regions.regions.get("single_line")
    if single:
        parts.append(
            f"{index}. `region_single_line` — the diagram area above the table, "
            f"in {len(single.chunks)} piece(s) left to right."
        )
        index += 1
    band = regions.regions.get("table_band")
    if band:
        parts.append(
            f"{index}. `region_destination_table` — the destination table at high resolution, "
            f"in {len(band.chunks)} piece(s) left to right."
        )
        index += 1
    title = regions.regions.get("title_block")
    if title:
        parts.append(
            f"{index}. `region_title_block` — the title block, in {len(title.chunks)} piece(s) "
            "left to right that overlap by a tenth of its width. Each label sits to the RIGHT "
            "of its own value (Hebrew order); pair them within one piece, never across two."
        )
        index += 1
    else:
        parts.append(
            "The title block is identical on every sheet of this set and is read once "
            "elsewhere. Leave `sheet.title_block` fields null here unless this sheet "
            "prints something different."
        )

    if (single and len(single.chunks) > 1) or (band and len(band.chunks) > 1):
        parts.append(
            f"\nConsecutive pieces of the same region OVERLAP by about {chunk_overlap} pixels: "
            "the rightmost columns of one piece are the leftmost columns of the next. "
            "That overlap exists so a merged cell is never cut without context. Reconcile "
            "the pieces into ONE table — a terminal that appears in two pieces is one "
            "terminal, not two."
        )
    if regions.layout_kind == "no_table":
        parts.append(
            "\nThis sheet has NO destination table. Return `circuit_table: []` and do not "
            "invent one. It is a control schematic, a PLC I/O sheet, an elevation or an "
            "equipment list."
        )
    return "\n".join(parts)


def filter_tokens(tokens: PageTokens) -> list[dict[str, float | str]]:
    """Drop what repeats on every sheet, keep what locates the drawing.

    Roughly halves the payload, and more importantly stops thirty-five copies
    of the same title block from crowding the useful tokens.
    """
    title = tokens.anchors.get("title_block")
    cutoff = title.y0 - 4 if title else tokens.height
    kept = []
    for token in tokens.tokens:
        if token.y0 >= cutoff:
            continue
        if FRAME_TOKEN.match(token.text) and (
            token.cx < tokens.width * 0.03
            or token.cx > tokens.width * 0.97
            or token.cy < tokens.height * 0.04
        ):
            continue
        kept.append(
            {
                "text": token.text,
                "x": round(token.x0, 1),
                "y": round(token.y0, 1),
                "w": round(token.w, 1),
                "h": round(token.h, 1),
            }
        )
    return kept


@dataclass
class SheetCall:
    page: int
    label: str
    call: Call


def build_call(
    tokens: PageTokens,
    regions: PageRegions,
    *,
    total_pages: int,
    text_coverage: str,
    chunk_overlap: int,
) -> SheetCall:
    # The system prompt must be byte-identical across every sheet in the run,
    # because it carries the cache breakpoint. Anything that varies per sheet —
    # which crops came, how many pieces, whether there is a table — belongs in
    # the user turn, after the breakpoint.
    system = (PROMPTS / "prompt_a.md").read_text(encoding="utf-8")
    system = system.replace(
        "{{TOKEN_GUIDANCE}}",
        TOKEN_GUIDANCE_RICH if text_coverage == "rich" else TOKEN_GUIDANCE_FRAME,
    )

    label = sheet_label(tokens)
    content: list[dict] = [
        text_block(
            f"sheet_index: {tokens.page} of {total_pages}\n"
            f"sheet_label: {label}\n\n"
            + region_guidance(regions, chunk_overlap)
            + "\n\nlatin_tokens:\n"
            + json.dumps(filter_tokens(tokens), ensure_ascii=False)
        ),
        image_block(regions.regions["context_page"].path),
    ]
    for name in ("single_line", "table_band", "title_block"):
        region = regions.regions.get(name)
        if region:
            content.extend(image_block(chunk) for chunk in region.chunks)

    return SheetCall(
        tokens.page,
        label,
        Call(
            key=f"sheet-{tokens.page:03d}",
            system=system,
            content=content,
            tool_name="sheet_extraction",
            schema=tool_schema(SheetExtraction),
        ),
    )


def sheet_label(tokens: PageTokens) -> str:
    """The label printed bottom-left.

    Total pages and sheet label share a cell there (`35 06`), so the label is
    the rightmost of the two numbers, not the leftmost.
    """
    corner = [
        t for t in tokens.tokens
        if t.cy > tokens.height * 0.90 and t.cx < tokens.width * 0.15 and t.text.isdigit()
    ]
    if not corner:
        return f"{tokens.page:02d}"
    return max(corner, key=lambda t: t.cx).text


def extract_sheets(
    client: LLMClient,
    config: Config,
    calls: list[SheetCall],
) -> dict[int, tuple[SheetExtraction | None, str]]:
    """Run the whole stage, and never let one sheet end the run."""
    raw = client.complete_many("extract", [c.call for c in calls])
    by_key = {c.call.key: c for c in calls}
    results: dict[int, tuple[SheetExtraction | None, str]] = {}

    def finish(key: str) -> None:
        sheet_call = by_key[key]
        payload, usage = raw[key]
        if payload is None:
            results[sheet_call.page] = (None, usage.note or "no response")
            return
        try:
            results[sheet_call.page] = (SheetExtraction.model_validate(payload), "")
            return
        except ValidationError as error:
            message = _first_error(error)
        try:
            # One correction turn with the validation error attached (§6). The
            # invariants that fail here — a qty that does not match its tags, a
            # spare with no שמור — are exactly the ones worth one more ask.
            corrected, _ = client.revalidate("extract", sheet_call.call, message)
            results[sheet_call.page] = (SheetExtraction.model_validate(corrected), "")
        except Exception as error:  # noqa: BLE001 — carry on with the other sheets
            results[sheet_call.page] = (None, f"{message} | retry failed: {error}")

    with ThreadPoolExecutor(max_workers=config.extract_concurrency) as pool:
        list(pool.map(finish, list(raw)))
    return results


def _first_error(error: ValidationError) -> str:
    first = error.errors()[0]
    location = ".".join(str(part) for part in first["loc"])
    return f"{location}: {first['msg']}"
