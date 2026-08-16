# PanelVault

PanelVault is an electrical-board operations platform for contractors,
workshops, managers, and warehouse staff. The goal is one connected system for
planning boards, tracking projects, managing components, and knowing exactly
what is available in the warehouse.

## Product vision

PanelVault is being expanded from an iPhone app into a company platform that
can be used from any computer:

- The **PanelVault app** manages projects, boards, customers, manufacturers,
  components, photos, schemes, and board completion.
- **PanelVault Cloud** gives the boss and managers a browser-based control
  center for the company, warehouse, boards, assignments, and team.
- The **Warehouse iPhone app** lets workshop staff receive, consume, and
  correct stock where the physical parts are handled.
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
| `ios/` | Main native SwiftUI PanelVault iPhone app |
| `warehouse/` | Native SwiftUI warehouse companion app and delivery scanner |
| `webapp/` | PanelVault Cloud website, API, accounts, roles, stock, and boards |

## Current capabilities

### PanelVault Cloud

- Company accounts with owner, manager, and worker roles
- Revocable invitation links and team management
- Browser-based stock receiving, consumption, and corrections
- Custom parts, minimum levels, locations, and movement history
- Board creation, assignment, and worker status updates
- Persistent company data with atomic JSON writes
- Mobile token authentication and cursor-based stock movement synchronization

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

For a shared production deployment, use HTTPS and back up `webapp/data/`.
That directory contains the company accounts and movement history and is
intentionally excluded from Git.

## Production domain and hosting

The registered production domain is **panel-vault.com**, managed through
GoDaddy. The intended layout is:

- `panel-vault.com` — public PanelVault website
- `cloud.panel-vault.com` — authenticated web app and shared iPhone API

DNS has not been cut over yet. The first hosted pilot will deploy the Node web
service from this GitHub repository, terminate HTTPS at the host, and point a
GoDaddy `cloud` record at that service. Runtime data must live on persistent
storage through `DATA_DIR`; an ephemeral deployment would lose company data on
restart. PostgreSQL and object storage for PDFs/photos are required before the
system becomes business-critical.

The planned receipt and scheme AI integration will call the OpenAI Responses
API from PanelVault Cloud. `OPENAI_API_KEY` must be a server environment secret
and must never be embedded in either iPhone app, browser JavaScript, or Git.
Scanned results will always pass through a user review screen before creating
boards or changing stock.

## Run the Warehouse app

Open `warehouse/Warehouse.xcodeproj` in Xcode and run the `Warehouse` scheme.
The app is pure SwiftUI and targets iOS 16 or newer. Use a physical iPhone to
test document scanning; manual receiving works in the simulator.

Open the Cloud tab and enter the server address, company code, user name, and
password. For local iPhone testing, use the Mac's Wi-Fi address such as
`http://192.168.1.20:8090`, not `localhost`.

## Run the PanelVault app

Open `ios/Runner.xcodeproj` in Xcode, select the `Runner` scheme and choose an
iPhone or simulator. The current iOS app is native SwiftUI and does not require
Flutter, CocoaPods, or the removed `Runner.xcworkspace`.

## Roadmap

1. Use the barcode stocktake on the real warehouse boxes and refine the first
   company component list.
2. Deploy PanelVault Cloud at `cloud.panel-vault.com` with HTTPS and durable
   storage.
3. Store scanned delivery batches and their source pages in PanelVault Cloud.
4. Add reviewed AI extraction for receipts and electrical schemes.
5. Synchronize projects, boards, customers, photos, PDFs, and checklists from
   the main PanelVault app.
6. Sync board component usage back to warehouse consumption.
7. Add purchase orders and delivery reconciliation.

More implementation details are available in `webapp/README.md` and
`warehouse/README.md`.
