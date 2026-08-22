# PanelVault Worker

The workshop-floor app. Same interface as PanelVault, with the warehouse in it
and nothing that creates or renames a record.

## Why it exists

PanelVault (`ios/`) grew up as one app for one person. On a real job there are
two very different users:

- **A manager** sets up the work: new projects, new boards, customers,
  manufacturers, board types, due dates.
- **A worker** does the work: builds the board, ticks the checklists, takes the
  photos, receives the delivery, consumes the parts.

Giving both of them the same app means the person on the floor can rename a
customer or delete a board by accident, and it means the warehouse — the thing
they touch most — is a separate app they have to switch to.

So `ios/` stays as it is and becomes the manager app, and this is a copy of it
with the two changes that matter.

## What is different from `ios/`

**The centre tab is the warehouse, not "+".**

| Tab | Manager app | Worker app |
| --- | --- | --- |
| 1 | Dashboard | Dashboard |
| 2 | Projects | Projects |
| 3 | **New** (project / board hub) | **Warehouse** |
| 4 | Search | Search |
| 5 | More | More |

**Nothing creates or redefines a record.** Removed from the copy:

| Removed | Where it was |
| --- | --- |
| New Project / New Board hub and the whole board wizard | centre tab |
| Project edit sheet, board edit sheet | project and board screens |
| Customers, Manufacturers, Board Types, Companies managers | More → Archive |
| Company switcher | dashboard header |
| Add custom component | equipment catalog |
| Delete project, delete board | rows and detail screens |

**What a worker still changes**, because this is their job:

- Cabinet checklists and their own personal checklist on a board
- Board and project photos, scheme attachments
- The board's finish date and hours worked (`BoardProgressSheet.swift`)
- Everything in the warehouse: receive, consume, adjust, stocktake

A board still counts as finished the same way it always did — the cabinet
checklists reaching 100%, not a switch someone flips.

## The warehouse inside it

The standalone warehouse app (`warehouse/`) is **unchanged**. Its code is copied
into `Sources/Warehouse/` by `tools/port_warehouse.py`, with three differences:

- `WarehouseTheme` became `PanelTheme`, so the warehouse follows whichever skin
  the user picked in More instead of being permanently dark blue.
- Its five tabs (Dashboard, Stock, Receive, Activity, Cloud) became one tab with
  a summary screen; the other four open as sheets, which is how PanelVault
  presents everything else.
- `WarehouseStore.onHand` is cached. PanelVault's equipment catalog asks for a
  part's stock once per row, and replaying the whole movement log per row is
  quadratic — the standalone app never called it that way.

The equipment catalog shows live on-hand stock per part, because
`StockMovement.partID` and `PanelComponent.id` are the same key.

## Run it

```
open worker/Worker.xcodeproj
```

Pick the `Worker` scheme and an iPhone or simulator. Pure SwiftUI, iOS 16+, no
packages. Sign in under **More → PanelVault Cloud**, or from the Cloud button on
the warehouse tab. Scanning delivery notes and barcodes needs a real device;
everything else works in the simulator.

## How this app is built

Most of this app is **generated**, not hand-written — it is a copy of two
existing codebases, so it is assembled by script rather than retyped:

```bash
python3 tools/split_worker.py        # slice ios/Runner/SceneDelegate.swift into Sources/
python3 tools/port_warehouse.py      # copy warehouse/Sources into Sources/Warehouse/
python3 tools/make_worker_project.py # regenerate Worker.xcodeproj from Sources/
python3 tools/check_worker.py        # structural checks (see below)
```

`split_worker.py` holds the list of manager-only declarations. It refuses to run
if a declaration in the PanelVault app is neither routed to a file nor named in
that drop list, so a new screen in `ios/` cannot silently go missing here.

**Re-running the first two scripts overwrites hand edits.** The hand edits made
after generation — removing creation entry points, wiring `BoardProgressSheet`,
swapping the stock store — are already in the files. If you re-run the splitter,
redo them or diff against git.

`check_worker.py` is the compiler stand-in used while building this: brace
balance, duplicate top-level types, and undefined names. It is not a type
checker and will not catch a wrong argument label. The first real build is
Xcode's.

## Known rough edges

- **No app icon.** `Assets.xcassets` is not set up, so the icon slot is empty.
- **Two catalogs in one binary.** `Sources/Catalog.swift` (PanelVault's
  `ComponentGroup`) and `Sources/Warehouse/WarehouseCatalog.swift` (`CatalogPart`)
  both ship. They agree on ids by construction, but they should become one.
- **The archive is still local.** This app reads and writes the same snapshot
  file the manager app does, on its own device. Projects and boards do not sync
  between phones yet — that is Phase 6 in `PLAN.md`. Warehouse stock *does* sync,
  through PanelVault Cloud.
- **Dead code left in on purpose.** The `Creation*` input controls stay because
  the profile editor and cloud sign-in forms use them; the picker sheets that
  only the board wizard used are still there too. Prune them after the first
  green build, not before.
