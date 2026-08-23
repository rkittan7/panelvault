#!/usr/bin/env python3
"""Port warehouse/Sources into the worker app under worker/Sources/Warehouse/.

The warehouse companion app stays exactly where it is; this copies its logic
and screens into the worker app so a worker gets stock, receiving and the
delivery scanner inside the PanelVault interface instead of a second app.

Only three things have to change to live in one target with PanelVault's
design system:

  * `WarehouseTheme` becomes `PanelTheme` (the warehouse theme was a hand copy
    of PanelTheme "Obsidian Blue" anyway, so this also makes the warehouse
    follow the user's chosen skin).
  * `Theme.swift` is dropped — its `GlassCard` and `Color(hex:)` would collide
    with PanelVault's. `SectionHeading` and `StatTile` are re-declared against
    PanelTheme in WarehouseAdapters.swift.
  * `DashboardView` is renamed, because PanelVault already has one.

Run from the repo root:  python3 tools/port_warehouse.py
"""

import os
import re
import sys

SRC = "warehouse/Sources"
OUT = "worker/Sources/Warehouse"

# Dropped: their contents are provided by the PanelVault design system or by
# the worker app's own root view.
#
# CatalogImages.swift is dropped for the same reason: the worker app already
# has `CatalogImageLibrary` from the PanelVault side, and porting the warehouse
# copy would redeclare it in the same target. The views built on top of it live
# in CatalogPartViews.swift, which does get ported.
SKIP = {"Theme.swift", "WarehouseApp.swift", "CatalogImages.swift", "Permissions.swift"}

RENAME_FILES = {
    "Catalog.swift": "WarehouseCatalog.swift",
    "Models.swift": "WarehouseModels.swift",
    "DashboardView.swift": "WarehouseHome.swift",
}

# Whole-word symbol substitutions applied to every ported file.
RENAME_SYMBOLS = {
    "WarehouseTheme": "PanelTheme",
    # PanelVault already declares a DashboardView.
    "DashboardView": "WarehouseHomeView",
}

HEADER = """// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

"""


def main():
    if not os.path.isdir(SRC):
        sys.exit(f"run from the repo root: {SRC} not found")
    os.makedirs(OUT, exist_ok=True)

    for name in sorted(os.listdir(SRC)):
        if not name.endswith(".swift") or name in SKIP:
            continue
        text = open(os.path.join(SRC, name), encoding="utf-8").read()
        for old, new in RENAME_SYMBOLS.items():
            text = re.sub(rf"\b{old}\b", new, text)

        # The store is reached from PanelVault's catalog sheets too, where an
        # @EnvironmentObject that fails to propagate is a crash rather than a
        # blank badge, so it gains a shared instance.
        if name == "WarehouseStore.swift":
            # PanelVault's equipment catalog asks for a part's stock once per
            # row. `onHand` replays the whole movement log, so answering it per
            # row is quadratic in a way the standalone warehouse app never hit.
            # Cache it, invalidated whenever the log changes.
            text = text.replace(
                "  @Published private(set) var movements: [StockMovement] = []\n",
                "  @Published private(set) var movements: [StockMovement] = [] {\n"
                "    didSet { onHandCache = nil }\n"
                "  }\n"
                "\n"
                "  /// Invalidated by the `movements` observer above. See `onHand`.\n"
                "  private var onHandCache: [String: Int]?\n",
                1,
            )
            text = text.replace(
                "  var onHand: [String: Int] {\n"
                "    movements.reduce(into: [:]) { counts, movement in\n"
                "      counts[movement.partID, default: 0] += movement.delta\n"
                "    }\n"
                "  }\n",
                "  var onHand: [String: Int] {\n"
                "    if let onHandCache { return onHandCache }\n"
                "    let counts = movements.reduce(into: [String: Int]()) { counts, movement in\n"
                "      counts[movement.partID, default: 0] += movement.delta\n"
                "    }\n"
                "    onHandCache = counts\n"
                "    return counts\n"
                "  }\n",
                1,
            )
            text = text.replace(
                "final class WarehouseStore: ObservableObject {\n",
                "final class WarehouseStore: ObservableObject {\n"
                "  /// Shared instance. PanelVault's catalog shows on-hand stock from\n"
                "  /// sheets that an @EnvironmentObject does not reliably reach.\n"
                "  static let shared = WarehouseStore()\n\n",
                1,
            )

        # The warehouse app's dashboard is replaced by WarehouseTabView, which
        # adds the actions a single-tab warehouse needs. Only its two row views
        # carry over.
        if name == "DashboardView.swift":
            text = "import SwiftUI\n\n" + text[text.index("struct LowStockRow: View {"):]

        target = RENAME_FILES.get(name, name)
        with open(os.path.join(OUT, target), "w", encoding="utf-8") as handle:
            handle.write(HEADER + text)
        print(f"{name:28s} -> Warehouse/{target}")


if __name__ == "__main__":
    main()
