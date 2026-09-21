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
    parsed, _ = _client(seen).complete("extract", CALL)
    assert parsed == {"ok": True}
    assert seen[-1]["temperature"] == 0.0


def test_models_that_reject_temperature_are_not_sent_it():
    assert accepts_temperature("claude-haiku-4-5-20251001")
    assert accepts_temperature("claude-sonnet-4-6")
    for model in ("claude-sonnet-5", "claude-opus-5", "claude-opus-4-8", "claude-fable-5-1"):
        assert not accepts_temperature(model)
