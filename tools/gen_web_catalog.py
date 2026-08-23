#!/usr/bin/env python3
"""Generate webapp/catalog.json from the app's component catalog.

warehouse/Sources/Catalog.swift is the machine-written form of PanelVault's
`ComponentGroup.samples` — the same parts, the same ids, already grouped into
the categories the apps browse by. This reads it and writes the JSON
the website serves, so PanelVault Cloud's catalog is the app's catalog rather
than a flat list that has to be kept in step by hand.

Part ids are the key that links warehouse stock to boards across all four
surfaces, so this never invents or rewrites one: it only carries across what
the Swift declares, plus the category each part already sits in.

Run from the repo root:

    python3 tools/gen_web_catalog.py           # rewrite webapp/catalog.json
    python3 tools/gen_web_catalog.py --check   # exit 1 if it is out of date
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_SWIFT = os.path.join(ROOT, "warehouse", "Sources", "Catalog.swift")
CATALOG_JSON = os.path.join(ROOT, "webapp", "catalog.json")

GROUP = re.compile(r'CatalogGroup\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*parts:\s*\[')
PART = re.compile(
    r'CatalogPart\('
    r'id:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'manufacturer:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'type:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'model:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'rating:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'poles:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'curve:\s*"((?:[^"\\]|\\.)*)",\s*'
    r'about:\s*"((?:[^"\\]|\\.)*)"\s*\)'
)

FIELDS = ("id", "manufacturer", "type", "model", "rating", "poles", "curve", "about")


def unescape(value):
    """Swift string literal -> the text it stands for."""
    return value.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")


def parse_catalog():
    """[part dict] in declaration order, each tagged with its group."""
    with open(CATALOG_SWIFT, encoding="utf-8") as handle:
        source = handle.read()

    # Group headers split the file; every part between two headers belongs to
    # the one above it. Simpler and far more robust than trying to balance
    # brackets across 199 multi-line literals.
    headers = list(GROUP.finditer(source))
    if not headers:
        sys.exit(f"no CatalogGroup found in {CATALOG_SWIFT}")

    parts = []
    for index, header in enumerate(headers):
        start = header.end()
        end = headers[index + 1].start() if index + 1 < len(headers) else len(source)
        for match in PART.finditer(source, start, end):
            part = dict(zip(FIELDS, (unescape(v) for v in match.groups())))
            part["group"] = header.group(1)
            part["groupName"] = header.group(2)
            parts.append(part)
    return parts


def render(parts):
    """The exact bytes webapp/catalog.json should hold.

    One object per line-block, matching the file's existing shape so a
    regeneration that changes nothing produces no diff.
    """
    body = ",\n".join(
        "{\n" + ",\n".join(f'"{key}": {json.dumps(part[key], ensure_ascii=False)}'
                           for key in (*FIELDS, "group", "groupName")) + "\n}"
        for part in parts
    )
    return "[\n" + body + "\n]\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="verify webapp/catalog.json matches the Swift catalog")
    parser.add_argument("--allow-drop", action="store_true",
                        help="permit removing part ids that catalog.json still "
                             "lists; only for a part added in error that no "
                             "stock line or board can yet reference")
    args = parser.parse_args()

    parts = parse_catalog()

    ids = [part["id"] for part in parts]
    duplicates = {pid for pid in ids if ids.count(pid) > 1}
    if duplicates:
        sys.exit(f"duplicate part ids in the Swift catalog: {', '.join(sorted(duplicates))}")

    # The ids are load-bearing across four apps; refuse to silently drop any.
    try:
        with open(CATALOG_JSON, encoding="utf-8") as handle:
            existing = json.load(handle)
        missing = {part["id"] for part in existing} - set(ids)
        if missing and not args.allow_drop:
            sys.exit(
                f"{len(missing)} part id(s) in catalog.json are not in the Swift "
                f"catalog, which would break stock and boards that reference "
                f"them: {', '.join(sorted(missing)[:5])}…\n"
                f"If these were added in error and nothing can reference them "
                f"yet, re-run with --allow-drop."
            )
        if missing:
            # Named in full rather than counted: dropping an id is the one thing
            # here that can strand data, so it belongs in the run's output.
            print(f"dropping {len(missing)} part id(s): {', '.join(sorted(missing))}")
    except FileNotFoundError:
        pass

    rendered = render(parts)

    if args.check:
        with open(CATALOG_JSON, encoding="utf-8") as handle:
            if handle.read() != rendered:
                sys.exit("webapp/catalog.json is out of date — run "
                         "python3 tools/gen_web_catalog.py")
        print(f"webapp/catalog.json is up to date ({len(parts)} parts)")
        return

    with open(CATALOG_JSON, "w", encoding="utf-8") as handle:
        handle.write(rendered)

    groups = {}
    for part in parts:
        groups.setdefault(part["groupName"], 0)
        groups[part["groupName"]] += 1
    print(f"webapp/catalog.json — {len(parts)} parts in {len(groups)} categories")
    for name, count in groups.items():
        print(f"  {count:>4}  {name}")


if __name__ == "__main__":
    main()
