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


def test_of_two_listed_families_the_one_naming_the_current_is_chosen():
    items = [{"tag_pattern": "Q..", "device_class": "mccb", "manufacturer": "ABB", "model": "XT3N 250 36kA"},
             {"tag_pattern": "Q..", "device_class": "mccb", "manufacturer": "ABB", "model": "XT1C 160 25kA"}]
    sheets = [_listed(24, [{"tag": "Q0", "device_class": "mccb", "rating": "3X250A", "poles": "3"}]),
              _listed(35, [], items)]
    assert build_bom(sheets)[0].model == "XT3N 250 36kA"


def test_a_slot_written_into_the_model_is_stripped():
    sheets = [_sheet(23, [{"tag": "SLOT-4-TM3AI8", "device_class": "plc_module", "model": "SLOT-4-TM3AI8"}]),
              _sheet(18, [{"tag": "PLC-AI8", "device_class": "plc_module", "model": "TM3AI8"}])]
    assert [(line.model, line.qty) for line in build_bom(sheets)] == [("TM3AI8", 1)]


def test_a_placeholder_in_the_parts_list_is_not_a_model():
    items = [{"tag_pattern": "PF1...", "device_class": "lamp", "manufacturer": "SALZER", "model": "N.D.S"}]
    sheets = [_listed(2, [{"tag": "PF1E", "device_class": "lamp"}]), _listed(35, [], items)]
    assert build_bom(sheets)[0].model is None


def test_poles_printed_in_the_rating_column_still_pick_the_family():
    items = [{"tag_pattern": "F...", "device_class": "mcb", "manufacturer": "ABB", "model": "S201M", "rating": "(1P) 10KA"},
             {"tag_pattern": "F...", "device_class": "mcb", "manufacturer": "ABB", "model": "S203M", "rating": "(3P) 10KA"}]
    sheets = [_listed(29, [{"tag": "F361", "device_class": "mcb", "manufacturer": "ABB", "rating": "16A"},
                           {"tag": "F391", "device_class": "mcb", "manufacturer": "ABB", "rating": "3X16A"}]),
              _listed(35, [], items)]
    assert {line.tags[0]: line.model for line in build_bom(sheets)} == {"F361": "S201M", "F391": "S203M"}


def test_a_plc_module_named_only_by_its_tag_gets_its_model():
    sheets = [_sheet(18, [{"tag": "TM3DI16", "device_class": "plc_module"},
                          {"tag": "SLOT-1TM3DI32K", "device_class": "plc_module"}]),
              _sheet(19, [{"tag": "SLOT1", "device_class": "plc_module", "model": "TM3DI32K"}])]
    assert sorted((line.model, line.qty) for line in build_bom(sheets)) == [("TM3DI16", 1), ("TM3DI32K", 1)]


def test_bare_labels_seen_only_on_a_layout_sheet_are_not_devices():
    layout = [{"tag": f"F{n}", "device_class": "mcb"} for n in range(30)] + [
        {"tag": "QU11", "device_class": "mccb"}, {"tag": "SPU", "device_class": "switch"}]
    sheets = [
        _sheet(34, layout),
        _sheet(11, [{"tag": "SPU", "device_class": "switch"}] + [
            {"tag": f"F{n}", "device_class": "mcb", "rating": "16A"} for n in range(30)]),
    ]
    tags = {t for line in build_bom(sheets) for t in line.tags}
    assert "QU11" not in tags and "SPU" in tags and "F0" in tags


def test_a_plc_slot_or_channel_reference_is_not_a_module():
    sheets = [_sheet(9, [{"tag": "SLOT1", "device_class": "plc_module"},
                         {"tag": "DI6", "device_class": "plc_module"}])]
    assert build_bom(sheets) == []


def test_an_omitted_confidence_on_a_single_column_is_not_a_zoom():
    from scheme_extractor.models.schema import CircuitRow
    assert CircuitRow.model_validate({"terminal": "XU471"}).span_confidence == "high"
    merged = CircuitRow.model_validate({"terminal": "XU461", "span_terminals": ["XU461", "XU462"]})
    assert merged.span_confidence == "low"


def test_a_merged_spare_cell_gives_its_word_to_every_column_it_covers():
    sheet = SheetExtraction.model_validate({"sheet": {"page_number": 24, "sheet_label": "24"}, "circuit_table": [
        {"terminal": "X381", "destination_he": "שמורים", "is_spare": True, "span_terminals": ["X381", "X382", "X383"]},
        {"terminal": "X382", "destination_he": "", "is_spare": True},
        {"terminal": "X399", "is_spare": True},
    ]})
    rows = {row.terminal: row for row in sheet.circuit_table}
    assert rows["X382"].destination_he == "שמורים" and rows["X382"].is_spare
    assert rows["X399"].is_spare is False


def test_a_sheet_keeps_everything_but_the_rows_that_break_the_contract():
    from scheme_extractor.stages.extract import salvage
    payload = {"sheet": {"page_number": 24, "sheet_label": "24"},
               "devices": [{"tag": "Q0", "device_class": "mccb", "model": "XT3N"},
                           {"tag": "BAD", "device_class": "not-a-class"}],
               "circuit_table": [{"terminal": "X381"}]}
    sheet, dropped = salvage(payload)
    assert [d.tag for d in sheet.devices] == ["Q0"] and dropped == ["devices entry 1"]


def test_a_stray_field_costs_the_field_not_the_row():
    from scheme_extractor.stages.extract import salvage
    payload = {"sheet": {"page_number": 31, "sheet_label": "31"},
               "circuit_table": [{"terminal": "X181", "destination_he": "שמור", "colour": "red"},
                                 {"terminal": "X182", "setting": "12.8A"}]}
    sheet, dropped = salvage(payload)
    assert [(r.terminal, r.inc) for r in sheet.circuit_table] == [("X181", None), ("X182", "12.8A")]
    assert dropped == ["colour on circuit table entry 0"]
