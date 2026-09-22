"""What the review screen receives — shapes seen on 4382.26-8."""

from scheme_extractor.models.schema import (
    AuditResult, Device, ExtractionRun, PanelFact, Sheet, SheetExtraction, TitleBlock,
)
from scheme_extractor.output.payload import board_draft
from scheme_extractor.stages.rollup import build_bom


def _sheet(page, devices, title=None):
    return SheetExtraction(
        sheet=Sheet(page_number=page, sheet_label=f"{page:02d}", title_block=title or TitleBlock()),
        devices=[Device(**d) for d in devices],
    )


def _run(sheets, facts=()):
    return ExtractionRun(
        job_id="j", source_hash="h", sheets=sheets, bom=build_bom(sheets),
        audit=AuditResult(panel=[PanelFact(field=f, value=v) for f, v in facts]),
    )


def test_one_rcd_is_one_line_whatever_the_poles_spelling_or_a_missing_model():
    sheets = [
        _sheet(15, [{"tag": "FB0U461", "device_class": "rcd", "manufacturer": "ABB", "model": "F202",
                     "rating": "2X40A", "poles": "2"}]),
        _sheet(16, [{"tag": "FB0U482", "device_class": "rcd", "manufacturer": "ABB", "model": "F202",
                     "rating": "2x40A", "poles": "2P"}]),
        _sheet(12, [{"tag": "FB0U1.1", "device_class": "rcd", "manufacturer": "ABB",
                     "rating": "2X40A", "poles": "2"}]),
    ]
    bom = build_bom(sheets)
    assert len(bom) == 1
    assert bom[0].qty == 3
    assert "model_inferred" in bom[0].flags


def test_a_missing_model_is_not_guessed_between_two_candidates():
    sheets = [_sheet(1, [
        {"tag": "Q1", "device_class": "mccb", "manufacturer": "ABB", "model": "XT1C", "rating": "3X40A", "poles": "3"},
        {"tag": "Q2", "device_class": "mccb", "manufacturer": "ABB", "model": "XT2N", "rating": "3X40A", "poles": "3"},
        {"tag": "Q3", "device_class": "mccb", "manufacturer": "ABB", "rating": "3X40A", "poles": "3"},
    ])]
    assert len(build_bom(sheets)) == 3


def test_only_the_audited_incomer_is_the_board_main():
    sheets = [_sheet(2, [
        {"tag": "QU1", "device_class": "mccb", "manufacturer": "ABB", "model": "XT3", "rating": "3X160A", "poles": "3"},
        {"tag": "QU497", "device_class": "mccb", "manufacturer": "ABB", "model": "XT1C", "rating": "3X32A", "poles": "3"},
        {"tag": "QALU", "device_class": "motor_protection", "manufacturer": "ABB", "model": "MS116", "rating": "4A"},
    ])]
    draft = board_draft(_run(sheets, [("main_breaker_reference", "QU1")]))
    mains = [c for c in draft["components"] if c["isMainBreaker"]]
    assert [c["reference"] for c in mains] == ["QU1"]
    assert all(c["supplyRole"] == "downstream" for c in draft["components"] if not c["isMainBreaker"])
    assert draft["board"]["mainBreakerModel"] == "XT3"
    assert draft["board"]["mainBreakerAmpere"] == "3X160A"


def test_terminals_are_not_parts_and_lines_are_named_by_what_they_are():
    sheets = [_sheet(3, [
        {"tag": "XU497", "device_class": "terminal"},
        {"tag": "F01", "device_class": "mcb", "rating": "3X40A", "poles": "3", "curve": "C"},
    ])]
    components = board_draft(_run(sheets))["components"]
    assert [c["type"] for c in components] == ["MCB"]
    assert components[0]["rawText"] == "MCB 3X40A 3P C"


def test_the_header_comes_from_the_title_block_in_the_right_fields():
    title = TitleBlock(
        project="אגרובנק TOWER B", panel="E2 לוח חשמל קומה 21", client='ס.מ.ע עבודות חשמל בע"מ',
        panel_builder='כיתאן אלקטריק בע"מ', drawing_no="4382.26-8",
    )
    draft = board_draft(_run([_sheet(1, [], title)], [("enclosure_manufacturer", "פח-תמחש T4P-M")]))
    board = draft["board"]
    assert board["project"] == "אגרובנק TOWER B"
    assert board["name"] == "E2 לוח חשמל קומה 21"
    assert board["customer"] == 'ס.מ.ע עבודות חשמל בע"מ'
    assert board["number"] == "4382.26-8"
    assert board["manufacturer"] == "פח-תמחש T4P-M"
    assert board["manufacturerRole"] == "enclosure"
    assert board["panelBuilder"] == 'כיתאן אלקטריק בע"מ'


def test_a_device_drawn_on_two_sheets_counts_once_at_its_most_detailed():
    sheets = [
        _sheet(2, [{"tag": "QU1", "device_class": "mccb", "rating": "3X100A"}]),
        _sheet(3, [{"tag": "QU1", "device_class": "mccb", "manufacturer": "ABB", "model": "XT1C",
                    "rating": "3X100A", "poles": "3"}]),
        _sheet(4, [{"tag": "FAKU", "device_class": "spd"}, {"tag": "FAKU", "device_class": "spd"}]),
        _sheet(5, [{"tag": "FAKU", "device_class": "spd"}]),
    ]
    bom = build_bom(sheets)
    mccb = next(line for line in bom if line.device_class == "mccb")
    assert (mccb.qty, mccb.model, mccb.breakdown) == (1, "XT1C", {"03": 1})
    assert next(line for line in bom if line.device_class == "spd").qty == 1


def test_one_tag_drawn_with_contradicting_specs_is_kept_and_flagged():
    sheets = [
        _sheet(2, [{"tag": "Q1", "device_class": "mccb", "rating": "3X40A"}]),
        _sheet(3, [{"tag": "Q1", "device_class": "mccb", "rating": "3X100A"}]),
    ]
    bom = build_bom(sheets)
    assert sum(line.qty for line in bom) == 2
    assert all("duplicate_tag" in line.flags and line.needs_human for line in bom)


# ------------------------------------------------ parts list and data table

from scheme_extractor.models.schema import BoardDatum, EquipmentListItem


def _listed(page, devices, items=(), data=()):
    sheet = _sheet(page, devices)
    sheet.equipment_list = [EquipmentListItem(**i) for i in items]
    sheet.board_data = [BoardDatum(**d) for d in data]
    return sheet


PARTS_SHEET = [
    {"tag_pattern": "F...", "device_class": "mcb", "manufacturer": "ABB", "model": "S201M",
     "description_he": "מאמ״תים (1P) 10KA"},
    {"tag_pattern": "F...", "device_class": "mcb", "manufacturer": "ABB", "model": "S203M",
     "description_he": "מאמ״תים (3P) 10KA"},
]


def test_a_parts_list_names_the_model_the_single_lines_leave_out():
    sheets = [
        _listed(15, [{"tag": "FU461", "device_class": "mcb", "manufacturer": "ABB", "rating": "32A"},
                     {"tag": "F313", "device_class": "mcb", "manufacturer": "ABB", "rating": "3X16A"}]),
        _listed(35, [], PARTS_SHEET),
    ]
    bom = {line.tags[0]: line for line in build_bom(sheets)}
    assert bom["FU461"].model == "S201M"
    assert bom["F313"].model == "S203M"
    assert "model_from_equipment_list" in bom["FU461"].flags


def test_a_parts_list_row_is_never_counted_as_a_device():
    sheets = [_listed(35, [{"tag": "F...", "device_class": "mcb", "model": "S201M"},
                           {"tag": "Q..", "device_class": "mccb", "model": "XT1C"}])]
    assert build_bom(sheets) == []


def test_the_board_data_table_fills_the_enclosure_fields():
    data = [
        {"label_he": "ייצרן מקורי", "value": "פח-תמחש T4P-M"},
        {"label_he": "דרגת הגנה", "symbol": "IP", "value": "IP-20"},
        {"label_he": "מידור (FORM)", "symbol": "FORM", "value": "FORM-1"},
        {"label_he": "מידה כללית HXWXD", "symbol": "mm", "value": "1950X3600X500"},
        {"label_he": "שיטת הארקה", "value": "TNCS"},
    ]
    board = board_draft(_run([_listed(1, [], data=data)]))["board"]
    assert board["manufacturer"] == "פח-תמחש T4P-M"
    assert board["manufacturerRole"] == "enclosure"
    assert (board["ipRating"], board["formSeparation"], board["enclosureSize"], board["earthingSystem"]) == (
        "IP-20", "FORM-1", "1950X3600X500", "TNCS")


def test_hebrew_abbreviations_inside_stringified_json_are_repaired():
    # Sheet 02 of 4382.26-8, as the model sent it.
    raw = '[{"tag": "QALE", "device_class": "motor_protection", "notes_he": "פ"י"ס"ק"ם"}]'
    sheet = SheetExtraction.model_validate({"sheet": {"page_number": 2, "sheet_label": "02"}, "devices": raw})
    assert sheet.devices[0].notes_he == "פ״י״ס״ק״ם"


def test_a_parts_list_row_names_only_the_tags_it_patterns():
    items = [{"tag_pattern": "IRL", "device_class": "relay", "manufacturer": "GIC", "model": "IRLA04S"},
             {"tag_pattern": "KSR..", "device_class": "switch", "manufacturer": "HAGER", "model": "EPN510"}]
    sheets = [
        _listed(20, [{"tag": "R211", "device_class": "relay"}, {"tag": "SPU", "device_class": "switch"}]),
        _listed(35, [], items),
    ]
    assert all(line.model is None for line in build_bom(sheets))


def test_one_motor_breaker_is_one_line_whatever_dash_or_class_a_sheet_used():
    items = [{"tag_pattern": "QA..", "device_class": "motor_protection", "manufacturer": "ABB", "model": "MS116"}]
    sheets = [
        _listed(21, [{"tag": "QALU", "device_class": "motor_protection", "manufacturer": "ABB", "model": "MS116", "rating": "2.5-4A"},
                     {"tag": "QA0", "device_class": "mccb", "manufacturer": "ABB", "model": "MS116", "rating": "2.5–4A"}]),
        _listed(35, [], items),
    ]
    bom = build_bom(sheets)
    assert [(line.device_class, line.qty) for line in bom] == [("motor_protection", 2)]


def test_a_bare_layout_range_adds_no_device_the_single_lines_do_not_draw():
    sheets = [
        _sheet(29, [{"tag": "F361", "device_class": "mcb", "manufacturer": "ABB", "rating": "16A"},
                    {"tag": "F381", "device_class": "mcb", "manufacturer": "ABB", "rating": "16A"}]),
        _sheet(33, [{"tag": "F361-F381", "device_class": "mcb", "qty": 21,
                     "tags_expanded": [f"F{n}" for n in range(361, 382)]}]),
    ]
    assert sorted(t for line in build_bom(sheets) for t in line.tags) == ["F361", "F381"]


def test_plc_modules_named_differently_per_sheet_are_one_module_per_slot():
    sheets = [
        _sheet(18, [{"tag": "PLC-AI8", "device_class": "plc_module", "model": "TM3AI8"},
                    {"tag": "PLC-DI32", "device_class": "plc_module", "model": "TM3DI32K"}]),
        _sheet(19, [{"tag": "PLC-SLOT-1", "device_class": "plc_module", "model": "TM3DI32K"}]),
        _sheet(23, [{"tag": "SLOT-4-TM3AI8", "device_class": "plc_module", "model": "TM3AI8"}]),
    ]
    assert {line.model: line.qty for line in build_bom(sheets)} == {"TM3AI8": 1, "TM3DI32K": 1}


def test_a_bare_mention_of_another_class_joins_the_specified_device():
    sheets = [
        _sheet(28, [{"tag": "F02", "device_class": "mccb", "rating": "3X40A", "poles": "3"}]),
        _sheet(33, [{"tag": "F02", "device_class": "mcb"}]),
        _sheet(6, [{"tag": "QC361", "device_class": "relay"}]),
        _sheet(10, [{"tag": "QC361", "device_class": "contactor", "manufacturer": "ABB", "model": "AF38"}]),
    ]
    bom = build_bom(sheets)
    assert sorted((line.device_class, line.qty) for line in bom) == [("contactor", 1), ("mccb", 1)]


def test_a_breaker_with_a_trip_curve_is_an_mcb_whatever_class_it_was_read_as():
    sheets = [_sheet(28, [
        {"tag": "F01", "device_class": "mcb", "rating": "3X40A", "poles": "3", "curve": "C"},
        {"tag": "F02", "device_class": "mccb", "rating": "3X40A", "poles": "3", "curve": "C"},
        {"tag": "F03", "device_class": "fuse", "rating": "3X40A", "poles": "3", "curve": "C"},
    ])]
    assert [(line.device_class, line.qty) for line in build_bom(sheets)] == [("mcb", 3)]


def test_lugs_and_letter_o_misreads_are_not_devices():
    sheets = [
        _sheet(2, [{"tag": "SHE", "device_class": "switch", "rating": "4x250A"},
                   {"tag": "SHE/1", "device_class": "switch"}, {"tag": "SHE/2", "device_class": "switch"}]),
        _sheet(24, [{"tag": "Q0", "device_class": "mccb", "model": "XT3N", "rating": "3X250A"}]),
        _sheet(33, [{"tag": "QO", "device_class": "switch"}]),
    ]
    assert sorted(t for line in build_bom(sheets) for t in line.tags) == ["Q0", "SHE"]


def test_a_module_named_short_on_one_sheet_is_the_full_model_on_another():
    sheets = [
        _sheet(18, [{"tag": "TM3DQ16", "device_class": "plc_module", "model": "TM3DQ16"}]),
        _sheet(22, [{"tag": "SLOT3", "device_class": "plc_module", "model": "TM3DQ16R"}]),
    ]
    assert [(line.model, line.qty) for line in build_bom(sheets)] == [("TM3DQ16R", 1)]


def test_a_model_label_read_as_a_tag_is_not_a_device():
    sheets = [
        _sheet(10, [{"tag": "QC211", "device_class": "contactor", "manufacturer": "ABB", "model": "AF38"}]),
        _sheet(30, [{"tag": "AF38", "device_class": "switch", "manufacturer": "ABB"}]),
    ]
    assert [t for line in build_bom(sheets) for t in line.tags] == ["QC211"]


def test_a_module_and_its_cable_sharing_a_slot_tag_stay_two_parts():
    sheets = [
        _sheet(19, [{"tag": "SLOT1", "device_class": "plc_module", "model": "TM3DI32K"}]),
        _sheet(20, [{"tag": "SLOT1", "device_class": "plc_module", "model": "TWDFCW30K"}]),
        _sheet(18, [{"tag": "PLC-DI32", "device_class": "plc_module", "model": "TM3DI32K"}]),
    ]
    assert sorted((line.model, line.qty, tuple(line.tags)) for line in build_bom(sheets)) == [
        ("TM3DI32K", 1, ("TM3DI32K SLOT1",)), ("TWDFCW30K", 1, ("TWDFCW30K SLOT1",))]
