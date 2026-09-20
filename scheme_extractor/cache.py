"""Rendered artifacts, keyed by the source file's hash.

Rendering a 35-sheet set at three resolutions is the slow part of a run and
none of it depends on the prompts. Keying the cache on the PDF's SHA-256
means a re-run after a prompt change re-renders nothing (§11.8), while a
different drawing can never collide with an earlier one's crops.
"""

from __future__ import annotations

import hashlib
from pathlib import Path


def source_hash(pdf: Path) -> str:
    digest = hashlib.sha256()
    with pdf.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


class ArtifactCache:
    def __init__(self, root: Path, source: str) -> None:
        self.root = Path(root) / source
        self.hits = 0
        self.misses = 0

    def path(self, page: int | str, name: str) -> Path:
        folder = self.root / str(page)
        folder.mkdir(parents=True, exist_ok=True)
        return folder / name

    def has(self, page: int | str, name: str) -> bool:
        present = self.path(page, name).exists()
        if present:
            self.hits += 1
        else:
            self.misses += 1
        return present
