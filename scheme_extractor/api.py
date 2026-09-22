"""HTTP surface: submit a drawing set, poll the job, collect the workbook.

A 35-sheet set takes minutes, so `POST /extract` hands back a job id rather
than holding a connection open. The Node API in front of this proxies both
endpoints.
"""

from __future__ import annotations

import base64
import binascii
import logging
import shutil
import tempfile
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import Config
from .output.payload import payload
from .output.workbook import write as write_workbook
from .pipeline import ExtractionFailed, run as run_pipeline

app = FastAPI(title="PanelVault scheme extraction", version="1.0")

BASE_CONFIG = Config.from_env()
JOBS_DIR = Path(tempfile.gettempdir()) / "scheme_extractor_jobs"
JOBS_DIR.mkdir(parents=True, exist_ok=True)

# 60 MB of PDF: a 35-sheet A4 set is about 8 MB, and the largest sets seen
# from this producer are well under this.
MAX_PDF_BYTES = 60 * 1024 * 1024


@dataclass
class Job:
    id: str
    status: str = "queued"          # queued | running | done | failed
    stage: str = ""
    progress: float = 0.0
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    finished_at: str | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    workbook: str | None = None


JOBS: dict[str, Job] = {}
LOCK = threading.Lock()

# A sidecar stays up for weeks. Finished jobs hold a whole run's JSON, so
# they are reaped rather than kept forever; the workbook goes with them.
MAX_FINISHED_JOBS = 50


def _reap() -> None:
    with LOCK:
        finished = sorted(
            (job for job in JOBS.values() if job.status in {"done", "failed"}),
            key=lambda job: job.finished_at or "",
        )
        for job in finished[:-MAX_FINISHED_JOBS] if len(finished) > MAX_FINISHED_JOBS else []:
            JOBS.pop(job.id, None)
            shutil.rmtree(JOBS_DIR / job.id, ignore_errors=True)


class ExtractRequest(BaseModel):
    """The JSON form, for callers that already hold the file in memory."""

    fileName: str | None = None
    data: str = Field(description="base64-encoded PDF")
    # Per-run overrides: which model runs which stage, and whether to batch.
    # Everything else stays server-side.
    models: dict[str, Any] | None = None
    use_batch: bool | None = None


def _config_for(overrides: dict[str, Any] | None) -> Config:
    try:
        return BASE_CONFIG.with_overrides(overrides)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


def _start(pdf: Path, config: Config, tasks: BackgroundTasks) -> Job:
    job = Job(id=f"job_{uuid.uuid4().hex[:12]}")
    with LOCK:
        JOBS[job.id] = job

    def work() -> None:
        job.status = "running"

        def progress(stage: str, fraction: float) -> None:
            job.stage = stage
            job.progress = round(fraction, 3)

        try:
            result = run_pipeline(pdf, config, job_id=job.id, progress=progress)
            book = JOBS_DIR / job.id / "extraction.xlsx"
            write_workbook(result, book)
            job.result = payload(result)
            job.workbook = str(book)
            job.status = "done"
        except Exception as error:  # noqa: BLE001 — the job carries the failure, the server stays up
            job.status = "failed"
            # A run that read nothing already says why in plain words.
            job.error = str(error) if isinstance(error, ExtractionFailed) else f"{type(error).__name__}: {error}"
            logging.getLogger("scheme_extractor").exception("job %s failed", job.id)
        finally:
            job.finished_at = datetime.now(timezone.utc).isoformat()
            job.progress = 1.0
            # The drawing is the customer's IP; it does not linger on disk
            # after the run that needed it.
            shutil.rmtree(pdf.parent, ignore_errors=True)
            _reap()

    tasks.add_task(work)
    return job


def _store(data: bytes, name: str) -> Path:
    if not (data[:5].startswith(b"%PDF-") or data.startswith(b"(DWF V")):
        raise HTTPException(status_code=415, detail="That file is neither a PDF nor a DWF.")
    if len(data) > MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="That drawing set is too large to read.")
    folder = JOBS_DIR / f"upload_{uuid.uuid4().hex[:12]}"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / (Path(name or "scheme.pdf").name or "scheme.pdf")
    target.write_bytes(data)
    return target


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "poppler": bool(shutil.which("pdftotext") and shutil.which("pdftoppm")),
        "configured": bool(BASE_CONFIG.api_key),
        "models": {stage: model.model for stage, model in BASE_CONFIG.models.items()},
    }


@app.post("/extract", status_code=202)
async def extract_json(request: ExtractRequest, tasks: BackgroundTasks) -> JSONResponse:
    try:
        data = base64.b64decode(request.data, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail="`data` is not valid base64.") from error
    pdf = _store(data, request.fileName or "scheme.pdf")
    config = _config_for({"models": request.models, "use_batch": request.use_batch})
    job = _start(pdf, config, tasks)
    return JSONResponse({"job_id": job.id, "status": job.status}, status_code=202)


@app.post("/extract/upload", status_code=202)
async def extract_upload(tasks: BackgroundTasks, file: UploadFile = File(...)) -> JSONResponse:
    pdf = _store(await file.read(), file.filename or "scheme.pdf")
    job = _start(pdf, _config_for(None), tasks)
    return JSONResponse({"job_id": job.id, "status": job.status}, status_code=202)


@app.get("/jobs/{job_id}")
def job_status(job_id: str) -> dict[str, Any]:
    job = JOBS.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="No such job.")
    body: dict[str, Any] = {
        "job_id": job.id,
        "status": job.status,
        "stage": job.stage,
        "progress": job.progress,
        "created_at": job.created_at,
        "finished_at": job.finished_at,
    }
    if job.status == "done":
        body["result"] = job.result
        body["workbook_url"] = f"/jobs/{job.id}/workbook"
    if job.error:
        body["error"] = job.error
    return body


@app.get("/jobs/{job_id}/workbook")
def job_workbook(job_id: str) -> FileResponse:
    job = JOBS.get(job_id)
    if job is None or not job.workbook or not Path(job.workbook).exists():
        raise HTTPException(status_code=404, detail="No workbook for that job.")
    return FileResponse(
        job.workbook,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        filename=f"{job.id}.xlsx",
    )
