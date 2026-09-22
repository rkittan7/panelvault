"""A DWF sheet's text, laid out into the reading the rest of the pipeline uses.

No model is involved. A CAD export keeps every label as text with its
position, so the reading is geometry:

- A device is a stack of labels at one x — `FU411 / 16A / C / ABB`,
  `FB0U2.1 / 2X40A / F202 30mA / ABB`, `Q0 / 3X250A / Inc=200A / XT3N` —
  whose tag is the stack's one device designation.
- A destination table is found by its row labels (שם / יעד / כבל / Inc);
  its columns are the terminals on the שם row, and every other cell is read
  down the column's x.
- A parts list is the sheet whose rows carry family patterns (`F...`, `Q..`).
- The switchboard data table is label/value rows (ייצרן מקורי, FORM, IP…).
- The title block is label/value pairs; see `title_block`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from ..models.schema import (
    BoardDatum, CircuitRow, Device, EquipmentListItem, Sheet, SheetExtraction, SPARE_WORDS, TitleBlock,
)
from . import whip

# Layers that carry the frame and title block on these drawings, not the
# schematic. Their text is read by the title and data-table steps instead.
FRAME_LAYERS = {"A", "TEXT", "LUAH", "LOGOENG"}

TAG = re.compile(r"^[A-Z]{1,5}\d*[A-Z]*\d+[A-Z0-9]*(?:[./-]\d+[A-Z]?)*$")
RATING = re.compile(
    r"^(?:\d[xX]\s*)?\d+(?:[.,]\d+)?(?:-\d+(?:[.,]\d+)?)?\s*(?:k?A)(?:\+N)?(?:\s*gG)?$"
    r"|^\d[xX]\d+(?:/\d+)?A(?:\s*gG)?$",
    re.I,
)
SETTING = re.compile(r"^Inc\s*=\s*\S+$", re.I)
CURVE = re.compile(r"^[BCDKZ]$")
SENSITIVITY = re.compile(r"^\d+\s*mA$", re.I)
MAKERS = {
    "ABB": "ABB", "SOCOMEC": "Socomec", "ETI": "ETI", "SCHNEIDER": "Schneider", "HAGER": "Hager",
    "SALZER": "Salzer", "PHOENIX": "Phoenix", "GIC": "GIC", "SIEMENS": "Siemens", "KLEMSAN": "Klemsan",
    "EATON": "Eaton", "LEGRAND": "Legrand", "FINDER": "Finder",
    "פיניקס": "Phoenix", "שניידר": "Schneider", "סוקומק": "Socomec", "הגר": "Hager", "סלצר": "Salzer",
}
HEBREW = re.compile(r"[֐-׿]")

# Class by model family first (it is printed and unambiguous), then by the
# tag's prefix, the way these drawings name their devices.
MODEL_CLASS = [
    (re.compile(r"^XT\d|^T\d|^TMAX", re.I), "mccb"),
    (re.compile(r"^MS1\d\d", re.I), "motor_protection"),
    (re.compile(r"^F2\d\d", re.I), "rcd"),
    (re.compile(r"^S2\d\d|^SN2\d\d", re.I), "mcb"),
    (re.compile(r"^AF\d", re.I), "contactor"),
    (re.compile(r"^VAL", re.I), "spd"),
    (re.compile(r"^EPN", re.I), "step_relay"),
    (re.compile(r"^IRL", re.I), "relay"),
    (re.compile(r"^TM\d", re.I), "plc_module"),
]
PREFIX_CLASS = [
    ("FB", "rcd"), ("FC", "fuse"), ("FA", "spd"), ("F", "mcb"),
    ("QA", "motor_protection"), ("QC", "contactor"), ("Q", "mccb"),
    ("SH", "switch"), ("SP", "switch"),
    ("PF", "lamp"), ("RC", "step_relay"), ("RH", "relay"), ("R", "relay"), ("K", "relay"),
    ("TC", "shunt_trip"),
]
NOT_DEVICES = ("X", "DI", "DO", "AI", "AO", "COM", "C0M", "CN", "SLOT", "W", "U", "L")
# Words that can sit in a device's stack but are never its model.
NOT_MODELS = ("DI", "DO", "AI", "AO", "COM", "C0M", "CN", "SLOT")


class Grid:
    """The drawing's ruled lines, to find the cell around a point."""

    def __init__(self, lines: list[list[tuple[int, int]]], min_length: int = 120):
        self.verticals: list[tuple[int, int, int]] = []
        self.horizontals: list[tuple[int, int, int]] = []
        for run in lines:
            for (x0, y0), (x1, y1) in zip(run, run[1:]):
                if abs(x0 - x1) <= 3 and abs(y0 - y1) >= min_length:
                    self.verticals.append(((x0 + x1) // 2, min(y0, y1), max(y0, y1)))
                elif abs(y0 - y1) <= 3 and abs(x0 - x1) >= min_length:
                    self.horizontals.append(((y0 + y1) // 2, min(x0, x1), max(x0, x1)))

    def cell(self, x: float, y: float) -> tuple[float, float, float, float] | None:
        """(left, bottom, right, top) of the ruled cell holding the point."""
        left = max((vx for vx, lo, hi in self.verticals if vx < x and lo <= y <= hi), default=None)
        right = min((vx for vx, lo, hi in self.verticals if vx > x and lo <= y <= hi), default=None)
        below = max((hy for hy, lo, hi in self.horizontals if hy < y and lo <= x <= hi), default=None)
        above = min((hy for hy, lo, hi in self.horizontals if hy > y and lo <= x <= hi), default=None)
        if None in (left, right, below, above):
            return None
        return left, below, right, above


def middle(text: whip.Text) -> tuple[float, float]:
    """A point inside the text: its insertion point sits on the baseline."""
    return text.x + 0.4 * text.height, text.y + 0.4 * text.height


@dataclass
class Block:
    texts: list[whip.Text]

    @property
    def x(self) -> int:
        return self.texts[0].x

    @property
    def y(self) -> int:
        return self.texts[0].y


def stacks(texts: list[whip.Text]) -> list[Block]:
    """Texts one below another at (about) one x, read top down."""
    blocks: list[Block] = []
    for text in sorted(texts, key=lambda t: -t.y):
        for block in blocks:
            last = block.texts[-1]
            reach = 2.6 * max(text.height, last.height)
            if abs(text.x - block.x) < 3 * text.height and 0 <= last.y - text.y < reach:
                block.texts.append(text)
                break
        else:
            blocks.append(Block([text]))
    return blocks


def _is_tag(value: str) -> bool:
    return bool(TAG.match(value)) and not RATING.match(value) and not value.upper().startswith(NOT_DEVICES)


def _device_class(tag: str, model: str | None, rating: str | None) -> str | None:
    if model:
        for pattern, cls in MODEL_CLASS:
            if pattern.search(model):
                return cls
    if rating and "GG" in rating.upper():
        return "fuse"
    for prefix, cls in PREFIX_CLASS:
        if tag.upper().startswith(prefix):
            return cls
    return None


LETTER_TAG = re.compile(r"^[A-Z]{2,6}$")


def _is_letter_tag(value: str) -> bool:
    """`SHE`, `QCU`, `FCKU`: a tag with no number, named by its prefix."""
    return (
        bool(LETTER_TAG.match(value)) and value not in MAKERS
        and any(value.startswith(prefix) and len(value) > len(prefix) for prefix, _ in PREFIX_CLASS)
    )


def _is_model(word: str) -> bool:
    return (
        bool(re.match(r"^[A-Z][A-Z0-9-]*\d", word) or re.match(r"^[A-Z]{2,}-[A-Z]", word))
        and "--" not in word and not word.upper().startswith(NOT_MODELS)
        and not re.search(r"\d+V$", word.upper())            # N-230V is a supply, not a model
    )


def device(block: Block) -> Device | None:
    values = [t.text for t in block.texts]
    attributes = [v for v in values if RATING.match(v) or v.upper() in MAKERS or _is_model(v.split()[0])]
    # A tag without a number counts only on a stack that also carries a
    # rating, a model or a maker: on its own it could be any word.
    tags = [v for v in values if _is_tag(v) or (attributes and _is_letter_tag(v))]
    if not tags:
        return None
    # A model number can look like a tag (AF190, MS116). The stack's tag is
    # the one named the way devices are named here; a known model family is
    # the last resort.
    def rank(value: str) -> int:
        if any(pattern.search(value) for pattern, _ in MODEL_CLASS):
            return 2
        return 0 if any(value.startswith(prefix) for prefix, _ in PREFIX_CLASS) else 1
    tag = min(tags, key=rank)
    rating = setting = curve = maker = model = sensitivity = None
    notes = []
    for value in values:
        if value == tag:
            continue
        words = value.split()
        if SETTING.match(value):
            setting = value
        elif RATING.match(value) and rating is None:
            rating = value
        elif CURVE.match(value) and curve is None:
            curve = value
        elif value.upper() in MAKERS or value in MAKERS:
            maker = MAKERS.get(value.upper(), MAKERS.get(value))
        elif SENSITIVITY.match(value):
            sensitivity = value
        elif words and _is_model(words[0]) and model is None and (
                not _is_tag(value) or any(p.search(words[0]) for p, _ in MODEL_CLASS)):
            model = words[0]
            sensitivity = next((w for w in words[1:] if SENSITIVITY.match(w)), sensitivity)
        elif HEBREW.search(value):
            notes.append(value)
    cls = _device_class(tag, model, rating)
    if cls is None:
        return None
    poles = None
    found = re.match(r"^(\d)[xX]", rating or "")
    if found:
        poles = found.group(1)
    return Device(
        tag=tag, device_class=cls, manufacturer=maker, model=model, rating=rating, poles=poles,
        setting=setting, curve=curve, description_he=" ".join(notes) or None,
    )


# ------------------------------------------------------------ circuit tables

ROW_LABELS = {"name": "שם", "destination": "יעד", "cable": "כבל", "inc": "Inc"}


def circuit_table(texts: list[whip.Text], devices: list[tuple[Device, Block]], grid: Grid) -> list[CircuitRow]:
    labels = {key: next((t for t in texts if t.text == word), None) for key, word in ROW_LABELS.items()}
    if not (labels["name"] and labels["destination"]):
        return []
    name_y = labels["name"].y
    left = labels["name"].x
    bottom_y = min(t.y for t in labels.values() if t) - 400
    # Columns: terminal names on the שם row, right of the row labels.
    columns = sorted(
        (t for t in texts if abs(t.y - name_y) < 250 and t.x > left and TAG.match(t.text)),
        key=lambda t: t.x,
    )
    if not columns:
        return []
    xs = [c.x for c in columns]
    pitch = min((b - a for a, b in zip(xs, xs[1:])), default=1000) or 1000

    dest_top = name_y - 60
    cable_y = labels["cable"].y if labels["cable"] else None
    inc_y = labels["inc"].y if labels["inc"] else None
    dest_bottom = (cable_y + 120) if cable_y is not None else bottom_y

    def column_of(x: float) -> int | None:
        best = min(range(len(xs)), key=lambda i: abs(xs[i] - x))
        return best if abs(xs[best] - x) < 0.75 * pitch else None

    def span_of(text: whip.Text) -> list[int]:
        """The columns sharing the ruled cell that holds the text."""
        cell = grid.cell(*middle(text))
        if cell is not None:
            covered = [i for i, cx in enumerate(xs) if cell[0] < cx + 0.4 * pitch and cx + 0.4 * pitch < cell[2]]
            if covered:
                return covered
        col = column_of(text.x)
        return [col] if col is not None else []

    destination: dict[int, list[whip.Text]] = {i: [] for i in range(len(xs))}
    spans: dict[int, list[str]] = {}
    cable: dict[int, str] = {}
    inc: dict[int, str] = {}
    for t in texts:
        if t in columns or t in labels.values():
            continue
        if dest_bottom < t.y < dest_top:
            covered = span_of(t)
            for i in covered:
                destination[i].append(t)
            if len(covered) > 1:
                for i in covered:
                    spans[i] = [columns[j].text for j in covered]
        elif cable_y is not None and abs(t.y - cable_y) < 200 and re.search(r"\d[xX]", t.text):
            col = column_of(t.x)
            if col is not None:
                cable[col] = t.text
        elif inc_y is not None and abs(t.y - inc_y) < 200 and RATING.match(t.text):
            col = column_of(t.x)
            if col is not None:
                inc[col] = t.text

    protective = [(d, b) for d, b in devices
                  if d.device_class in {"mcb", "mccb", "rcd", "fuse", "motor_protection", "switch"}]
    rows = []
    for i, column in enumerate(columns):
        parts = sorted(destination[i], key=lambda t: (-t.y, t.x))
        text = " ".join(t.text for t in parts) or None
        above = [(d, b) for d, b in protective if abs(b.x - column.x) < 0.6 * pitch and b.y > name_y]
        below_most = min(above, key=lambda db: db[1].y)[0].tag if above else None
        rows.append(CircuitRow(
            terminal=column.text,
            protective_device=below_most,
            destination_he=text,
            span_terminals=spans.get(i, []),
            span_confidence="high",
            cable=cable.get(i),
            inc=inc.get(i),
            is_spare=bool(text and any(word in text for word in SPARE_WORDS)),
        ))
    return rows


# ------------------------------------------------------------- parts list

FAMILY = re.compile(r"^[A-Z]{1,4}\d?\.{2,}$|^[A-Z]{1,4}\d?…$")


def equipment_list(texts: list[whip.Text], grid: Grid) -> list[EquipmentListItem]:
    """One item per family pattern, read across the ruled row it sits in."""
    families = [t for t in texts if FAMILY.match(t.text)]
    if len(families) < 3:
        return []
    cells = {id(f): grid.cell(*middle(f)) for f in families}
    heights = sorted(c[3] - c[1] for c in cells.values() if c)
    usual = heights[len(heights) // 2] if heights else 0
    items = []
    for family in families:
        cell = cells[id(family)]
        # A row whose ruling did not close reads across its neighbours; better
        # no model from it than someone else's.
        if cell is None or cell[3] - cell[1] > 1.6 * usual:
            continue
        _, bottom, _, top = cell
        row = [t for t in texts if t is not family and bottom < middle(t)[1] < top]
        maker = next((MAKERS.get(t.text.upper(), MAKERS.get(t.text)) for t in row
                      if t.text.upper() in MAKERS or t.text in MAKERS), None)
        model = next((t.text.split()[0] for t in row
                      if re.match(r"^[A-Z][A-Z0-9-]*\d", t.text) and not FAMILY.match(t.text)
                      and not RATING.match(t.text)), None)
        description = " ".join(t.text for t in sorted(row, key=lambda t: -t.x) if HEBREW.search(t.text)) or None
        rating = next((t.text for t in row if RATING.match(t.text)), None)
        poles = next((m.group(1) for t in row if (m := re.search(r"\((\d)P\)", t.text))), None)
        cls = _device_class(family.text.rstrip(".…"), model, rating) or "external"
        items.append(EquipmentListItem(
            tag_pattern=family.text, device_class=cls, description_he=description,
            manufacturer=maker, model=model, rating=rating, poles=poles,
        ))
    return items


# ------------------------------------------------------ board data table

DATA_LABELS = ("ייצרן מקורי", "יצרן מקורי", "מידור", "מידה כללית", "דרגת הגנה", "זרם הלוח",
               "שיטת הארקה", "מתח רשת", "תדר", "סוג המעטפת", "משקל מוערך", "גוון צבע")


def board_data(texts: list[whip.Text], grid: Grid) -> list[BoardDatum]:
    """Each labelled row's value, from the column headed מידע/נתון.

    Rows are the ruled bands; columns are told apart by the nearest header,
    since not every column divider is drawn as a line of its own.
    """
    headers = {name: next((t for t in texts if t.text.startswith(word)), None)
               for name, word in (("value", "מידע/נתון"), ("symbol", "ערך"), ("label", "תאור"))}
    if headers["value"] is None:
        return []
    columns = {name: middle(t)[0] for name, t in headers.items() if t}
    rows = []
    for text in texts:
        label = next((l for l in DATA_LABELS if text.text.startswith(l)), None)
        if label is None:
            continue
        cell = grid.cell(*middle(text))
        if cell is None:
            continue
        _, bottom, _, top = cell
        value = [
            t for t in texts
            if t is not text and bottom < middle(t)[1] < top
            and min(columns, key=lambda c: abs(columns[c] - middle(t)[0])) == "value"
            and abs(columns["value"] - middle(t)[0]) < 1500
        ]
        if value:
            rows.append(BoardDatum(label_he=label, value=" ".join(
                t.text for t in sorted(value, key=lambda t: (-t.y, -t.x)))))
    return rows


# ------------------------------------------------------------- title block

STAGE_WORDS = {"לביצוע", "לאישור", "לשרטוט", "AS-MADE", "מתוך", "דף מס'", "עדכון מס'", "תאריך עדכון"}

TITLE_LABELS = {
    "project": ("שם פרוייקט", "שם פרויקט"),
    "client": ("שם המזמין",),
    "panel": ("שם הלוח",),
    "consultant": ("שם היועץ",),
    "drawing_no": ("מס' סדורי",),
    "drawn_by": ("שרטט",),
}


def title_block(texts: list[whip.Text], board_number: str) -> TitleBlock:
    """Label/value pairs, calibrated on the one pair whose value is known.

    AutoCAD plots a title block's fixed labels in paper space and its filled
    attributes in model space, so on these DWFs a value sits a fixed distance
    left of its label that is not the distance on paper. The drawing number
    is known from the package, so its pair measures that distance, and every
    other label's value is looked for the same distance away, on its row.
    """
    title_texts = [t for t in texts if t.layer in FRAME_LAYERS]
    labels = {
        field: next((t for t in title_texts if any(t.text.startswith(w) for w in words)), None)
        for field, words in TITLE_LABELS.items()
    }
    anchor_label = labels.get("drawing_no")
    anchor_value = next((t for t in title_texts if t.text == board_number), None)
    found: dict[str, str] = {}
    if board_number:
        found["drawing_no"] = board_number
    if anchor_label is None or anchor_value is None:
        return TitleBlock(**found)
    shift = anchor_label.x - anchor_value.x
    all_labels = {t for t in labels.values() if t}
    for field, label in labels.items():
        if label is None or field == "drawing_no":
            continue
        target = label.x - shift
        candidates = [t for t in title_texts if t not in all_labels and _value_like(t)
                      and -2.5 * label.height < t.y - label.y < 1.5 * label.height]
        if not candidates:
            continue
        near = [t for t in candidates if abs(t.x - target) < 1500]
        if not near:
            continue
        # The value's first line is the top one near the target; its further
        # lines follow close below it, nearer than the next row's value.
        first = max(near, key=lambda t: t.y)
        cell, bottom = [first], first
        for t in sorted(title_texts, key=lambda t: -t.y):
            if t is not first and _value_like(t) and t not in all_labels and abs(t.x - first.x) < 1000 \
                    and not t.text.isdigit() and 0 < bottom.y - t.y < 1.3 * t.height:
                cell.append(t)
                bottom = t
        found[field] = " ".join(t.text for t in sorted(cell, key=lambda t: (-t.y, -t.x)))
    # The builder: its name heads the block with the logo, unlabelled, beyond
    # every label.
    if labels.get("project"):
        rightmost = max(l.x for l in all_labels)
        names = [t for t in title_texts if t.x > rightmost + 2000 and _value_like(t) and HEBREW.search(t.text)]
        if names:
            found["panel_builder"] = max(names, key=lambda t: t.y).text
    return TitleBlock(**found)


def _value_like(text: whip.Text) -> bool:
    """Not a label, a single stray glyph of a logo, or a stage box."""
    return len(text.text) > 1 and not text.text.rstrip().endswith(":") and text.text not in STAGE_WORDS


# ------------------------------------------------------------------ sheet

def read_sheet(number: int, page: whip.Page, board_number: str) -> SheetExtraction:
    schematic = [t for t in page.texts if t.rotation == 0 and t.layer not in FRAME_LAYERS]
    devices: list[tuple[Device, Block]] = []
    for block in stacks(schematic):
        found = device(block)
        if found is not None:
            devices.append((found, block))
    grid = Grid(page.lines)
    table = circuit_table(schematic, devices, grid)
    return SheetExtraction(
        sheet=Sheet(page_number=number, sheet_label=f"{number:02d}",
                    title_block=title_block(page.texts, board_number)),
        devices=[d for d, _ in devices],
        circuit_table=table,
        equipment_list=equipment_list([t for t in page.texts if t.rotation == 0], grid),
        board_data=board_data(page.texts, grid),
    )


def consensus_title(titles: list[TitleBlock]) -> TitleBlock:
    """Each title field as most sheets read it: one sheet's stray note
    beside its title block does not outvote the other forty."""
    fields = {}
    for name in ("project", "panel", "panel_builder", "client", "consultant", "drawing_no", "drawn_by"):
        values = [getattr(t, name) for t in titles if getattr(t, name)]
        if values:
            fields[name] = max(set(values), key=values.count)
    return TitleBlock(**fields)
