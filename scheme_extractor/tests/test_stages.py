"""Stages 0-2 against the real reference set.

These run without an API key and without spending anything, which is the
point: the geometry either works on the customer's own drawings or it does
not, and that is knowable before a single token is bought.

Set SCHEME_REFERENCE_PDF to the reference drawing to run them.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest
from PIL import Image

from scheme_extractor.cache import ArtifactCache, source_hash
from scheme_extractor.config import Config, RenderSettings
from scheme_extractor.models.client import CostLedger, Usage
from scheme_extractor.stages.probe import probe
from scheme_extractor.stages.render import chunk_width, page_regions
from scheme_extractor.stages.textlayer import AnchorError, page_tokens

REFERENCE = Path(os.environ.get("SCHEME_REFERENCE_PDF", ""))
needs_reference = pytest.mark.skipif(
    not REFERENCE.is_file(), reason="Set SCHEME_REFERENCE_PDF to the reference drawing."
)


@pytest.fixture(scope="session")
def probed():
    return probe(REFERENCE)


@pytest.fixture(scope="session")
def cache(tmp_path_factory):
    return ArtifactCache(tmp_path_factory.mktemp("artifacts"), source_hash(REFERENCE))


@needs_reference
def test_probe_survives_quartz_syntax_errors(probed):
    # Every poppler tool prints pages of `Syntax Error` on these files and
    # extracts them correctly anyway. A probe that treated stderr as failure
    # would reject the entire reference set.
    assert probed.pages == 35
    assert probed.page_size == (595.0, 842.0)
    assert probed.rotation == 270
    assert probed.has_text_layer


@needs_reference
def test_text_layer_carries_the_frame_and_not_the_drawing(probed):
    # The premise this pipeline had to be rebuilt around: `pdftotext` recovers
    # the sheet frame and the title block, and none of the device tags. If a
    # future export changes that, this test flips and stage 5 can start
    # reconciling for real.
    assert probed.text_coverage == "frame"
    assert probed.chars_per_page < 400
    assert not probed.hebrew_recoverable


@needs_reference
def test_every_page_transform_verifies_against_an_anchor(probed):
    for page in range(1, probed.pages + 1):
        tokens = page_tokens(
            REFERENCE, page, page_size=probed.page_size, rotation=probed.rotation, dpi=220
        )
        label = tokens.anchors["sheet_label"]
        assert label is not None, f"page {page} has no sheet label to verify against"
        assert label.cx < tokens.width * 0.15
        assert label.cy > tokens.height * 0.90


@needs_reference
def test_rotation_is_applied_before_any_bbox_maths(probed):
    tokens = page_tokens(
        REFERENCE, 6, page_size=probed.page_size, rotation=probed.rotation, dpi=220
    )
    # A 595x842 portrait page with Page rot 270 renders landscape. Tokens that
    # came back in portrait space would put the title block off the image.
    assert tokens.width > tokens.height
    assert all(t.x1 <= tokens.width + 2 for t in tokens.tokens)
    assert all(t.y1 <= tokens.height + 2 for t in tokens.tokens)


@needs_reference
def test_table_detection_matches_the_sheets_that_have_tables(probed, cache):
    settings = RenderSettings()
    kinds = {}
    for page in range(1, probed.pages + 1):
        tokens = page_tokens(
            REFERENCE, page, page_size=probed.page_size, rotation=probed.rotation, dpi=220
        )
        kinds[page] = page_regions(REFERENCE, tokens, cache, settings).layout_kind

    with_table = {p for p, kind in kinds.items() if kind == "table"}
    # Single-line sheets carry an outgoing table; control schematics, the PLC
    # I/O sheets, the elevations and the equipment list do not.
    assert with_table == {3, 4, 5, 6, 7, 8, 12, 13, 14, 15, 16, 17, 24, 25, 26, 27, 28, 29, 30, 31}
    assert kinds[35] == "no_table"


@needs_reference
def test_narrow_table_is_not_cropped_to_a_percentage(probed, cache):
    # Sheet 17 carries a single-column table roughly a fifth of the page wide.
    # A fixed-percentage crop tuned on sheet 6 would cut it to pieces.
    tokens = page_tokens(
        REFERENCE, 17, page_size=probed.page_size, rotation=probed.rotation, dpi=220
    )
    band = page_regions(REFERENCE, tokens, cache, RenderSettings()).regions["table_band"]
    width = band.box[2] - band.box[0]
    assert 400 < width < 1400, width
    assert len(band.chunks) == 1


@needs_reference
def test_table_band_chunks_overlap(probed, cache):
    settings = RenderSettings()
    tokens = page_tokens(
        REFERENCE, 6, page_size=probed.page_size, rotation=probed.rotation, dpi=220
    )
    band = page_regions(REFERENCE, tokens, cache, settings).regions["table_band"]
    assert len(band.chunks) > 1
    for chunk in band.chunks:
        assert Image.open(chunk).size[0] <= settings.chunk_width
    total = sum(Image.open(c).size[0] for c in band.chunks)
    span = band.box[2] - band.box[0]
    # Overlap means the chunk widths must exceed the band they cover.
    assert total > span


@needs_reference
def test_second_run_renders_nothing(probed, cache, tmp_path):
    settings = RenderSettings()
    warm = ArtifactCache(tmp_path / "warm", source_hash(REFERENCE))
    tokens = page_tokens(
        REFERENCE, 6, page_size=probed.page_size, rotation=probed.rotation, dpi=220
    )
    page_regions(REFERENCE, tokens, warm, settings)
    warm.hits = warm.misses = 0
    page_regions(REFERENCE, tokens, warm, settings)
    assert warm.misses == 0
    assert warm.hits > 0


def test_chunking_splits_wide_strips_with_overlap(tmp_path):
    settings = RenderSettings()
    image = Image.new("RGB", (4000, 400), "white")
    paths = chunk_width(image, settings, tmp_path / "band")
    # step is chunk_width - overlap, so 4000px needs three passes, not four.
    assert len(paths) == 3
    widths = [Image.open(p).size[0] for p in paths]
    assert max(widths) <= settings.chunk_width
    assert sum(widths) > 4000


def test_unpriced_model_is_never_free():
    # A model missing from the price table must cost the most, not nothing:
    # a run that silently reports $0.00 is a broken audit trail.
    ledger = CostLedger(Config())
    ledger.record(Usage("audit", "some-unreleased-model", input_tokens=1_000_000))
    assert ledger.summary()["total_usd"] >= 5.0


def test_batch_halves_the_bill():
    config = Config()
    plain = CostLedger(config)
    plain.record(Usage("extract", "claude-haiku-4-5-20251001", input_tokens=1_000_000))
    batched = CostLedger(config)
    batched.record(Usage("extract", "claude-haiku-4-5-20251001", input_tokens=1_000_000, batched=True))
    assert batched.summary()["total_usd"] == pytest.approx(plain.summary()["total_usd"] / 2)


def test_expensive_run_warns():
    config = Config()
    ledger = CostLedger(config)
    ledger.record(Usage("extract", "claude-opus-5", input_tokens=1_000_000))
    assert any("above the" in w for w in ledger.summary()["warnings"])


def test_model_is_overridable_from_the_request_body():
    # §11.9: swapping any stage's model is a config change only.
    config = Config().with_overrides({"models": {"audit": "claude-sonnet-5"}})
    assert config.models["audit"].model == "claude-sonnet-5"
    assert config.models["extract"].model.startswith("claude-haiku")


# ------------------------------------------------ final protective devices
# Shapes taken from 4382.26-8, where counting every breaker flagged sheets
# that were read correctly.

from scheme_extractor.models.schema import CircuitRow, Device, Sheet, SheetExtraction
from scheme_extractor.stages.reconcile import final_protective_devices


def _sheet(devices, terminals):
    return SheetExtraction(
        sheet=Sheet(page_number=1, sheet_label="01"),
        devices=[Device(**d) for d in devices],
        circuit_table=[CircuitRow(terminal=t) for t in terminals],
    )


def test_series_mcb_and_rcd_count_once_per_circuit():
    # Sheet 15: nine lines, each an MCB with its own RCD beneath it.
    devices = []
    for n in range(9):
        devices.append({"tag": f"FU{n}", "device_class": "mcb"})
        devices.append({"tag": f"FB0U{n}", "device_class": "rcd", "fed_from": f"FU{n}"})
    assert final_protective_devices(_sheet(devices, [f"XU{n}" for n in range(9)])) == 9


def test_feeder_and_group_rcds_have_no_column():
    # Sheet 12: F0U1 feeds three RCDs, each over three MCBs; three more MCBs
    # hang straight off F0U1's busbar.
    devices = [{"tag": "F0U1", "device_class": "mccb"}]
    for g in range(3):
        devices.append({"tag": f"FB0U1.{g}", "device_class": "rcd", "fed_from": "F0U1"})
        for m in range(3):
            devices.append({"tag": f"FU40{g}{m}", "device_class": "mcb", "fed_from": f"FB0U1.{g}"})
    devices.append({
        "tag": "FU410.1-.3", "device_class": "mcb", "fed_from": "F0U1",
        "qty": 3, "tags_expanded": ["FU410.1", "FU10.2", "FU410.3"],
    })
    assert final_protective_devices(_sheet(devices, [])) == 12


def test_a_device_listed_twice_by_overlapping_pieces_counts_once():
    devices = [
        {"tag": "F05", "device_class": "mccb"},
        {"tag": "F181", "device_class": "mcb", "fed_from": "F05"},
        {"tag": "F181", "device_class": "mcb", "fed_from": "F05"},
    ]
    assert final_protective_devices(_sheet(devices, [])) == 1


def test_no_feed_links_means_no_verdict():
    devices = [{"tag": "F1", "device_class": "mcb"}, {"tag": "FB1", "device_class": "rcd"}]
    assert final_protective_devices(_sheet(devices, ["X1"])) is None


def test_accessories_on_a_breaker_do_not_make_it_upstream():
    # Sheet 17: QU497 carries a shunt-trip coil and an auxiliary contact,
    # both fed from it. It is still the one final device for XU497.
    # A second line, an MCB over its own RCD, gives the sheet a feed link.
    devices = [
        {"tag": "QU497", "device_class": "mccb"},
        {"tag": "TC-QU497", "device_class": "shunt_trip", "fed_from": "QU497"},
        {"tag": "SLOT2", "device_class": "relay", "fed_from": "QU497"},
        {"tag": "F189", "device_class": "mcb"},
        {"tag": "FB0189", "device_class": "rcd", "fed_from": "F189"},
        {"tag": "AF16", "device_class": "relay", "fed_from": "FB0189"},
    ]
    assert final_protective_devices(_sheet(devices, ["XU497", "X189"])) == 2
