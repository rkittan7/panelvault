"""The request the real SDK sends — no network, no key, no spend."""

import json

import anthropic
import httpx2

from scheme_extractor.config import Config
from scheme_extractor.models.client import AnthropicClient, Call, accepts_temperature


def _client(seen: list[dict]) -> AnthropicClient:
    def handler(request: httpx2.Request) -> httpx2.Response:
        body = json.loads(request.content)
        seen.append(body)
        return httpx2.Response(200, json={
            "id": "msg_1", "type": "message", "role": "assistant", "model": body["model"],
            "content": [{"type": "tool_use", "id": "tu_1", "name": "t", "input": {"ok": True}}],
            "stop_reason": "tool_use", "stop_sequence": None,
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })

    sdk = anthropic.Anthropic(api_key="test", http_client=httpx2.Client(transport=httpx2.MockTransport(handler)))
    return AnthropicClient(Config.from_env({"ANTHROPIC_API_KEY": "test"}), client=sdk)


CALL = Call(
    key="k", system="s", content=[{"type": "text", "text": "hi"}], tool_name="t",
    schema={"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False},
)


def test_sdk_1x_accepts_the_request_and_temperature_reaches_the_body():
    # SDK 1.x raises TypeError on a `temperature=` keyword; it must travel in the body.
    seen: list[dict] = []
    parsed, _ = _client(seen).complete("zoom", CALL)  # a Haiku stage
    assert parsed == {"ok": True}
    assert seen[-1]["temperature"] == 0.0


def test_a_newer_model_gets_no_temperature_and_no_thinking_with_a_forced_tool():
    seen: list[dict] = []
    _client(seen).complete("extract", CALL)  # Sonnet 5
    assert "temperature" not in seen[-1]
    assert seen[-1]["thinking"] == {"type": "disabled"}


def test_models_that_reject_temperature_are_not_sent_it():
    assert accepts_temperature("claude-haiku-4-5-20251001")
    assert accepts_temperature("claude-sonnet-4-6")
    for model in ("claude-sonnet-5", "claude-opus-5", "claude-opus-4-8", "claude-fable-5-1"):
        assert not accepts_temperature(model)


# ---------------------------------------------------------------- strict schemas

import pytest

from scheme_extractor.models.schema import (
    STRICT_UNION_LIMIT, AuditResult, SheetExtraction, ZoomResult, tool_schema, union_parameters,
)

REJECTED = {
    "maxItems", "minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum",
    "exclusiveMaximum", "multipleOf", "uniqueItems", "patternProperties", "propertyNames",
}


def _violations(node, path=""):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in REJECTED or (key == "minItems" and value not in (0, 1)):
                yield f"{path}/{key}"
            if key == "additionalProperties" and value is not False:
                yield f"{path}/additionalProperties"
            yield from _violations(value, f"{path}/{key}")
        if node.get("type") == "object" and node.get("additionalProperties") is not False:
            yield f"{path} (object not closed)"
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from _violations(item, f"{path}[{index}]")


@pytest.mark.parametrize("model", [SheetExtraction, ZoomResult, AuditResult])
def test_every_stage_schema_is_accepted_by_strict_tool_use(model):
    # The API answers a violation with a 400 on every sheet of every run.
    assert list(_violations(tool_schema(model))) == []


def test_zoom_maps_arrive_as_pairs_and_are_folded_back():
    result = ZoomResult.model_validate({
        "terminals": ["X11"], "cells": [], "unresolved": [],
        "cable_row": [{"terminal": "X11", "value": "5x2.5N2XY"}],
        "inc_row": [{"terminal": "X11", "value": "12.8A"}],
    })
    assert result.cable_row == {"X11": "5x2.5N2XY"}
    assert result.inc_row == {"X11": "12.8A"}


def test_strict_is_only_claimed_where_the_api_will_compile_it():
    seen: list[dict] = []
    client = _client(seen)
    for model in (SheetExtraction, ZoomResult, AuditResult):
        schema = tool_schema(model)
        call = Call(key="k", system="s", content=[{"type": "text", "text": "hi"}], tool_name="t", schema=schema)
        client.complete("extract", call)
        tool = seen[-1]["tools"][0]
        if tool["strict"]:
            assert union_parameters(tool["input_schema"]) <= STRICT_UNION_LIMIT
    # The sheet schema is the one over the limit; the other two stay strict.
    assert union_parameters(tool_schema(SheetExtraction)) > STRICT_UNION_LIMIT
    assert union_parameters(tool_schema(ZoomResult)) <= STRICT_UNION_LIMIT
    assert union_parameters(tool_schema(AuditResult)) <= STRICT_UNION_LIMIT


def test_an_answer_nested_under_the_tool_name_is_unwrapped():
    # Sonnet 5, unconstrained by strict mode, sent {"sheet_extraction": {...}}.
    class Block:
        type, name = "tool_use", "sheet_extraction"
        input = {"sheet_extraction": {"sheet": {"page_number": 24}}}

    class Message:
        content = [Block()]

    assert AnthropicClient._tool_input(Message(), "sheet_extraction") == {"sheet": {"page_number": 24}}
