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

## Repository layout

| Path | Purpose |
| --- | --- |
| `ios/` | Native SwiftUI PanelVault iPhone app — the manager app |
| `worker/` | Native SwiftUI worker app: PanelVault's interface with the warehouse in it and creation removed |
| `warehouse/` | Native SwiftUI warehouse companion app and delivery scanner |
| `webapp/` | PanelVault Cloud website, API, accounts, roles, stock, and boards |
| `tools/` | Scripts that assemble the worker app from `ios/` and `warehouse/` |

### How the three iPhone apps relate

`ios/` is the source of truth for the interface and the data model. `worker/` is
a generated copy of it — `tools/split_worker.py` slices
`ios/Runner/SceneDelegate.swift` into files and drops the manager-only screens,
and `tools/port_warehouse.py` copies `warehouse/Sources` in beside them. Neither
`ios/` nor `warehouse/` is modified by this; both still build and ship on their
own. See `worker/README.md`.

## Current capabilities

### PanelVault Cloud

- Company accounts with owner, manager, and worker roles
- Revocable invitation links and team management
- Browser-based stock receiving, consumption, and corrections
- Custom parts, minimum levels, locations, and movement history
- Board creation, assignment, and worker status updates
- Selectable local JSON or guarded Supabase persistence
- Mobile token authentication and cursor-based stock movement synchronization
- Shared sign-in, company creation, and worker invite joining across the
  website and both native iPhone apps

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
18 or newer.

```bash
cd webapp
node server.js
```

Open `http://localhost:8090`. Set `PORT` to use a different port.

For a shared production deployment, use HTTPS and configure the documented
Supabase backend. If the local backend is used, back up `webapp/data/`; it
contains company accounts and movement history and is excluded from Git.

## Production domain and hosting

The registered production domain is **panel-vault.com**, managed through
GoDaddy. The intended layout is:

- `panel-vault.com` — public PanelVault website
- `cloud.panel-vault.com` — authenticated web app and shared iPhone API

DNS has not been cut over yet. The first hosted pilot will deploy the Node web
service from this GitHub repository, terminate HTTPS at the host, and point a
GoDaddy `cloud` record at that service. Runtime data must live on persistent
storage through Supabase or `DATA_DIR`; an ephemeral local deployment would
lose company data on restart. The first Supabase boundary stores a guarded JSON
document, so relational tables and object storage for PDFs/photos are still
required before the system becomes business-critical or scales horizontally.

The planned receipt and scheme AI integration will call the OpenAI Responses
API from PanelVault Cloud. `OPENAI_API_KEY` must be a server environment secret
and must never be embedded in either iPhone app, browser JavaScript, or Git.
Scanned results will always pass through a user review screen before creating
boards or changing stock.

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

This app has not been compiled yet — it was assembled from `ios/` and
`warehouse/` by script. Expect a first pass of small fixes in Xcode.
`python3 tools/check_worker.py` runs the structural checks used while building
it.

## Run the PanelVault app

Open `ios/Runner.xcodeproj` in Xcode, select the `Runner` scheme and choose an
iPhone or simulator. The current iOS app is native SwiftUI and does not require
Flutter, CocoaPods, or the removed `Runner.xcworkspace`. Open **More →
PanelVault Cloud** to sign in, create a company, or join with the worker invite
link generated by the website.

## Roadmap

1. Build the worker app in Xcode, fix whatever the first compile surfaces, and
   put it on a workshop phone alongside the manager app.
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
