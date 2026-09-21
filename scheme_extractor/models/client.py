"""The model client: one place that talks to Anthropic, counts what it spent,
and refuses to lose a whole run over one bad sheet.

Direct Anthropic SDK, not a routing layer (§8). The two reasons that decide
it are both money: the Batch API halves the dominant stage, and prompt
caching takes another slice off it, and neither is reliably reachable
through an abstraction layer. The `LLMClient` protocol below is what keeps
the bake-off possible anyway — an OpenRouter implementation can sit beside
this one and the pipeline will not know the difference.
"""

from __future__ import annotations

import base64
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Protocol, Sequence

import anthropic
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_random_exponential,
)

from dataclasses import replace as dc_replace

from ..config import BATCH_DISCOUNT, Config, StageModel
from .schema import strict_compatible



# Opus 4.7 and later, Sonnet 5 and Fable reject a fixed `temperature` with a
# 400; the 4.5 / 4.6 line still takes it. A stage upgraded to a newer model
# (SCHEME_MODEL_AUDIT=claude-sonnet-5) must not start failing for it.
_SAMPLING_MODELS = re.compile(r"claude-(?:haiku|sonnet|opus)-4-[56](?:$|-)")


def accepts_temperature(model: str) -> bool:
    return bool(_SAMPLING_MODELS.search(model))

class SchemaError(ValueError):
    """The model returned structurally valid JSON that the contract rejects."""


@dataclass
class Usage:
    stage: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0
    wall_seconds: float = 0.0
    batched: bool = False
    calls: int = 1
    note: str = ""

    def __add__(self, other: "Usage") -> "Usage":
        return Usage(
            stage=self.stage,
            model=self.model,
            input_tokens=self.input_tokens + other.input_tokens,
            output_tokens=self.output_tokens + other.output_tokens,
            cache_read_tokens=self.cache_read_tokens + other.cache_read_tokens,
            cache_write_tokens=self.cache_write_tokens + other.cache_write_tokens,
            wall_seconds=self.wall_seconds + other.wall_seconds,
            batched=self.batched or other.batched,
            calls=self.calls + other.calls,
        )


@dataclass
class CostLedger:
    """Per-stage tokens and dollars for the run (§7).

    Every number here comes from a response's own `usage`, never from an
    estimate — a cost report that guesses is not an audit trail.
    """

    config: Config
    entries: list[Usage] = field(default_factory=list)

    def record(self, usage: Usage) -> None:
        self.entries.append(usage)

    def usd(self, usage: Usage) -> float:
        price = self.config.price_for(usage.model)
        total = (
            usage.input_tokens * price.input
            + usage.output_tokens * price.output
            + usage.cache_write_tokens * price.cache_write
            + usage.cache_read_tokens * price.cache_read
        ) / 1_000_000
        return total * (BATCH_DISCOUNT if usage.batched else 1.0)

    def summary(self) -> dict[str, Any]:
        by_stage: dict[str, dict[str, Any]] = {}
        for entry in self.entries:
            row = by_stage.setdefault(
                entry.stage,
                {
                    "model": entry.model,
                    "calls": 0,
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "cache_read_tokens": 0,
                    "cache_write_tokens": 0,
                    "wall_seconds": 0.0,
                    "usd": 0.0,
                },
            )
            row["calls"] += entry.calls
            row["input_tokens"] += entry.input_tokens
            row["output_tokens"] += entry.output_tokens
            row["cache_read_tokens"] += entry.cache_read_tokens
            row["cache_write_tokens"] += entry.cache_write_tokens
            row["wall_seconds"] += entry.wall_seconds
            row["usd"] += self.usd(entry)
        total = round(sum(row["usd"] for row in by_stage.values()), 4)
        warnings: list[str] = []
        if total > self.config.cost_warning_usd:
            warnings.append(
                f"Run cost ${total:.2f}, above the ${self.config.cost_warning_usd:.2f} line. "
                "Either prompt caching missed or the zoom stage fired on most sheets."
            )
        cache_reads = sum(row["cache_read_tokens"] for row in by_stage.values())
        if not cache_reads and len(self.entries) > 4:
            warnings.append(
                "No cached input tokens across the whole run — the static prompt prefix is "
                "being invalidated somewhere."
            )
        for stage, row in by_stage.items():
            row["usd"] = round(row["usd"], 4)
        return {"by_stage": by_stage, "total_usd": total, "warnings": warnings}


# ------------------------------------------------------------------ requests

@dataclass
class Call:
    """One unit of work: a system prompt, some content, and a contract."""

    key: str
    system: str
    content: list[dict[str, Any]]
    tool_name: str
    schema: dict[str, Any]


def image_block(path: Path, media_type: str = "image/png") -> dict[str, Any]:
    return {
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": media_type,
            "data": base64.standard_b64encode(path.read_bytes()).decode("ascii"),
        },
    }


def text_block(text: str) -> dict[str, Any]:
    return {"type": "text", "text": text}


class LLMClient(Protocol):
    """The seam that makes a model bake-off a config change (§8)."""

    def complete(self, stage: str, call: Call) -> tuple[dict[str, Any], Usage]:
        ...

    def complete_many(self, stage: str, calls: Sequence[Call]) -> dict[str, tuple[dict[str, Any] | None, Usage]]:
        ...


RETRYABLE = (
    anthropic.RateLimitError,
    anthropic.InternalServerError,
    anthropic.APIConnectionError,
    anthropic.APITimeoutError,
)


class AnthropicClient:
    def __init__(self, config: Config, client: Any | None = None) -> None:
        self.config = config
        self.ledger = CostLedger(config)
        self._client = client or anthropic.Anthropic(api_key=config.api_key)

    # -- shared request shape -------------------------------------------

    def _params(self, stage: StageModel, call: Call, extra_messages: Iterable[dict[str, Any]] = ()) -> dict[str, Any]:
        """Build one Messages request.

        Two placements matter. The system prompt and the tool schema carry
        `cache_control: ephemeral` so the ~7k tokens of instructions are
        written to cache once and read back on the other thirty-four sheets.
        And the images go last, after the tokens, because everything before
        the final breakpoint has to be byte-identical for that cache to hit.
        """
        tool: dict[str, Any] = {
            "name": call.tool_name,
            "description": f"Return the {call.tool_name} record for this sheet.",
            # The sheet schema has far more nullable fields than strict mode
            # will compile (41 against a limit of 16). It goes unstrict and
            # leans on the Pydantic check and its correction turn instead.
            "strict": strict_compatible(call.schema),
            "input_schema": call.schema,
            "cache_control": {"type": "ephemeral"},
        }
        params: dict[str, Any] = {
            "model": stage.model,
            "max_tokens": stage.max_tokens,
            "system": [
                {"type": "text", "text": call.system, "cache_control": {"type": "ephemeral"}}
            ],
            "tools": [tool],
            "tool_choice": {"type": "tool", "name": call.tool_name},
            "messages": [{"role": "user", "content": call.content}, *extra_messages],
        }
        if stage.thinking_budget:
            # Haiku 4.5 takes an explicit budget; it has no `effort` control.
            params["thinking"] = {"type": "enabled", "budget_tokens": stage.thinking_budget}
            # Thinking and forced tool choice cannot be combined.
            params["tool_choice"] = {"type": "auto"}
        elif accepts_temperature(stage.model):
            params["temperature"] = self.config.temperature
        return params

    def _create(self, params: dict[str, Any]) -> Any:
        """`messages.create` for one request.

        SDK 1.x dropped `temperature` from the method signature (passing it is
        a TypeError), though the API still honours it on the models that
        accept it. It travels in the request body instead. The batch path
        needs no such move: a batch request's params are forwarded as-is.
        """
        params = dict(params)
        temperature = params.pop("temperature", None)
        if temperature is not None:
            params["extra_body"] = {"temperature": temperature}
        return self._client.messages.create(**params)

    @staticmethod
    def _usage(stage_name: str, model: str, message: Any, seconds: float, batched: bool) -> Usage:
        usage = getattr(message, "usage", None)
        return Usage(
            stage=stage_name,
            model=model,
            input_tokens=getattr(usage, "input_tokens", 0) or 0,
            output_tokens=getattr(usage, "output_tokens", 0) or 0,
            cache_read_tokens=getattr(usage, "cache_read_input_tokens", 0) or 0,
            cache_write_tokens=getattr(usage, "cache_creation_input_tokens", 0) or 0,
            wall_seconds=seconds,
            batched=batched,
        )

    @staticmethod
    def _tool_input(message: Any, tool_name: str) -> dict[str, Any]:
        for block in getattr(message, "content", []):
            if getattr(block, "type", None) == "tool_use" and block.name == tool_name:
                # Never string-match a serialized tool input; take the parsed dict.
                return dict(block.input)
        raise SchemaError(f"No {tool_name} tool call in the response.")

    # -- single call -----------------------------------------------------

    def complete(self, stage: str, call: Call) -> tuple[dict[str, Any], Usage]:
        stage_model = self.config.models[stage]

        @retry(
            retry=retry_if_exception_type(RETRYABLE),
            wait=wait_random_exponential(multiplier=2, max=60),
            stop=stop_after_attempt(5),
            reraise=True,
        )
        def send(params: dict[str, Any]) -> tuple[Any, float]:
            started = time.monotonic()
            message = self._create(params)
            return message, time.monotonic() - started

        params = self._params(stage_model, call)
        message, seconds = send(params)
        usage = self._usage(stage, stage_model.model, message, seconds, batched=False)
        try:
            parsed = self._tool_input(message, call.tool_name)
        except SchemaError as first:
            # One correction turn, with the model's own answer and the
            # complaint attached. A model that cannot satisfy the contract
            # twice will not satisfy it a third time, and the run must not
            # stop for it.
            retry_message, retry_seconds = send(
                self._params(
                    stage_model,
                    call,
                    extra_messages=[
                        {"role": "assistant", "content": message.content},
                        {"role": "user", "content": (
                            f"That response did not satisfy the contract: {first}. "
                            f"Answer again using the {call.tool_name} tool only."
                        )},
                    ],
                )
            )
            usage = usage + self._usage(stage, stage_model.model, retry_message, retry_seconds, False)
            parsed = self._tool_input(retry_message, call.tool_name)
        self.ledger.record(usage)
        return parsed, usage

    def revalidate(
        self, stage: str, call: Call, error: str, previous: Any = None
    ) -> tuple[dict[str, Any], Usage]:
        """Re-ask once with a validation error attached (§6).

        Used when the JSON parsed but the Pydantic contract rejected it —
        a `qty` that does not match its expanded tags, a cell marked spare
        with no שמור printed.
        """
        stage_model = self.config.models[stage]
        params = self._params(
            stage_model,
            call,
            extra_messages=[
                {"role": "assistant", "content": previous or [text_block("(previous answer omitted)")]},
                {"role": "user", "content": (
                    f"The previous answer failed validation: {error}\n"
                    "Correct only what the error names and return the whole record again. "
                    "Do not invent values to satisfy the check."
                )},
            ],
        )
        started = time.monotonic()
        message = self._create(params)
        usage = self._usage(stage, stage_model.model, message, time.monotonic() - started, False)
        self.ledger.record(usage)
        return self._tool_input(message, call.tool_name), usage

    # -- batch -----------------------------------------------------------

    def complete_many(
        self, stage: str, calls: Sequence[Call], poll_seconds: int = 20, timeout_seconds: int = 24 * 3600
    ) -> dict[str, tuple[dict[str, Any] | None, Usage]]:
        """Run a stage's calls as one batch, falling back to one-by-one.

        Nobody is watching a scheme extraction run, which makes the 50%
        batch discount free money on the stage that dominates the bill.
        """
        stage_model = self.config.models[stage]
        if not stage_model.use_batch or len(calls) < 2:
            # Four to six at a time. Higher hits rate limits, and the retry
            # churn then costs more wall clock than the parallelism saved.
            def one(call: Call) -> tuple[str, tuple[dict[str, Any] | None, Usage]]:
                try:
                    return call.key, self.complete(stage, call)
                except Exception as error:  # noqa: BLE001 — one sheet must not end the run
                    return call.key, (
                        None,
                        Usage(stage, stage_model.model, wall_seconds=0.0, note=str(error)[:300]),
                    )

            workers = max(1, min(self.config.extract_concurrency, len(calls)))
            with ThreadPoolExecutor(max_workers=workers) as pool:
                return dict(pool.map(one, calls))

        try:
            return self._run_batch(stage, calls, poll_seconds, timeout_seconds)
        except Exception as error:  # noqa: BLE001 — batching is an optimisation, not a dependency
            fallback = dict(self.config.models)
            fallback[stage] = dc_replace(stage_model, use_batch=False)
            self.config = dc_replace(self.config, models=fallback)
            self.ledger.entries.append(
                Usage(stage, stage_model.model, note=f"Batch failed, fell back to per-sheet calls: {error}"[:300])
            )
            return self.complete_many(stage, calls, poll_seconds, timeout_seconds)

    def _run_batch(
        self, stage: str, calls: Sequence[Call], poll_seconds: int, timeout_seconds: int
    ) -> dict[str, tuple[dict[str, Any] | None, Usage]]:
        stage_model = self.config.models[stage]
        started = time.monotonic()
        batch = self._client.messages.batches.create(
            requests=[
                {"custom_id": call.key, "params": self._params(stage_model, call)}
                for call in calls
            ]
        )
        while True:
            current = self._client.messages.batches.retrieve(batch.id)
            if current.processing_status == "ended":
                break
            if time.monotonic() - started > timeout_seconds:
                raise TimeoutError(f"Batch {batch.id} did not finish within {timeout_seconds}s.")
            time.sleep(poll_seconds)

        by_key = {call.key: call for call in calls}
        elapsed = time.monotonic() - started
        results: dict[str, tuple[dict[str, Any] | None, Usage]] = {}
        # Results come back in any order, so they are keyed, never positional.
        for item in self._client.messages.batches.results(batch.id):
            call = by_key[item.custom_id]
            if item.result.type != "succeeded":
                # An errored result carries the API's own reason; without it
                # the sheet's failure reads only "errored".
                detail = getattr(getattr(getattr(item.result, "error", None), "error", None), "message", "")
                note = f"batch result: {item.result.type}" + (f" — {detail}" if detail else "")
                results[call.key] = (None, Usage(stage, stage_model.model, batched=True, note=note[:300]))
                continue
            message = item.result.message
            usage = self._usage(stage, stage_model.model, message, elapsed / max(1, len(calls)), batched=True)
            self.ledger.record(usage)
            try:
                results[call.key] = (self._tool_input(message, call.tool_name), usage)
            except SchemaError:
                results[call.key] = (None, usage)
        for call in calls:
            results.setdefault(call.key, (None, Usage(stage, stage_model.model, batched=True)))
        return results
