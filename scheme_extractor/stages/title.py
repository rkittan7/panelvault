"""The title block and the board data table, read in one small call.

These name the board — project, customer, board name, enclosure maker — and
they are in Hebrew set in a CAD font. On 4382.26-8 Haiku paired every label
with the right value once asked about nothing else, but misread the letters
themselves (חשמל as השמחי, ס.מ.ע as ס.ה.ע) however the crop was prepared;
Sonnet 5 read every field. So this one call has its own stage and model,
and costs about two cents; the sheet itself is read with the others.
"""

from __future__ import annotations

from pathlib import Path

from ..models.client import Call, LLMClient, image_block, text_block
from ..models.schema import TitleResult, tool_schema
from .render import PageRegions

PROMPT = """\
You are reading the identity of one Israeli low-voltage switchboard drawing.

The first images are its TITLE BLOCK, cut into pieces left to right that
overlap by a quarter of its width. Hebrew reads right to left: each field is a
bold label ending in ":" with its value in the same cell, immediately to the
LEFT of the label. Pair each label with the value beside it inside one piece;
never across two.
- project — שם פרויקט
- client — שם המזמין (who ordered the board)
- panel — שם הלוח (the board's name)
- consultant — שם היועץ
- drawing_no — מס' סדורי
- drawn_by — שרטט; status — the ticked stage (AS-MADE, לביצוע…);
  revision_dates — תאריך עדכון; total_pages — the number after מתוך
- panel_builder — the company named with its logo in its own cell, with no
  label: the firm that built the board.

The last images are the rest of the same sheet. If they hold the switchboard
data table (תיאור / ערך, per ת"י 61439: יצרן מקורי, דרגת הגנה, מידור, מידה
כללית, זרם הלוח, שיטת הארקה, מתח רשת, תדר…) copy each row into `board_data`:
the Hebrew label, the symbol column if any, and the value, exactly as printed.

Copy Hebrew letter by letter exactly as printed. Leave out anything you cannot
read; never fill one field from another."""


def build_call(regions: PageRegions) -> Call | None:
    title = regions.regions.get("title_block")
    if title is None:
        return None
    content: list[dict] = [image_block(chunk) for chunk in title.chunks]
    single = regions.regions.get("single_line")
    if single:
        content.append(text_block("The rest of the sheet, left to right:"))
        content.extend(image_block(chunk) for chunk in single.chunks)
    return Call(
        key=f"title-{regions.page:03d}",
        system=PROMPT,
        content=content,
        tool_name="board_identity",
        schema=tool_schema(TitleResult),
    )


def read(client: LLMClient, regions: PageRegions) -> tuple[TitleResult | None, str]:
    call = build_call(regions)
    if call is None:
        return None, ""
    try:
        payload, _ = client.complete("title", call)
        return TitleResult.model_validate(payload), ""
    except Exception as error:  # noqa: BLE001 — the rest of the run stands without it
        return None, f"The title block could not be read: {error}"
