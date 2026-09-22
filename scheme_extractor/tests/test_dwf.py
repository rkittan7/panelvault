"""The DWF reader: the WHIP decoder, Hebrew, and reading sheets as geometry."""

from __future__ import annotations

import io
import os
import struct
import zipfile
from pathlib import Path

import pytest

from scheme_extractor.dwf import hebrew, package, whip
from scheme_extractor.dwf.sheet import (
    Grid, board_data, circuit_table, consensus_title, device, enclosure_build, equipment_list, read_sheet,
    stacks, title_block,
)
from scheme_extractor.models.schema import TitleBlock

REFERENCE_DWF = os.environ.get("SCHEME_REFERENCE_DWF")
needs_reference = pytest.mark.skipif(
    not (REFERENCE_DWF and Path(REFERENCE_DWF).exists()), reason="set SCHEME_REFERENCE_DWF to a DWF set",
)


# -------------------------------------------------------------- WHIP decoder

def _text(dx: int, dy: int, value: str) -> bytes:
    return b"x" + struct.pack("<ii", dx, dy) + b"'" + value.encode("latin-1") + b"'"


def test_text_positions_accumulate_across_every_drawing_opcode():
    stream = (
        b"(W2D V06.00)(Layer 3 DRAWING)"
        + _text(1000, 2000, "FU411")
        + b"\x0c" + struct.pack("<hhhh", 10, 20, 30, 40)           # 16-bit line: two relative points
        + _text(5, -5, "16A")
    )
    page = whip.read(stream)
    assert [(t.x, t.y, t.text, t.layer) for t in page.texts] == [
        (1000, 2000, "FU411", "DRAWING"),
        (1000 + 10 + 30 + 5, 2000 + 20 + 40 - 5, "16A", "DRAWING"),
    ]
    assert page.lines == [[(1010, 2020), (1040, 2060)]]


def test_an_extended_binary_block_is_skipped_by_its_own_size():
    # `self.i += self.i32()` once skipped four bytes short: the offset was
    # taken before the size was read.
    blob = b"{" + struct.pack("<i", 6) + b"abcde}"
    page = whip.read(b"(W2D V06.00)" + blob + _text(1, 2, "Q0"))
    assert [t.text for t in page.texts] == ["Q0"]


def _boxed_text(dx: int, dy: int, value: str, corners: list[tuple[int, int]]) -> bytes:
    """0x18: position, string, no overscore/underscore, 4 relative corners, no reserved."""
    return (b"\x18" + struct.pack("<ii", dx, dy) + b"'" + value.encode("latin-1") + b"'"
            + b"\x01\x01" + b"".join(struct.pack("<ii", *c) for c in corners) + b"\x01")


def test_a_texts_bounding_box_moves_the_pen():
    # Skipping the corners as bytes drifted every later text by a text's height.
    stream = (b"(W2D V06.00)" + _boxed_text(100, 100, "F327", [(0, -27), (400, 0), (0, 140), (-400, 0)])
              + _text(1000, -113, "F328"))
    page = whip.read(stream)
    assert [(t.text, t.x, t.y) for t in page.texts] == [("F327", 100, 100), ("F328", 1100, 100)]


def test_an_images_corners_move_the_pen():
    # A logo's corners are relative points: skipped, the frame sat 8000 off.
    body = struct.pack("<HHH", 0x0008, 406, 108) + struct.pack("<iiii", 5881, -622, 2436, 648) + b"jpeg"
    blob = b"{" + struct.pack("<i", len(body) + 1) + body + b"}"
    page = whip.read(b"(W2D V06.00)" + blob + _text(-8317, -26, "Q1"))
    assert (page.texts[0].x, page.texts[0].y) == (0, 0)


def test_backslash_escapes_a_quote_inside_a_string():
    page = whip.read(b"(W2D V06.00)" + b"x" + struct.pack("<ii", 0, 0) + b"'ao\\'s'")
    assert page.texts[0].text == "ao's"


def test_an_unknown_opcode_stops_the_reader_instead_of_drifting():
    with pytest.raises(whip.WhipError):
        whip.read(b"(W2D V06.00)\x9f")


# -------------------------------------------------------------------- Hebrew

def test_keyboard_hebrew_is_decoded_word_by_word():
    assert hebrew.decode("ao pruhhey:") == "שם פרוייקט:"   # as the drawing spells it
    assert hebrew.decode(",trhl gsfui") == "תאריך עדכון"
    # Latin stays Latin: tags, ratings, models, units, e-mail.
    assert hebrew.decode("FU411 16A F202 30mA") == "FU411 16A F202 30mA"
    assert hebrew.decode("Bassam@kittan") == "Bassam@kittan"
    assert hebrew.decode("kuj jank 2E") == "לוח חשמל E2"
    assert hebrew.decode(",/ jhruo") == "ת. חירום"        # the ת key is the comma
    assert hebrew.decode("3, 4") == "3, 4"
    # Latin inside a Hebrew label is typed backwards for the right-to-left font.
    assert hebrew.decode("ntn,ho-ntzho AK01") == "מאמתים-מאזים 10KA"
    assert hebrew.decode("3-n SPU") == "3-מ UPS"
    assert hebrew.decode("4x150 N2XY") == "4x150 N2XY"       # a size, not Hebrew


# ------------------------------------------------------------------- package

def test_a_package_is_its_header_and_a_zip_with_a_manifest():
    stream = b"(W2D V06.00)(Layer 1 TEXT)" + _text(0, 0, "ao vkuj:")
    manifest = (
        '<dwf:Manifest xmlns:dwf="DWF-Manifest:1.1"><dwf:Sections>'
        '<dwf:Section type="com.autodesk.dwf.ePlot" name="s1" title="4382.26-1-1"><dwf:Toc>'
        '<dwf:Resource role="2d streaming graphics" mime="application/x-w2d" href="s1\\page.w2d"/>'
        "</dwf:Toc></dwf:Section></dwf:Sections></dwf:Manifest>"
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("manifest.xml", manifest)
        archive.writestr("s1\\page.w2d", stream)
    sheets = package.read(b"(DWF V06.00)" + buffer.getvalue())
    assert [(s.number, s.title) for s in sheets] == [(1, "4382.26-1-1")]
    assert sheets[0].page.texts[0].text == "שם הלוח:"
    assert package.board_number(sheets) == "4382.26-1"


# ------------------------------------------------------------ sheet layout

def T(text: str, x: int, y: int, layer: str = "DRAWING", height: int = 109) -> whip.Text:
    return whip.Text(x, y, text, layer, height, 0)


def _stack(x: int, top: int, *values: str) -> list[whip.Text]:
    return [T(v, x, top - 150 * i) for i, v in enumerate(values)]


def test_stacked_labels_are_one_device_each():
    texts = (_stack(6684, 3599, "FU411", "16A", "C", "ABB")
             + _stack(7779, 4876, "R", "FB0U2.1", "2X40A", "F202 30mA", "ABB")
             + _stack(10588, 6691, "Q0", "3X250A", "Inc=200A", "XT3N")
             + _stack(11337, 4707, "QCU", "AF190", "ABB")
             + _stack(7740, 3936, "SHE", "4x400A", "Socomec"))
    found = {d.tag: d for d in (device(b) for b in stacks(texts)) if d}
    assert (found["FU411"].device_class, found["FU411"].rating, found["FU411"].curve) == ("mcb", "16A", "C")
    assert (found["FB0U2.1"].device_class, found["FB0U2.1"].model) == ("rcd", "F202")
    assert (found["Q0"].model, found["Q0"].setting, found["Q0"].poles) == ("XT3N", "Inc=200A", "3")
    assert (found["QCU"].device_class, found["QCU"].model) == ("contactor", "AF190")   # not a device "AF190"
    assert (found["SHE"].device_class, found["SHE"].manufacturer) == ("switch", "Socomec")


def test_a_word_without_a_number_is_a_tag_only_beside_a_rating_or_model():
    assert [device(b) for b in stacks(_stack(100, 500, "SPU", "0-1"))] == [None]


def _ruled_table(columns: list[int], rows: list[int], x0: int, x1: int) -> list[list[tuple[int, int]]]:
    lines = [[(x, rows[-1]), (x, rows[0])] for x in columns]
    lines += [[(x0, y), (x1, y)] for y in rows]
    return lines


def test_a_table_is_read_down_its_columns_with_merged_cells_spanning():
    # Three columns, 960 apart; the middle and right share one destination cell.
    texts = [
        T("שם", 5794, 775, "BOARD"), T("יעד", 5838, 602, "BOARD"),
        T("כבל", 5813, 28, "BOARD"), T("Inc", 5714, -198, "BOARD"),
        T("X21", 6440, 695), T("X22", 7400, 695), T("X23", 8360, 695),
        T("קרוסלה", 6300, 450), T("עמדות עבודה", 7850, 450),
        T("3x2.5N2XY", 6300, 32), T("3x2.5N2XY", 7260, 32), T("5x10N2XY", 8220, 32),
        T("12.8A", 6327, -147), T("12.8A", 7279, -147), T("32A", 8240, -147),
    ] + _stack(6440, 3000, "F21", "16A", "C", "ABB") + _stack(7400, 3000, "F22", "16A", "C", "ABB")
    # A rule between X21 and X22 only: X22 and X23 share a destination cell.
    grid = Grid(_ruled_table([5960, 6920, 8840], [800, 620, 100, -60, -300], 5600, 8840))
    devices = [(d, b) for b in stacks([t for t in texts if t.y > 2000]) if (d := device(b))]
    rows = {r.terminal: r for r in circuit_table(texts, devices, grid)}
    assert rows["X21"].destination_he == "קרוסלה"
    assert rows["X22"].destination_he == rows["X23"].destination_he == "עמדות עבודה"
    assert rows["X22"].span_terminals == ["X22", "X23"]
    assert (rows["X23"].cable, rows["X23"].inc) == ("5x10N2XY", "32A")
    assert (rows["X21"].protective_device, rows["X22"].protective_device) == ("F21", "F22")


def test_a_frame_line_through_a_table_does_not_split_a_merged_cell():
    texts = [
        T("שם", 5794, 775, "BOARD"), T("יעד", 5838, 602, "BOARD"),
        T("X21", 6440, 695), T("X22", 7400, 695),
        T("עמדות", 6900, 450), T("עבודה", 6700, 450),
    ]
    lines = _ruled_table([5960, 8840], [800, 620, 100], 5600, 8840)
    lines.append([(7300, -900), (7300, 9000)])          # the title block's rule, far past the table
    rows = {r.terminal: r for r in circuit_table(texts, [], Grid(lines))}
    assert rows["X21"].destination_he == rows["X22"].destination_he == "עמדות עבודה"   # right to left


def test_a_second_device_tag_starts_its_own_stack():
    found = [d.tag for b in stacks(_stack(7424, 5319, "QU1", "מפסק הזנה", "PHU1")) if (d := device(b))]
    assert found == ["QU1", "PHU1"]


def test_the_parts_list_reads_each_family_across_its_ruled_row():
    texts = [
        T("Q..", 13228, 7753, "TEXT"), T("XT3N 250 36kA", 16851, 7679, "TEXT"), T("ABB", 18000, 7700, "TEXT"),
        T("F...", 13247, 6450, "TEXT"), T("S201M", 17369, 6471, "TEXT"), T("(1P)", 19326, 6445, "TEXT"),
        T("KSR..", 13218, 4237, "TEXT"), T("EPN510", 17242, 4206, "TEXT"), T("HAGER", 18000, 4220, "TEXT"),
    ]
    grid = Grid(_ruled_table([12376, 21294], [7923, 7604, 6647, 6328, 4413, 4094], 12376, 21294))
    items = {i.tag_pattern: i for i in equipment_list(texts, grid)}
    assert (items["Q.."].model, items["Q.."].device_class) == ("XT3N", "mccb")
    assert (items["F..."].model, items["F..."].poles) == ("S201M", "1")
    assert (items["KSR.."].model, items["KSR.."].manufacturer) == ("EPN510", "Hager")


def test_the_data_table_value_is_the_column_headed_for_values():
    texts = [
        T("מידע/נתון", 10500, 6600, "A"), T("ערך", 12000, 6600, "A"), T("תאור", 13900, 6600, "A"),
        T("ייצרן מקורי", 13988, 6271, "A"), T("פח-תמחש", 11229, 6266, "A"), T("T4P-M", 10402, 6235, "A"),
        T("מידור", 13931, 5747, "A"), T("FORM", 12000, 5720, "A"), T("FORM-1", 10444, 5694, "A"),
    ]
    grid = Grid(_ruled_table([4729, 15133], [6366, 6183, 5816, 5632], 4729, 15133))
    data = {d.label_he: d.value for d in board_data(texts, grid)}
    assert data == {"ייצרן מקורי": "פח-תמחש T4P-M", "מידור": "FORM-1"}


def test_title_values_are_found_at_the_offset_the_drawing_number_measures():
    # Labels in paper space, values in model space 10068 units to the left.
    texts = [
        T("מס' סדורי:", 12665, 1512, "A", 179), T("4382.26-1", 2597, 1583, "A", 179),
        T("שם פרוייקט:", 18288, 1688, "TEXT", 126), T("אגרובנק", 8486, 1489, "A", 179),
        T("TOWER B", 7905, 1410, "A", 179),
        T("שם המזמין:", 18274, 1122, "TEXT", 126), T('ס.מ.ע עבודות חשמל בע"מ', 9051, 1026, "A", 179),
        T("שם הלוח:", 18288, 679, "TEXT", 126), T("לוח חשמל", 8609, 674, "A", 179),
        T("E2", 7763, 562, "A", 179), T("קומה 22", 8448, 454, "A", 179), T("42", 9743, 296, "LUAH", 126),
    ]
    title = title_block(texts, "4382.26-1")
    assert title.project == "אגרובנק TOWER B"
    assert title.client == 'ס.מ.ע עבודות חשמל בע"מ'
    assert title.panel == "לוח חשמל E2 קומה 22"


def test_the_front_elevation_counts_the_cabinets_and_names_the_format():
    page = whip.Page(texts=[
        T("מראה לוח עם פנלים לפי תקן", 18448, 9179, "PTAG", 82),
        T("1950", 9988, 4918, "PRTG"), T("100", 10217, 2251, "PRTG"),   # height and base, not widths
        T("500", 11171, 1900, "DREAW"), T("600", 12776, 1900, "DREAW"), T("600", 14502, 1900, "DREAW"),
        T("800", 16539, 1900, "DREAW"), T("800", 18867, 1899, "DREAW"), T("600", 20905, 1899, "DREAW"),
        T("3900", 16057, 1662, "DREAW"), T("500", 22350, 2354, "PTAG"),  # overall width, and the depth
    ])
    build = enclosure_build([page], width=3900)
    assert build == {"cabinet_count": "6", "cabinet_widths": "500+600+600+800+800+600",
                     "build_format": "Panels"}


def test_the_title_is_what_most_sheets_read():
    good = TitleBlock(project="אגרובנק TOWER B")
    odd = TitleBlock(project="אגרובנק TOWER B כניסות-יציאות כבלים")
    assert consensus_title([good, good, odd]).project == "אגרובנק TOWER B"


# ---------------------------------------------------------- the whole set

@needs_reference
def test_a_dwf_set_reads_end_to_end_without_a_model():
    from scheme_extractor.config import Config
    from scheme_extractor.pipeline import run

    result = run(Path(REFERENCE_DWF), Config(), job_id="dwf")
    assert result.cost == {"total_usd": 0.0}
    assert sum(line.qty for line in result.bom) > 100
    assert result.circuits and result.sheets[0].sheet.title_block.drawing_no
