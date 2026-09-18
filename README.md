# PanelVault

PanelVault is an electrical-board operations platform for contractors,
workshops, managers, and warehouse staff. The goal is one connected system for
planning boards, tracking projects, managing components, and knowing exactly
what is available in the warehouse.

## Product vision

PanelVault is being expanded from an iPhone app into a company platform that
can be used from any computer:

- The **PanelVault app** is the manager's iPhone app. It creates and manages
  projects, boards, customers, manufacturers, components, photos, schemes, and
  board completion.
- The **PanelVault Worker app** is the same interface for the workshop floor:
  the warehouse in place of the creation tab, and nothing that creates or
  renames a record. A worker builds boards, works checklists, takes photos,
  receives deliveries and consumes parts.
- **PanelVault Cloud** gives the boss and managers a browser-based control
  center for the company, warehouse, boards, assignments, and team.
- The **Warehouse iPhone app** is the standalone stock app, for staff who only
  handle parts and never touch a board.
- All clients use the same component IDs and append-only stock movement model,
  which is designed to support reliable company-wide synchronization.

## Delivery-note scanning

The Warehouse iPhone app can scan a delivery paper with the camera. Apple's
on-device Vision framework reads English and Hebrew text, extracts quantities,
and fuzzy-matches each line to the electrical component catalog.

The flow is deliberately:

1. Scan every page of the delivery note.
2. Review the recognized components and quantities.
3. Correct or remove uncertain matches.
4. Confirm the delivery.
5. Add the confirmed receipt movements to warehouse stock immediately.

Nothing changes stock until the user confirms the review screen. Confirmed
receipts are stored on the iPhone first and then synchronized to the correct
PanelVault Cloud company. Uploads are safe to retry: movement IDs are
deduplicated by the server, so a delivery cannot be counted twice.

Confirming also records the delivery itself — note number, supplier, page
count, and every line the camera read, including the ones the worker chose not
to receive. That batch uploads alongside the movements, and the Deliveries page
in PanelVault Cloud shows the paperwork behind any receipt. The scanned page
images still stay on the phone until the delivery uploader is connected to the
private object store already used by board PDFs and photos; the website reports
the page count so it is clear what it does not yet hold.

## Creating a board from the AutoCAD scheme

Creating a board starts with the drawing, because the drawing is what the board
is. New Board opens on a single step: attach the scheme PDF exported from
AutoCAD. PanelVault sends it to PanelVault Cloud, Gemini reads the PDF natively
— pages, title block and every schematic device reference, no rasterising or
OCR — and the reading comes back as board details plus a counted parts list.
The final parts/legend page can clarify a model, but quantities come from unique
devices actually instantiated across the schematic. Only then does the form
appear, pre-filled, as a review of what was read.

Entering the board by hand is one tap away on that same screen, for when the
scheme is not ready.

Three rules keep the reading honest, because a board draft gets built:

- **The model reports, it does not infer.** A field the drawing does not state
  comes back empty and stays as the form's default. An empty field costs
  seconds to fill; a confident wrong one gets built into a panel.
- **Ambiguous parts are not placed.** A schedule line only becomes a catalog
  part when the model agrees and, whenever the drawing names a brand, the brand
  agrees too. Anything else is listed on the draft in amber as unplaced, for a
  person to resolve. The board's component types come only from lines that did
  match.
- **Nothing is created until a person confirms.** The endpoint writes nothing;
  it reads the PDF and returns. The board exists when someone taps Create.

The drawing is attached to the board either way, so the workshop has the scheme
whether or not the reading succeeded.

`POST /api/ai/board-scheme` needs `GEMINI_API_KEY` set on the server, and the
phone needs to be signed in to PanelVault Cloud (More → sign in). Without
either, the app says so and offers the manual form rather than pretending.
The matching rules live in `webapp/scheme.js` and are covered by
`webapp/scheme.test.js`.

## Roles and permissions

One definition, on the server. `capabilitiesFor()` in `webapp/server.js` decides
what an account may do, and both the website (`/api/state`) and the phones
(`/api/mobile/login`) are handed the same block:

| Capability | Roles |
| --- | --- |
| `administer` — change stock, manage parts, teach barcodes, create and assign boards | Owner, Manager, Staff Manager |
| `seeCosts` — unit prices, stock value, board cost | Owner, Manager |
| `signOffQA` | Owner, Manager, Staff Manager, QA |
| `manageMembers` | Owner |

The apps used to re-derive this from the role name as `owner || manager`, in six
separate places, which locked **Staff Managers** out of stocktakes, part
creation and barcode teaching that PanelVault Cloud has always allowed them.
They now read the capabilities the server sent, so the phone permits exactly
what the server will accept.

`PanelCapabilities.forRole` in `warehouse/Sources/Permissions.swift` carries the
same rules for an account cached before the server sent them, or one signed in
against an older PanelVault Cloud. A test in `webapp/server.test.js` reads that
Swift file and fails if it stops matching `server.js`, so the two cannot drift.

Signed out, the phone allows everything: it is a local notebook, and the sync is
what enforces the account's limits.

## Component and manufacturer photos

Every component and every manufacturer can carry a picture, and all four
surfaces read the same one. The files live in `assets/catalog` — logos in
`manufacturers/`, part photos in `components/` — and are referenced, never
copied: PanelVault Cloud serves the folder at `/catalog-images/`, and the three
Xcode projects bundle it as a folder reference. One file in the repository,
four places it shows up.

Adding photos is two steps: drop them in the folder, then run

```bash
python3 tools/sync_catalog_images.py
```

which matches each file to a catalog id — exact ids like `abb-s201-1p.jpg`
always win, and loose names like `ABB S201 1P.jpg` or `ABB logo.png` are
resolved by matching against the catalog — and writes the `index.json` manifest
that every surface reads. Files it cannot place, or that could mean more than
one part, are reported rather than guessed at. See
[assets/catalog/README.md](assets/catalog/README.md) for the naming rules.

These pictures are defaults. A photo someone takes on their phone is stored on
that device and always wins over the catalog photo; a part with neither keeps
the SF Symbol for its category, exactly as before.

The brand list is read out of `worker/Sources/Models.swift` rather than copied
into the tool, and it covers both `ManufacturerItem.defaults` and
`EquipmentCompany.all` — the pool the board manufacturer and main-breaker
pickers draw from. A brand that only ever appears on an enclosure is a
manufacturer like any other and gets a logo the same way, and adding one to the
Swift means the tool counts it with no second edit here.

## The catalog

All four surfaces browse the same catalog: 334 parts in eighteen categories.

`warehouse/Sources/Catalog.swift` is the machine-written form of the app's
component catalog and is the source `webapp/catalog.json` is generated from:

```bash
python3 tools/gen_web_catalog.py           # rewrite webapp/catalog.json
python3 tools/gen_web_catalog.py --check   # fail if it is out of date
```

That carries each part's `group` and `groupName` across, which is what lets
PanelVault Cloud show the catalog the way the apps do — a grid of the eighteen
categories, then the parts inside one, with a search that cuts across all of
them. Selecting a part shows its photo, description and specification, and the
boss or a manager can start tracking it in the warehouse from there.

Part ids are the key linking warehouse stock to boards across every client, so
the generator never invents or rewrites one: it refuses to run if a part id
already present in `catalog.json` is missing from the Swift.

## The app icon

The manager app and the worker app share one mark: four breaker rails with a
lightning bolt cut through them. The gap around the bolt is part of the drawing
— it is what makes the rails and the bolt read as one object rather than a bolt
sitting on stripes.

The two apps are told apart by colour alone, never by shape:

| App | Ground | Mark |
| --- | --- | --- |
| PanelVault (manager) | control-room blue `#3B6BFF` → `#0A2296` | white |
| PanelVault Worker | hi-vis amber `#FFC61F` → `#F58400` | near-black `#14181B` |

Amber with a dark mark is how the warning labels already on a cabinet are
printed, so the app on the workshop floor is recognisable from across the room
and still obviously the same system as the one in the office.

`assets/brand/` holds the SVG masters. The iPhone icons are not converted from
them — a Mac with only the Command Line Tools has no SVG rasteriser — but
redrawn in CoreGraphics from the same numbers:

```bash
swift tools/make_app_icons.swift manager ios/Runner/Assets.xcassets/AppIcon.appiconset
swift tools/make_app_icons.swift worker  worker/Assets.xcassets/AppIcon.appiconset
```

Each run writes all 15 PNG slots and the `Contents.json` that names them. The
geometry lives in both `assets/brand/panelvault-mark.svg` and
`tools/make_app_icons.swift`; move a rail in one and move it in the other.

## Repository layout

| Path | Purpose |
| --- | --- |
| `ios/` | Native SwiftUI PanelVault iPhone app — the manager app |
| `worker/` | Native SwiftUI worker app: PanelVault's interface with the warehouse in it and creation removed |
| `warehouse/` | Native SwiftUI warehouse companion app and delivery scanner |
| `webapp/` | PanelVault Cloud website, API, accounts, roles, stock, and boards |
| `assets/catalog/` | Component and manufacturer photos shared by all four surfaces |
| `assets/brand/` | SVG masters for the PanelVault mark and both app colourways |
| `tools/` | Scripts that assemble the worker app from `ios/` and `warehouse/`, and cut the app icons |

### How the three iPhone apps relate

`ios/` is the source of truth for the interface and the data model. `worker/` is
a generated copy of it — `tools/split_worker.py` slices
`ios/Runner/SceneDelegate.swift` into files and drops the manager-only screens,
and `tools/port_warehouse.py` copies `warehouse/Sources` in beside them. Neither
`ios/` nor `warehouse/` is modified by this; both still build and ship on their
own. See `worker/README.md`.

## Current capabilities

### PanelVault Cloud

- Company accounts with owner, manager, staff manager, QA, and staff roles
- Revocable invitation links and team management
- Browser-based stock receiving, consumption, and corrections
- Delivery history: every confirmed note with its read lines and the stock it
  created, including lines the worker rejected
- Custom parts, minimum levels, locations, and movement history
- Board creation, assignment, and worker status updates
- Manager-only stock valuation, component pricing, and per-board cost summaries
- Selectable local JSON or guarded Supabase persistence
- Mobile token authentication and cursor-based stock movement synchronization
- Shared sign-in, company creation, and worker invite joining across the
  website and both native iPhone apps

### Worker app

- Workshop-safe project and board views with creation, renaming, and deletion
  paths removed
- Cabinet and personal checklists, progress, hours, photos, and scheme files
- Embedded receiving, consumption, stocktake, and warehouse activity tools
- Live company stock in the component catalog, including component serial
  numbers
- PanelVault Cloud sign-in with secure Keychain session storage

### Warehouse app

- Shared PanelVault electrical-component catalog
- Custom warehouse parts
- On-hand stock derived from an append-only movement log
- Delivery-note camera scanning and on-device OCR
- Scan review before stock is committed
- Manual receiving, usage, corrections, history, and low-stock tracking
- PanelVault Cloud sign-in, secure Keychain sessions, pending upload status,
  and automatic sync when the app opens or returns to the foreground
- Barcode opening stocktake with reusable box-to-component mappings and
  reviewed counted-versus-recorded adjustments

## Run PanelVault Cloud

PanelVault Cloud has no third-party runtime dependencies and requires Node.js
20 or newer.

```bash
cd webapp
npm start
```

Open `http://localhost:8090`. Set `PORT` to use a different port.
Run the API and storage tests with `npm test`.

For a shared production deployment, use HTTPS and configure the documented
Supabase backend. If the local backend is used, back up `webapp/data/`; it
contains company accounts and movement history and is excluded from Git.

## Production domain and hosting

The registered production domain is **panel-vault.com**, managed through
GoDaddy. The intended layout is:

- `panel-vault.com` — public PanelVault website
- `cloud.panel-vault.com` — authenticated web app and shared iPhone API

DNS has not been cut over yet. The repository includes `render.yaml` for a
Render deployment of `webapp/`, including the `/api/health` health check.
Configure the documented Supabase secrets before deploying, then point the
GoDaddy `cloud` record at the Render service. Runtime data must live on
persistent storage through Supabase or `DATA_DIR`; an ephemeral local
deployment would lose company data on restart. The first Supabase boundary
stores a guarded JSON document, so relational tables and object storage for
PDFs/photos are still required before the system becomes business-critical or
scales horizontally.

PanelVault Cloud exposes the authenticated `POST /api/ai/generate` endpoint for
its receipt and scheme AI features. Configure `GEMINI_API_KEY` as a server
environment secret (and optionally `GEMINI_MODEL`, which defaults to
`gemini-3.6-flash`). The key must never be embedded in either iPhone app,
browser JavaScript, or Git. Scanned results must always pass through a user
review screen before creating boards or changing stock.

## Run the Warehouse app

Open `warehouse/Warehouse.xcodeproj` in Xcode and run the `Warehouse` scheme.
The app is pure SwiftUI and targets iOS 16 or newer. Use a physical iPhone to
test document scanning; manual receiving works in the simulator.

Open the Cloud tab to sign in, create a company, or paste a worker invite link
from the website. For local iPhone testing, use the Mac's Wi-Fi address such as
`http://192.168.1.20:8090`, not `localhost`.

## Run the Worker app

Open `worker/Worker.xcodeproj` in Xcode and run the `Worker` scheme. Pure
SwiftUI, iOS 16 or newer, no packages. Sign in under **More → PanelVault Cloud**
so warehouse stock syncs. Delivery-note and barcode scanning need a physical
iPhone.

The generated Xcode project and source split are committed. Run
`python3 tools/check_worker.py` after changing the manager or warehouse source
to verify the generated Worker app structure.

## Run the PanelVault app

Open `ios/Runner.xcodeproj` in Xcode, select the `Runner` scheme and choose an
iPhone or simulator. The current iOS app is native SwiftUI and does not require
Flutter, CocoaPods, or the removed `Runner.xcworkspace`. Open **More →
PanelVault Cloud** to sign in, create a company, or join with the worker invite
link generated by the website.

## Roadmap

1. Put the Worker app on a workshop phone alongside the manager app and test
   the role boundaries in day-to-day use.
2. Use the barcode stocktake on the real warehouse boxes and refine the first
   company component list.
3. Deploy PanelVault Cloud at `cloud.panel-vault.com` with HTTPS and durable
   storage.
4. Store scanned delivery batches and their source pages in PanelVault Cloud.
5. Add reviewed AI extraction for receipts and electrical schemes.
6. Synchronize projects, boards, customers, photos, PDFs, and checklists between
   the manager app, the worker app, and PanelVault Cloud. Until this lands, the
   worker app reads its own device's archive only.
7. Sync board component usage back to warehouse consumption, so ticking a board
   checklist can create the consumption movements.
8. Add purchase orders and delivery reconciliation.

More implementation details are available in `worker/README.md`,
`webapp/README.md` and `warehouse/README.md`.
