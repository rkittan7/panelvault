"""The orchestrator: stages 0 through 7, in order, for one drawing set."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .cache import ArtifactCache, source_hash
from .config import Config
from .models.client import AnthropicClient, LLMClient
from .models.schema import AuditResult, ExtractionRun, Sheet, SheetExtraction
from .stages import audit, extract, reconcile, rollup, title, zoom
from .stages.probe import ProbeResult, probe
from .stages.render import PageRegions, page_regions
from .stages.textlayer import AnchorError, PageTokens, page_tokens

Progress = Callable[[str, float], None]

log = logging.getLogger("scheme_extractor")


class ExtractionFailed(RuntimeError):
    """The run produced nothing a reviewer could use."""


def account_problem(error: str) -> str | None:
    """Plain words for a failure of the Anthropic account, not the drawing."""
    text = error.lower()
    if "credit balance is too low" in text:
        return ("The Anthropic account behind the scheme reader is out of credit. "
                "Add credit under Plans & Billing at console.anthropic.com, then read the drawing again.")
    if "invalid x-api-key" in text or "authentication_error" in text:
        return "The scheme reader's Anthropic API key was rejected. Check ANTHROPIC_API_KEY on the extractor service."
    return None


@dataclass
class PreparedPage:
    tokens: PageTokens
    regions: PageRegions


@dataclass
class Prepared:
    """Everything stages 0-2 produce, before a token has been bought."""

    probe: ProbeResult
    pages: dict[int, PreparedPage] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    # How the file was handled (rotation, chunking, a thin text layer):
    # context for a developer, not something a reviewer can act on.
    notes: list[str] = field(default_factory=list)


def prepare(pdf: Path, config: Config, cache: ArtifactCache, progress: Progress | None = None) -> Prepared:
    result = probe(pdf, timeout=config.poppler_timeout_s)
    prepared = Prepared(probe=result, notes=list(result.notes))

    # Which sheet carries the title block: read once, reused everywhere (§5).
    title_sheet = 1
    for page in range(1, result.pages + 1):
        try:
            tokens = page_tokens(
                pdf, page,
                page_size=result.page_size,
                rotation=result.rotation,
                dpi=config.render.single_line_dpi,
                timeout=config.poppler_timeout_s,
            )
        except AnchorError as error:
            # Fail the page, not the run — but loudly, and never with a crop.
            prepared.warnings.append(str(error))
            continue
        regions = page_regions(
            pdf, tokens, cache, config.render,
            include_title_block=(page == title_sheet),
            timeout=config.poppler_timeout_s,
        )
        prepared.pages[page] = PreparedPage(tokens, regions)
        prepared.notes.extend(regions.notes)
        if progress:
            progress(f"prepared sheet {page}", page / max(1, result.pages) * 0.25)
    return prepared


def run(
    pdf: Path,
    config: Config,
    *,
    client: LLMClient | None = None,
    job_id: str | None = None,
    progress: Progress | None = None,
) -> ExtractionRun:
    digest = source_hash(pdf)
    cache = ArtifactCache(config.cache_dir, digest)
    job = job_id or f"job_{uuid.uuid4().hex[:12]}"

    prepared = prepare(pdf, config, cache, progress)
    client = client or AnthropicClient(config)

    # ---------------------------------------------------------- stage 3
    calls = [
        extract.build_call(
            page.tokens, page.regions,
            total_pages=prepared.probe.pages,
            text_coverage=prepared.probe.text_coverage,
            chunk_overlap=config.render.chunk_overlap,
        )
        for page in prepared.pages.values()
    ]
    if progress:
        progress(f"reading {len(calls)} sheets", 0.30)
    extracted = extract.extract_sheets(client, config, calls)

    sheets: list[SheetExtraction] = []
    # A page that could not be prepared is a problem; how the others were
    # prepared is a note, kept apart so it never crowds the problems out.
    warnings: list[str] = list(prepared.warnings)
    failures: list[str] = []
    for page, prepared_page in sorted(prepared.pages.items()):
        sheet, error = extracted.get(page, (None, "not attempted"))
        if sheet is None:
            # One unreadable sheet does not end a run; it is reported as one.
            label = extract.sheet_label(prepared_page.tokens)
            sheet = SheetExtraction(sheet=Sheet(page_number=page, sheet_label=label))
            sheet.notes.append(f"Extraction failed: {error}")
            warnings.append(f"Sheet {label} could not be read: {error}")
            failures.append(error)
            log.warning("sheet %s could not be read: %s", label, error)
        sheet.layout_kind = prepared_page.regions.layout_kind
        sheets.append(sheet)
    account = next((reason for error in failures if (reason := account_problem(error))), None)
    if account:
        # Every further call fails the same way; a draft read from the few
        # sheets that got through would look like a board with parts missing.
        raise ExtractionFailed(account)
    if not prepared.pages:
        raise ExtractionFailed("No sheet in this PDF could be prepared: " + "; ".join((prepared.warnings or prepared.notes)[:3]))
    if len(failures) == len(sheets):
        # Nothing was read. An empty draft would look like an empty board;
        # fail the job with the reason instead.
        raise ExtractionFailed(f"Claude could not read any of the {len(sheets)} sheets. First error: {failures[0]}")

    # The board's identity, read on its own: see stages/title.py.
    for sheet in sheets:
        prepared_page = prepared.pages.get(sheet.sheet.page_number)
        if prepared_page is None or "title_block" not in prepared_page.regions.regions:
            continue
        identity, problem = title.read(client, prepared_page.regions)
        if identity is not None:
            sheet.sheet.title_block = identity.title_block
            if identity.board_data:
                sheet.board_data = identity.board_data
        elif problem:
            warnings.append(problem)

    # ---------------------------------------------------------- stage 4
    for index, sheet in enumerate(sheets):
        prepared_page = prepared.pages.get(sheet.sheet.page_number)
        if prepared_page is None or sheet.layout_kind != "table":
            continue
        if not zoom.targets_for(sheet, prepared_page.regions):
            continue
        zoom.resolve(client, config, pdf, sheet, prepared_page.regions, cache)
        if progress:
            progress(f"resolved spans on sheet {sheet.sheet.sheet_label}", 0.60 + index / len(sheets) * 0.15)

    # ---------------------------------------------------------- stage 5
    for sheet in sheets:
        prepared_page = prepared.pages.get(sheet.sheet.page_number)
        if prepared_page:
            reconcile.reconcile(sheet, prepared_page.tokens, text_coverage=prepared.probe.text_coverage)
        warnings.extend(sheet.notes)

    # ---------------------------------------------------------- stage 6
    if progress:
        progress("rolling up", 0.80)
    bom = rollup.build_bom(sheets)
    circuits, counts = rollup.flatten_circuits(sheets)

    # ---------------------------------------------------------- stage 7
    if progress:
        progress("auditing the set", 0.88)
    audit_result, audit_error = audit.run(client, sheets)
    if audit_error:
        warnings.append(audit_error)

    cost = client.ledger.summary() if hasattr(client, "ledger") else {}
    warnings.extend(cost.get("warnings", []))

    notes = list(prepared.notes)
    if prepared.probe.text_coverage != "rich":
        notes.append(
            "This drawing's text layer carries only the sheet frame and title block, so device "
            "values could not be reconciled against it. Every affected value is flagged "
            "`*_unverifiable` rather than verified."
        )

    unresolved = [line for line in bom if line.needs_human]
    if unresolved:
        warnings.append(
            f"{len(unresolved)} BOM line(s) carry unresolved flags and are marked for human review."
        )

    if progress:
        progress("done", 1.0)
    return ExtractionRun(
        job_id=job,
        source_hash=digest,
        sheets=sheets,
        bom=bom,
        circuits=circuits,
        counts=counts,
        audit=audit_result or AuditResult(),
        cost=cost,
        warnings=warnings,
        notes=notes,
    )
