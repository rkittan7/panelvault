#!/usr/bin/env python3
"""Match the photos in assets/catalog to catalog ids and write index.json.

assets/catalog is the single source of truth for component and manufacturer
photos. PanelVault Cloud serves the folder over HTTP and all three iPhone apps
reference it as a bundle folder, so nothing here is ever copied — this script
only decides *which id each file belongs to* and records that in index.json.
The website and the apps read that manifest; a file the manifest does not list
is invisible to them.

Run from the repo root:

    python3 tools/sync_catalog_images.py            # report and write index.json
    python3 tools/sync_catalog_images.py --rename   # also rename files to ids
    python3 tools/sync_catalog_images.py --check    # exit 1 if anything is unmatched
"""

import argparse
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "catalog")
COMPONENTS_DIR = os.path.join(ASSETS, "components")
MANUFACTURERS_DIR = os.path.join(ASSETS, "manufacturers")
CATALOG_JSON = os.path.join(ROOT, "webapp", "catalog.json")
INDEX_JSON = os.path.join(ASSETS, "index.json")
MODELS_SWIFT = os.path.join(ROOT, "worker", "Sources", "Models.swift")

EXTENSIONS = (".png", ".jpg", ".jpeg", ".heic", ".webp")

# Read out of Models.swift rather than copied here, so this tool cannot drift
# from the app when a brand is added:
#
#   ManufacturerItem.defaults  the manufacturer tiles, which is also the pool
#                              the board manufacturer and main-breaker pickers
#                              draw from
#   EquipmentCompany.all       brands offered on a board that need not carry a
#                              catalog part of their own
#
# Both lists matter. A board's manufacturer is a manufacturer like any other —
# it shows the same badge on a board card that a part's brand shows in the
# catalog — so a brand that only ever appears on an enclosure still gets a logo.
MANUFACTURER_SOURCES = (
    (r"static let defaults = \[(.*?)\n  \]",
     r'ManufacturerItem\(id:\s*"[^"]+",\s*name:\s*"([^"]+)"'),
    (r"enum EquipmentCompany\s*\{\s*static let all = \[(.*?)\]",
     r'"([^"]+)"'),
)

# Dropped from a filename before matching, so "ABB logo.png" and "ABB.png" are
# the same request. Ordered longest-first: "product photo" must lose "photo"
# and "product" both.
NOISE_WORDS = (
    "logo", "logos", "brand", "mark", "icon",
    "photo", "photos", "picture", "product", "image", "img",
    "final", "copy", "small", "large", "transparent", "white", "black",
)


def slug(text):
    """Lowercase, alphanumeric, hyphen-separated — the shape of a catalog id."""
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")


def strip_noise(stem):
    """`ABB logo (1)` -> `abb`. Trailing counters and noise words go away."""
    parts = [p for p in slug(stem).split("-") if p]
    while parts and (parts[-1] in NOISE_WORDS or parts[-1].isdigit()):
        parts.pop()
    while parts and parts[0] in NOISE_WORDS:
        parts.pop(0)
    return "-".join(parts)


def load_catalog():
    with open(CATALOG_JSON, encoding="utf-8") as handle:
        return json.load(handle)


def app_manufacturers():
    """Brand names declared in the apps: manufacturer tiles and board brands."""
    try:
        with open(MODELS_SWIFT, encoding="utf-8") as handle:
            source = handle.read()
    except OSError:
        return []

    names = []
    for block_pattern, name_pattern in MANUFACTURER_SOURCES:
        block = re.search(block_pattern, source, re.S)
        if block:
            names.extend(re.findall(name_pattern, block.group(1)))
    return names


def manufacturer_keys(parts):
    """slug -> display name for every brand any surface can show.

    Three sources, deduplicated by slug: the manufacturer tiles, the board
    manufacturer list, and whatever brands the component catalog actually
    carries. `HAGER` and `Hager` are one brand and share one logo file.
    """
    known = {}
    for name in app_manufacturers():
        if name.strip():
            known.setdefault(slug(name), name.strip())
    for part in parts:
        name = (part.get("manufacturer") or "").strip()
        if name:
            known.setdefault(slug(name), name)
    return known


def component_keys(parts):
    """Alias slug -> set of component ids that alias could mean.

    Aliases are deliberately generous — the id, the model on its own, and the
    manufacturer combined with the model and poles — because the person taking
    the photos names files after what is printed on the box, not after an id
    they have never seen. Anything that lands on more than one id is reported
    as ambiguous instead of guessed.
    """
    aliases = defaultdict(set)
    for part in parts:
        pid = part["id"]
        manufacturer = part.get("manufacturer", "")
        model = part.get("model", "")
        poles = part.get("poles", "")
        candidates = {
            pid,
            slug(model),
            slug(f"{manufacturer} {model}"),
            slug(f"{manufacturer} {model} {poles}"),
            slug(f"{model} {poles}"),
        }
        for candidate in candidates:
            if candidate:
                aliases[candidate].add(pid)
    return aliases


def image_files(directory):
    if not os.path.isdir(directory):
        return []
    return sorted(
        name for name in os.listdir(directory)
        if name.lower().endswith(EXTENSIONS) and not name.startswith(".")
    )


def resolve(name, exact_ids, aliases):
    """(id, reason) for a filename, or (None, reason) when it cannot be placed."""
    stem, _ = os.path.splitext(name)

    if slug(stem) in exact_ids:
        return slug(stem), "id"

    key = strip_noise(stem)
    if not key:
        return None, "empty name"
    if key in exact_ids:
        return key, "id"

    matches = aliases.get(key, set())
    if len(matches) == 1:
        return next(iter(matches)), "name"
    if len(matches) > 1:
        return None, "ambiguous: " + ", ".join(sorted(matches))
    return None, "no catalog match"


def collect(directory, kind, exact_ids, aliases, rename):
    """Resolve every file in one folder. Returns (manifest, problems)."""
    manifest = {}
    problems = []
    claimed = {}

    resolutions = []
    for name in image_files(directory):
        resolved, reason = resolve(name, exact_ids, aliases)
        if not resolved:
            problems.append(f"{kind}/{name}: {reason}")
        else:
            resolutions.append((name, resolved, reason))

    # A file named with an exact id claims that id ahead of any file that only
    # matched by name, whatever order the directory listing came back in.
    resolutions.sort(key=lambda item: (item[2] != "id", item[0]))

    for name, resolved, _ in resolutions:
        if resolved in claimed:
            problems.append(
                f"{kind}/{name}: {resolved} already taken by {claimed[resolved]}"
            )
            continue

        filename = name
        if rename:
            wanted = resolved + os.path.splitext(name)[1].lower()
            if wanted != name:
                os.rename(
                    os.path.join(directory, name), os.path.join(directory, wanted)
                )
                filename = wanted

        claimed[resolved] = filename
        manifest[resolved] = f"{kind}/{filename}"

    return dict(sorted(manifest.items())), problems


def content_stamps(*manifests):
    """relative path -> short hash of that file's bytes.

    Keyed by path rather than by catalog id so one map covers both logos and
    component photos, and so a caller holding only a path can look it up.
    """
    stamps = {}
    for manifest in manifests:
        for relative in manifest.values():
            full = os.path.join(ASSETS, relative)
            try:
                with open(full, "rb") as handle:
                    stamps[relative] = hashlib.sha256(handle.read()).hexdigest()[:10]
            except OSError:
                # Listed but unreadable: the website falls back to the bare
                # path, which is what it did before stamps existed.
                continue
    return dict(sorted(stamps.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rename", action="store_true",
                        help="rename matched files to their canonical catalog id")
    parser.add_argument("--check", action="store_true",
                        help="exit non-zero if any file could not be matched")
    args = parser.parse_args()

    if not os.path.isfile(CATALOG_JSON):
        sys.exit(f"catalog not found: {CATALOG_JSON}")

    parts = load_catalog()
    manufacturers = manufacturer_keys(parts)
    aliases = component_keys(parts)
    part_ids = {part["id"] for part in parts}

    os.makedirs(COMPONENTS_DIR, exist_ok=True)
    os.makedirs(MANUFACTURERS_DIR, exist_ok=True)

    logos, logo_problems = collect(
        MANUFACTURERS_DIR, "manufacturers",
        set(manufacturers), {key: {key} for key in manufacturers}, args.rename,
    )
    photos, photo_problems = collect(
        COMPONENTS_DIR, "components", part_ids, aliases, args.rename,
    )

    index = {
        "note": "Generated by tools/sync_catalog_images.py — do not edit by hand.",
        "manufacturers": logos,
        "components": photos,
        # A short content stamp per file, keyed by the same relative path the
        # two maps above point at. A photo is replaced under the name it
        # already had, so nothing in the path changes when the bytes do; the
        # website hangs this on the image URL so a browser holding the previous
        # file cannot serve it back. The iPhone apps read the files straight
        # out of the bundle and ignore this key.
        "versions": content_stamps(logos, photos),
    }
    with open(INDEX_JSON, "w", encoding="utf-8") as handle:
        json.dump(index, handle, indent=2, sort_keys=False, ensure_ascii=False)
        handle.write("\n")

    print(f"manufacturers  {len(logos)}/{len(manufacturers)} have a logo")
    print(f"components     {len(photos)}/{len(part_ids)} have a photo")

    missing_brands = [
        name for key, name in sorted(manufacturers.items()) if key not in logos
    ]
    if missing_brands:
        print("\nno logo yet: " + ", ".join(missing_brands))

    problems = logo_problems + photo_problems
    if problems:
        print(f"\n{len(problems)} file(s) not placed:")
        for problem in problems:
            print(f"  {problem}")
        print("\nRename these to a catalog id from webapp/catalog.json, "
              "or run with --rename after fixing the ambiguous ones.")

    print(f"\nwrote {os.path.relpath(INDEX_JSON, ROOT)}")

    if args.check and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
