"""Everything tunable about a run, in one place.

Two rules from the brief shape this module. Every stage's model must be
overridable from config and from the request body, so upgrading the audit
stage to Sonnet is a one-line change and never a code edit (§6). And the
price table lives here rather than at the call sites, so cost accounting
stays honest when prices move (§7).
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Mapping


# --------------------------------------------------------------- models

@dataclass(frozen=True)
class StageModel:
    """Which model runs a stage, and how it is called."""

    model: str
    max_tokens: int
    use_batch: bool = False
    # Haiku 4.5 still takes an explicit thinking budget; the 4.6+ models take
    # `adaptive` instead and reject `budget_tokens` outright. None means the
    # stage runs without extended thinking, which is what the extraction and
    # zoom stages want — they transcribe, they do not reason.
    thinking_budget: int | None = None


# Haiku 4.5 is the brief's default on every stage: cheapest viable, and the
# §9 harness exists precisely to prove or disprove that choice. If it fails
# the gates, upgrade `audit` first — that is one line here.
DEFAULT_MODELS: dict[str, StageModel] = {
    # Haiku, batched on the site (half price). Sonnet 5 read 4382.26-8 better
    # but cost $2.20 a run against about $1; what Haiku misses on that set is
    # covered in code (parts-list models, column links) where it can be.
    "extract": StageModel("claude-haiku-4-5-20251001", 8000, use_batch=True),
    "zoom": StageModel("claude-haiku-4-5-20251001", 2000),
    "audit": StageModel("claude-haiku-4-5-20251001", 8000),
    # The sheet carrying the title block and the board data table. Its own
    # stage so it can be moved to a stronger model with one line
    # (SCHEME_MODEL_TITLE=claude-sonnet-5, about five cents a drawing).
    "title": StageModel("claude-haiku-4-5-20251001", 8000),
}


# --------------------------------------------------------------- pricing

@dataclass(frozen=True)
class Price:
    """USD per million tokens, as published for the first-party API."""

    input: float
    output: float

    @property
    def cache_write(self) -> float:
        """A 5-minute cache write costs 1.25x the base input rate."""
        return self.input * 1.25

    @property
    def cache_read(self) -> float:
        """A cache read costs 0.1x the base input rate."""
        return self.input * 0.10


DEFAULT_PRICES: dict[str, Price] = {
    "claude-haiku-4-5": Price(1.00, 5.00),
    "claude-haiku-4-5-20251001": Price(1.00, 5.00),
    "claude-sonnet-5": Price(2.00, 10.00),
    "claude-sonnet-4-6": Price(3.00, 15.00),
    "claude-opus-5": Price(5.00, 25.00),
    "claude-opus-4-8": Price(5.00, 25.00),
}

# The Batch API bills every token type at half price.
BATCH_DISCOUNT = 0.50


# --------------------------------------------------------------- rendering

@dataclass(frozen=True)
class RenderSettings:
    """Resolutions and chunking, from §5 stage 2.

    The DPI numbers are not arbitrary. The table band carries 5-6pt Hebrew
    destination text; below about 350 DPI it stops being legible once the
    API downsamples, and the model fabricates plausible room names rather
    than erroring (§2.1). The chunk width is the other half of that defence:
    Anthropic caps an image's long edge near 1568px, so a 4000px-wide band
    must be cut into pieces that survive the cap intact.
    """

    single_line_dpi: int = 220
    table_band_dpi: int = 350
    title_block_dpi: int = 300
    zoom_dpi: int = 600
    context_long_edge: int = 1536
    chunk_width: int = 1400
    # A merged destination cell cut exactly at a chunk boundary with no
    # context around it is unrecoverable, so chunks overlap.
    chunk_overlap: int = 80


# --------------------------------------------------------------- run config

@dataclass(frozen=True)
class Config:
    api_key: str | None = None
    models: Mapping[str, StageModel] = field(default_factory=lambda: dict(DEFAULT_MODELS))
    prices: Mapping[str, Price] = field(default_factory=lambda: dict(DEFAULT_PRICES))
    render: RenderSettings = field(default_factory=RenderSettings)

    cache_dir: Path = Path("/tmp/scheme_extractor_cache")

    # Higher than six hits rate limits, and the retry churn costs more wall
    # clock than the parallelism saves (§5 stage 3).
    extract_concurrency: int = 4
    zoom_concurrency: int = 4

    # A third zoom attempt on the same region does not converge; escalate to
    # a human instead (§5 stage 4).
    max_zoom_passes: int = 2

    # Above this, caching missed or the zoom stage is firing on most sheets.
    # Both are real problems, so the run says so rather than quietly costing
    # three times what it should (§7).
    cost_warning_usd: float = 3.00

    # `pdftoppm` on a dense A1 sheet at 600 DPI is slow but not unbounded.
    poppler_timeout_s: int = 180

    temperature: float = 0.0

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Config":
        env = os.environ if env is None else env
        config = cls(api_key=env.get("ANTHROPIC_API_KEY"))
        if env.get("SCHEME_CACHE_DIR"):
            config = replace(config, cache_dir=Path(env["SCHEME_CACHE_DIR"]))
        if env.get("SCHEME_EXTRACT_CONCURRENCY"):
            config = replace(config, extract_concurrency=int(env["SCHEME_EXTRACT_CONCURRENCY"]))
        models = dict(config.models)
        for stage in models:
            override = env.get(f"SCHEME_MODEL_{stage.upper()}")
            if override:
                models[stage] = replace(models[stage], model=override)
        return replace(config, models=models)

    def with_overrides(self, overrides: Mapping[str, Any] | None) -> "Config":
        """Apply a `/extract` request body's per-run overrides.

        Only the knobs a caller is allowed to move are read here: the model
        per stage, and whether the extract stage uses the Batch API. Cache
        directory and API key stay server-side.
        """
        if not overrides:
            return self
        config = self
        model_overrides = overrides.get("models") or {}
        if model_overrides:
            models = dict(config.models)
            for stage, value in model_overrides.items():
                if stage not in models:
                    raise ValueError(f"Unknown stage: {stage}")
                if isinstance(value, str):
                    models[stage] = replace(models[stage], model=value)
                elif isinstance(value, Mapping):
                    models[stage] = replace(
                        models[stage],
                        **{k: v for k, v in value.items() if k in {"model", "max_tokens", "use_batch", "thinking_budget"}},
                    )
                else:
                    raise ValueError(f"Bad model override for {stage}: {value!r}")
            config = replace(config, models=models)
        if "use_batch" in overrides:
            models = dict(config.models)
            models["extract"] = replace(models["extract"], use_batch=bool(overrides["use_batch"]))
            config = replace(config, models=models)
        return config

    def price_for(self, model: str) -> Price:
        """Fall back to the most expensive known rate for an unknown model.

        An unpriced model must never report as free — a run that silently
        costs nothing is a broken cost report, not a cheap run.
        """
        if model in self.prices:
            return self.prices[model]
        return max(self.prices.values(), key=lambda p: p.output)
