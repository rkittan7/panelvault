"""A stand-in for the model, so the tunnel can be exercised without spending.

It answers every call with a canned record built from the call's own images,
which is enough to prove that the stages hand off correctly, that stage 4
fires where it should, and that the rollup arithmetic lands — none of which
is about the model's reading ability.
"""

from __future__ import annotations

import re
from typing import Any, Sequence

from ..models.client import Call, CostLedger, Usage
from ..config import Config


class FakeClient:
    def __init__(self, config: Config, answers: dict[str, dict[str, Any]] | None = None) -> None:
        self.config = config
        self.ledger = CostLedger(config)
        self.answers = answers or {}
        self.calls: list[Call] = []

    def _usage(self, stage: str, batched: bool = False) -> Usage:
        usage = Usage(stage, self.config.models[stage].model, input_tokens=1000, output_tokens=200, batched=batched)
        self.ledger.record(usage)
        return usage

    def complete(self, stage: str, call: Call) -> tuple[dict[str, Any], Usage]:
        self.calls.append(call)
        return self.answers.get(call.key, self._default(stage, call)), self._usage(stage)

    def complete_many(self, stage: str, calls: Sequence[Call], **_: Any) -> dict[str, tuple[dict[str, Any] | None, Usage]]:
        return {
            call.key: (self.answers.get(call.key, self._default(stage, call)), self._usage(stage, batched=True))
            for call in (self.calls.extend(calls) or calls)
        }

    def revalidate(self, stage: str, call: Call, error: str, previous: Any = None) -> tuple[dict[str, Any], Usage]:
        return self.answers.get(call.key, self._default(stage, call)), self._usage(stage)

    def _default(self, stage: str, call: Call) -> dict[str, Any]:
        if stage == "audit":
            return {"findings": [], "panel": []}
        if stage == "zoom":
            return {"terminals": [], "cells": [], "cable_row": {}, "inc_row": {}, "unresolved": []}
        if stage == "title":
            return {"title_block": {"project": "אגרובנק TOWER B", "drawing_no": "4382.26-8"}, "board_data": []}
        page = int(re.search(r"sheet-(\d+)", call.key).group(1))
        label = f"{page:02d}"
        return {
            "sheet": {
                "page_number": page,
                "sheet_label": label,
                "title_block": {
                    "project": None, "panel": None, "panel_builder": None, "client": None,
                    "consultant": None, "drawing_no": None, "drawn_by": None,
                    "revision_dates": [], "status": None, "total_pages": None,
                },
            },
            "busbars": [],
            "devices": [],
            "circuit_table": [],
            "io_points": [],
            "cross_references": [],
            "gaps": [],
            "anomalies": [],
            "needs_zoom_regions": [],
        }
