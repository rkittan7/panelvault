"""Stage 2 — render the page once, then cut it into regions worth sending.

The one rule this stage exists to enforce: never send a whole sheet as a
single image and expect a table to be read (§2.1). An A4 sheet downscaled to
the API's ~1568px long-edge cap puts 5-6pt Hebrew destination text at three
or four pixels tall, and the model does not error on that — it invents
plausible room names. So the sheet is cropped and the crops go out at native
resolution.

Regions are located from the drawing itself, never from fixed percentages,
because the destination table's height and width both vary from sheet to
sheet — sheet 17 of the reference set carries a table one column wide, and a
percentage crop tuned on sheet 6 would cut it in half.
"""

from __future__ import annotations

import re
import subprocess
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

from ..cache import ArtifactCache
from ..config import RenderSettings
from .textlayer import PageTokens, Token

# A dark run in a bilevel scanline. Rules are long runs; glyphs are short ones.
DARK_RUN = re.compile(rb"\x00+")


@dataclass
class Region:
    """One image the model will be shown, and where on the sheet it came from."""

    name: str
    path: Path
    box: tuple[int, int, int, int]          # pixels, in this region's own dpi
    bbox_pct: tuple[float, float, float, float]  # fraction of the page, for stage 4
    dpi: int
    chunks: list[Path] = field(default_factory=list)


@dataclass
class PageRegions:
    page: int
    layout_kind: str                         # "table" | "no_table"
    regions: dict[str, Region]
    notes: list[str] = field(default_factory=list)


# ----------------------------------------------------------------- rendering

# This producer's exports make poppler print hundreds of stream warnings per
# page. They are noise; only what is left says why a render failed.
PDF_NOISE = re.compile(r"Syntax (?:Error|Warning)|Illegal character|Missing 'endstream'|Bad 'Length'")


def _pdftoppm(pdf: Path, page: int, dpi: int, target: Path, extra: list[str], timeout: int) -> Path:
    """Render into `target`, once more if the first attempt yields nothing.

    Each attempt writes under its own prefix, so two runs of the same drawing
    — which share a cache directory — never move each other's output away.
    """
    detail = ""
    for _ in range(2):
        prefix = target.with_name(f"{target.stem}.{uuid.uuid4().hex[:8]}")
        done = subprocess.run(
            ["pdftoppm", "-r", str(dpi), "-png", "-f", str(page), "-l", str(page), *extra, str(pdf), str(prefix)],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
        )
        # pdftoppm appends a zero-padded page number of unpredictable width.
        produced = sorted(prefix.parent.glob(f"{prefix.name}-*.png"))
        if produced:
            produced[0].replace(target)
            for leftover in produced[1:]:
                leftover.unlink()
            return target
        errors = [line for line in done.stderr.splitlines() if line.strip() and not PDF_NOISE.search(line)]
        # A negative code is the signal that killed it; -9 under a memory cap
        # is the out-of-memory killer.
        detail = f"exit code {done.returncode}" + (f": {' | '.join(errors[-3:])}" if errors else "")
    raise RuntimeError(f"pdftoppm produced nothing for page {page} at {dpi} dpi ({detail}).")


def render_page(pdf: Path, page: int, dpi: int, cache: ArtifactCache, timeout: int = 180) -> Path:
    name = f"page-{dpi}.png"
    target = cache.path(page, name)
    if cache.has(page, name):
        return target
    return _pdftoppm(pdf, page, dpi, target, [], timeout)


def render_region(
    pdf: Path,
    page: int,
    dpi: int,
    box: tuple[int, int, int, int],
    cache: ArtifactCache,
    name: str,
    timeout: int = 180,
) -> Image.Image:
    """One rectangle of a page at `dpi`, in rendered (post-rotation) pixels."""
    target = cache.path(page, f"{name}.png")
    if not cache.has(page, f"{name}.png"):
        x0, y0, x1, y1 = box
        _pdftoppm(
            pdf, page, dpi, target,
            ["-x", str(x0), "-y", str(y0), "-W", str(x1 - x0), "-H", str(y1 - y0)],
            timeout,
        )
    with Image.open(target) as image:
        image.load()
        return image


# ------------------------------------------------------------ rule detection

def _bilevel(image: Image.Image) -> tuple[bytes, int, int]:
    grey = image.convert("L").point(lambda v: 0 if v < 200 else 255)
    width, height = grey.size
    return grey.tobytes(), width, height


def _runs(line: bytes, min_len: int, gap: int = 3) -> list[tuple[int, int]]:
    """Dark runs in one scanline, closing antialiasing gaps of a few pixels."""
    spans: list[list[int]] = []
    for match in DARK_RUN.finditer(line):
        start, end = match.span()
        if spans and start - spans[-1][1] <= gap:
            spans[-1][1] = end
        else:
            spans.append([start, end])
    return [(s, e) for s, e in spans if e - s >= min_len]


def title_block_top(image: Image.Image, anchor_y: int) -> int | None:
    """The title block's top border: the first long rule above its text.

    The text-layer anchor sits on a middle row of the block (the e-mail line
    on this producer's frame). Cropping a fixed distance above it cut the
    project and drawing-number row in half.
    """
    width, height = image.size
    lowest = max(0, anchor_y - round(0.25 * height))
    band = image.crop((0, lowest, width, anchor_y))
    data, band_w, band_h = _bilevel(band)
    for row in range(band_h - 1, -1, -1):
        line = data[row * band_w:(row + 1) * band_w]
        if any(end - start >= 0.6 * band_w for start, end in _runs(line, round(0.6 * band_w))):
            # Keep going while the block's own internal rules continue; the
            # top border is the highest rule reached before a gap in them.
            top = row
            gap = 0
            for above in range(row - 1, -1, -1):
                ruled = _runs(data[above * band_w:(above + 1) * band_w], round(0.6 * band_w))
                if ruled:
                    top, gap = above, 0
                elif (gap := gap + 1) > round(0.06 * height):
                    break
            return lowest + top
    return None


def title_piece_lefts(width: int, piece_width: int) -> list[int]:
    """Left edges of pieces `piece_width` wide, overlapping by a quarter of `width`."""
    step = max(1, piece_width - round(width * 0.25))
    return list(range(0, width - piece_width, step)) + [width - piece_width]


def split_title_block(image: Image.Image, stem: Path, piece_width: int = 1500) -> list[Path]:
    """Pieces narrow enough to reach the model unshrunk, overlapping by a quarter.

    Hebrew title blocks put each label to the right of its value, and a
    label/value pair spans up to a fifth of the block (שם המזמין on
    4382.26-8 runs from 42% to 62% of its width). Cut at a fixed width, or
    with too thin an overlap, the label lands in one piece and its value in
    the next, and the model pairs the wrong ones. With a quarter-width
    overlap every pair is whole in at least one piece.
    """
    width, height = image.size
    if width <= piece_width:
        path = stem.with_name(f"{stem.name}-00.png")
        image.save(path)
        return [path]
    paths = []
    for index, left in enumerate(title_piece_lefts(width, piece_width)):
        path = stem.with_name(f"{stem.name}-{index:02d}.png")
        image.crop((left, 0, left + piece_width, height)).save(path)
        paths.append(path)
    return paths


def _vertical_rules(image: Image.Image, min_len: int) -> list[tuple[int, int, int]]:
    """Every long vertical line as (x, y_top, y_bottom).

    Rotating the image turns columns into scanlines, so the same cheap
    run-length scan finds both orientations.
    """
    data, width, height = _bilevel(image.transpose(Image.ROTATE_90))
    # After ROTATE_90 the scanline at index j is the original column W-1-j,
    # and positions along it are original rows.
    page_width = height
    found: list[tuple[int, int, int]] = []
    for index in range(height):
        for y0, y1 in _runs(data[index * width : (index + 1) * width], min_len):
            found.append((page_width - 1 - index, y0, y1))
    return found


def detect_table(image: Image.Image, tokens: PageTokens) -> tuple[int, int, int, int] | None:
    """Locate the outgoing-destination table, or report that there is none.

    The anchor is the `Inc` row label. It is the one piece of the table that
    survives into the text layer on every sheet that has a table, which makes
    it a far steadier starting point than the terminal tags — those are drawn
    as vector geometry and recover as nothing at all.

    From that anchor the table's own left border gives the exact top and
    bottom: a border rule runs the full height of the table and stops there,
    where a walk up through horizontal rules would happily march off into the
    single-line diagram above.
    """
    width, height = image.size
    incs = [t for t in tokens.tokens if t.text == "Inc" and t.cy > height * 0.60]
    if not incs:
        return None
    inc = min(incs, key=lambda t: t.cy)

    verticals = _vertical_rules(image, min_len=int(height * 0.04))

    # The left border: the nearest vertical rule to the left of the label, of
    # a length that is a table and not the sheet frame.
    borders = [
        (inc.x0 - x, x, y0, y1)
        for x, y0, y1 in verticals
        if y0 - 2 <= inc.cy <= y1 + 2
        and (y1 - y0) < height * 0.55
        and 0 <= inc.x0 - x <= 160 * (image.size[0] / 2573)
    ]
    if not borders:
        return None
    _, left, top, bottom = min(borders)

    # The right border: the furthest rule of comparable height that runs
    # alongside this one. Height keeps the sheet frame out.
    table_height = bottom - top
    right = left
    for x, y0, y1 in verticals:
        overlap = min(y1, bottom) - max(y0, top)
        if overlap >= table_height * 0.60 and (y1 - y0) <= table_height * 1.35 and x > right:
            right = x
    if right <= left:
        return None
    return left, top, right, bottom


# ------------------------------------------------------------------ chunking

def chunk_width(image: Image.Image, settings: RenderSettings, stem: Path) -> list[Path]:
    """Cut a wide strip into pieces the API will not downscale past legibility.

    Overlap is the point of this function. A destination cell merged across
    several terminals, cut exactly at a boundary with no context on either
    side, is unrecoverable — no later stage can tell that the fragment it saw
    was half a cell.
    """
    width, height = image.size
    if width <= settings.chunk_width:
        path = stem.with_name(f"{stem.name}.png")
        image.save(path)
        return [path]

    step = settings.chunk_width - settings.chunk_overlap
    paths: list[Path] = []
    start = 0
    index = 0
    while start < width:
        end = min(start + settings.chunk_width, width)
        path = stem.with_name(f"{stem.name}-{index:02d}.png")
        image.crop((start, 0, end, height)).save(path)
        paths.append(path)
        if end >= width:
            break
        start += step
        index += 1
    return paths


# -------------------------------------------------------------------- stage

def page_regions(
    pdf: Path,
    tokens: PageTokens,
    cache: ArtifactCache,
    settings: RenderSettings,
    *,
    include_title_block: bool = False,
    timeout: int = 180,
) -> PageRegions:
    page = tokens.page
    base_path = render_page(pdf, page, settings.single_line_dpi, cache, timeout)
    base = Image.open(base_path)
    width, height = base.size
    notes: list[str] = []
    regions: dict[str, Region] = {}

    def pct(box: tuple[int, int, int, int], from_size: tuple[int, int]) -> tuple[float, float, float, float]:
        w, h = from_size
        return (box[0] / w, box[1] / h, box[2] / w, box[3] / h)

    # Layout only: enough to see where things sit, never to read a table from.
    context_path = cache.path(page, "context_page.png")
    if not cache.has(page, "context_page.png"):
        context = base.copy()
        context.thumbnail((settings.context_long_edge, settings.context_long_edge), Image.LANCZOS)
        context.save(context_path)
    regions["context_page"] = Region(
        "context_page", context_path, (0, 0, width, height), (0.0, 0.0, 1.0, 1.0),
        settings.context_long_edge,
    )

    table_box = detect_table(base, tokens)
    layout_kind = "table" if table_box else "no_table"
    if table_box is None:
        notes.append("No destination table on this sheet; stage 3 must not expect one.")

    title = tokens.anchors.get("title_block")
    single_line_bottom = table_box[1] if table_box else (
        int(title.y0) if title else height
    )
    pad = round(6 * settings.single_line_dpi / 72)
    single_box = (0, 0, width, max(1, single_line_bottom - pad))
    single_stem = cache.path(page, "single_line")
    single_paths = chunk_width(base.crop(single_box), settings, single_stem)
    regions["single_line"] = Region(
        "single_line", single_paths[0], single_box, pct(single_box, (width, height)),
        settings.single_line_dpi, single_paths,
    )

    if table_box:
        # Re-render at table resolution rather than upscaling the 220dpi page:
        # interpolation invents nothing a model can read.
        hi_path = render_page(pdf, page, settings.table_band_dpi, cache, timeout)
        hi = Image.open(hi_path)
        ratio = settings.table_band_dpi / settings.single_line_dpi
        pad_hi = round(10 * settings.table_band_dpi / 72)
        band_box = (
            max(0, int(table_box[0] * ratio) - pad_hi),
            max(0, int(table_box[1] * ratio) - pad_hi),
            min(hi.size[0], int(table_box[2] * ratio) + pad_hi),
            min(hi.size[1], int(table_box[3] * ratio) + pad_hi),
        )
        band_stem = cache.path(page, "table_band")
        band_paths = chunk_width(hi.crop(band_box), settings, band_stem)
        regions["table_band"] = Region(
            "table_band", band_paths[0], band_box, pct(band_box, hi.size),
            settings.table_band_dpi, band_paths,
        )
        if len(band_paths) > 1:
            notes.append(
                f"Table band is {band_box[2] - band_box[0]}px wide; split into "
                f"{len(band_paths)} overlapping chunks."
            )

    # The title block is byte-identical on every sheet of a set, so it is read
    # once and reused rather than paid for 35 times.
    if include_title_block and title is not None:
        top = title_block_top(base, int(title.y0))
        if top is None:
            top = max(0, int(title.y0) - round(0.10 * height))
            notes.append("Title block border not found; cropped a fixed band above it.")
        tb_box = (0, max(0, top - pad), width, height)
        tb_stem = cache.path(page, "title_block")
        # Rendered afresh at its own resolution: the Hebrew in the title
        # block is what names the board, and it is small.
        with Image.open(render_page(pdf, page, settings.title_block_dpi, cache, timeout)) as fine:
            ratio = fine.size[0] / width
            fine_box = tuple(round(v * ratio) for v in tb_box)
            tb_paths = split_title_block(fine.crop(fine_box), tb_stem)
        regions["title_block"] = Region(
            "title_block", tb_paths[0], tb_box, pct(tb_box, (width, height)),
            settings.title_block_dpi, tb_paths,
        )

    return PageRegions(page, layout_kind, regions, notes)


def zoom_crop(
    pdf: Path,
    page: int,
    bbox_pct: tuple[float, float, float, float],
    cache: ArtifactCache,
    settings: RenderSettings,
    *,
    tag: str,
    timeout: int = 180,
) -> list[Path]:
    """Stage 4's re-crop: the same region again, at 600 dpi.

    Cropping from a fresh high-resolution render rather than upscaling the
    stage 2 crop is the whole point — this pass exists to see detail the
    first pass could not.
    """
    # Only the region is rendered. A whole A4 page at 600 dpi is 7017x4959
    # pixels: pdftoppm peaks near 160 MB drawing it and Pillow needs another
    # 100 MB to open it — most of a 512 MB instance.
    # pdftoppm's own crop yields the identical pixels at a tenth of that.
    with Image.open(render_page(pdf, page, settings.single_line_dpi, cache, timeout)) as base:
        base_w, base_h = base.size
    scale = settings.zoom_dpi / settings.single_line_dpi
    width, height = round(base_w * scale), round(base_h * scale)
    box = (
        max(0, int(bbox_pct[0] * width)),
        max(0, int(bbox_pct[1] * height)),
        min(width, int(bbox_pct[2] * width)),
        min(height, int(bbox_pct[3] * height)),
    )
    if box[2] <= box[0] or box[3] <= box[1]:
        raise ValueError(f"Empty zoom region {bbox_pct} on page {page}.")
    image = render_region(pdf, page, settings.zoom_dpi, box, cache, f"zoom-{tag}-region", timeout)
    stem = cache.path(page, f"zoom-{tag}")
    return chunk_width(image, settings, stem)
