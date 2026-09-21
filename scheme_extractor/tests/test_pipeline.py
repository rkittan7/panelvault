"""The whole tunnel, end to end, with the model stubbed out.

Everything these cover is the pipeline's own behaviour: which stages fire,
what they hand each other, and whether the arithmetic and the flags survive
the trip. Reading ability is measured separately, by the golden harness.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from scheme_extractor.config import Config
from scheme_extractor.models.schema import CircuitRow, Device, Sheet, SheetExtraction, ZoomResult
from scheme_extractor.pipeline import run
from scheme_extractor.stages import reconcile, zoom
from scheme_extractor.stages.probe import probe
from scheme_extractor.stages.textlayer import page_tokens
from scheme_extractor.tests.fake_client import FakeClient

REFERENCE = Path(os.environ.get("SCHEME_REFERENCE_PDF", ""))
needs_reference = pytest.mark.skipif(
    not REFERENCE.is_file(), reason="Set SCHEME_REFERENCE_PDF to the reference drawing."
)


@pytest.fixture(scope="module")
def cache_dir(tmp_path_factory):
    """One render cache for the whole module.

    Rendering the reference set is the slow part and it does not depend on
    anything these tests vary, so it happens once. That it can happen once is
    itself the §11.8 promise working.
    """
    return tmp_path_factory.mktemp("pipeline-cache")


def sheet_answer(page: int, label: str, devices: list[dict], circuits: list[dict]) -> dict:
    return {
        "sheet": {"page_number": page, "sheet_label": label, "title_block": {
            "project": "TOWER B", "panel": "E2", "panel_builder": None, "client": None,
            "consultant": None, "drawing_no": "4382.26-8", "drawn_by": None,
            "revision_dates": [], "status": "AS-MADE", "total_pages": "35"}},
        "busbars": [], "devices": devices, "circuit_table": circuits,
        "io_points": [], "cross_references": [], "gaps": [], "anomalies": [],
        "needs_zoom_regions": [],
    }


@needs_reference
def test_a_whole_set_runs_and_rolls_up(cache_dir):
    config = Config(cache_dir=cache_dir)
    devices = [{
        "tag": "F361-F369", "tags_expanded": [f"F36{n}" for n in range(1, 10)], "qty": 9,
        "device_class": "mcb", "description_he": None, "manufacturer": "ABB", "model": "S201M",
        "rating": "16A", "setting": None, "curve": "C", "poles": "1P",
        "fed_from": "WE", "feeds": None, "aux_contacts": [], "notes_he": None,
    }]
    circuits = [{
        "terminal": "X361", "protective_device": "F361", "destination_he": 'ח. תקשורת "ש" 2kW',
        "span_terminals": ["X361", "X362"], "span_confidence": "high",
        "cable": "3x2.5N2XY", "inc": "12.8A", "is_spare": False, "needs_zoom": False,
    }]
    answers = {"sheet-006": sheet_answer(6, "06", devices, circuits)}
    client = FakeClient(config, answers)

    result = run(REFERENCE, config, client=client, job_id="job_test")

    assert len(result.sheets) == 35
    assert result.job_id == "job_test"
    assert result.source_hash

    line = next(l for l in result.bom if l.model == "S201M")
    assert line.qty == 9
    assert line.breakdown == {"06": 9}
    # §11.6 — the per-sheet breakdown sums to the quantity, on every line.
    assert all(sum(l.breakdown.values()) == l.qty for l in result.bom)

    # A merged span becomes one row per terminal, both carrying the phrase.
    span = [r for r in result.circuits if r.terminal in {"X361", "X362"}]
    assert len(span) == 2
    assert all(r.destination_he == 'ח. תקשורת "ש" 2kW' for r in span)
    assert result.counts.total == 2


@needs_reference
def test_the_system_prompt_is_identical_on_every_sheet(cache_dir):
    config = Config(cache_dir=cache_dir)
    client = FakeClient(config)
    run(REFERENCE, config, client=client, job_id="job_cache")
    systems = {c.system for c in client.calls if c.tool_name == "sheet_extraction"}
    # The cache breakpoint sits on the system prompt and the tool schema. If
    # anything sheet-specific leaks in there, nothing is ever cached and the
    # run costs several times what it should.
    assert len(systems) == 1


@needs_reference
def test_a_sheet_that_fails_does_not_end_the_run(cache_dir):
    config = Config(cache_dir=cache_dir)
    client = FakeClient(config, {"sheet-006": {"sheet": {"nope": True}}})
    result = run(REFERENCE, config, client=client, job_id="job_partial")

    assert len(result.sheets) == 35
    assert any("could not be read" in w for w in result.warnings)
    broken = next(s for s in result.sheets if s.sheet.page_number == 6)
    assert broken.notes and "Extraction failed" in broken.notes[0]


@needs_reference
def test_the_run_says_the_text_layer_could_not_verify_anything(cache_dir):
    config = Config(cache_dir=cache_dir)
    result = run(REFERENCE, config, client=FakeClient(config), job_id="job_cov")
    assert any("could not be reconciled" in note for note in result.notes)


def test_zoom_overwrites_a_span_and_recomputes_spare():
    sheet = SheetExtraction(
        sheet=Sheet(page_number=6, sheet_label="06"),
        circuit_table=[
            CircuitRow(terminal="X11", destination_he="תריס", span_terminals=["X11"], span_confidence="medium"),
            CircuitRow(terminal="X12", destination_he=None, span_confidence="low"),
            CircuitRow(terminal="X15", destination_he=None, span_confidence="low"),
        ],
    )
    # The failure the reference set actually produced: X11-X14 read as
    # X11-X13 plus a spare.
    zoom.apply(sheet, ZoomResult.model_validate({
        "terminals": ["X11", "X12", "X13", "X14", "X15"],
        "cells": [
            {"span_terminals": ["X11", "X12", "X13", "X14"],
             "destination_he": "תריס חשמלי בכניסה", "confidence": "high"},
            {"span_terminals": ["X15"], "destination_he": "שמור", "confidence": "high"},
        ],
        "cable_row": {"X11": "5x2.5N2XY"}, "inc_row": {"X11": "12.8A"}, "unresolved": [],
    }))

    rows = {r.terminal: r for r in sheet.circuit_table}
    assert [rows[t].destination_he for t in ("X11", "X12", "X13", "X14")] == ["תריס חשמלי בכניסה"] * 4
    assert all(rows[t].is_spare is False for t in ("X11", "X12", "X13", "X14"))
    # is_spare is recomputed from the printed word, not carried from the model.
    assert rows["X15"].is_spare is True
    assert rows["X11"].cable == "5x2.5N2XY"


def test_unresolved_terminals_go_to_a_human():
    sheet = SheetExtraction(
        sheet=Sheet(page_number=6, sheet_label="06"),
        circuit_table=[CircuitRow(terminal="X21", span_confidence="low")],
    )
    zoom.apply(sheet, ZoomResult.model_validate(
        {"terminals": ["X21"], "cells": [], "cable_row": {}, "inc_row": {}, "unresolved": ["X21"]}
    ))
    assert sheet.circuit_table[0].needs_human is True
    assert "span_unresolved" in sheet.circuit_table[0].flags


@needs_reference
def test_reconcile_distinguishes_contradicted_from_unverifiable():
    meta = probe(REFERENCE)
    tokens = page_tokens(REFERENCE, 6, page_size=meta.page_size, rotation=meta.rotation, dpi=220)
    sheet = SheetExtraction(
        sheet=Sheet(page_number=6, sheet_label="06"),
        devices=[Device(tag="F361", tags_expanded=["F361"], qty=1, device_class="mcb", rating="16A")],
    )
    reconcile.reconcile(sheet, tokens, text_coverage=meta.text_coverage)

    device = sheet.devices[0]
    # This sheet's text layer carries no drawing text, so the tag is
    # unverifiable — which is not the same claim as "wrong", and must not
    # send an otherwise sound reading to a human.
    assert "tag_unverifiable" in device.flags
    assert "tag_not_in_text_layer" not in device.flags
    assert device.needs_human is False


@needs_reference
def test_a_busbar_caption_does_not_make_a_frame_only_sheet_verifiable():
    # Sheet 17's text layer holds `L1,L2,L3/N/PE`, `3x400A`, `3X160A` and
    # `SLOT2` — five tag-shaped tokens and no device tag. The set is
    # frame-only, so its breaker is unverifiable, not contradicted.
    meta = probe(REFERENCE)
    assert meta.text_coverage == "frame"
    tokens = page_tokens(REFERENCE, 17, page_size=meta.page_size, rotation=meta.rotation, dpi=220)
    sheet = SheetExtraction(
        sheet=Sheet(page_number=17, sheet_label="17"),
        devices=[Device(tag="QU497", device_class="mccb", rating="3X32A", model="XT1C")],
    )
    reconcile.reconcile(sheet, tokens, text_coverage=meta.text_coverage)
    assert sheet.devices[0].needs_human is False
    assert "tag_not_in_text_layer" not in sheet.devices[0].flags
