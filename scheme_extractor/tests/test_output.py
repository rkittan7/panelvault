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
