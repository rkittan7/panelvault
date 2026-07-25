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

Nothing changes stock until the user confirms the review screen. At present,
the confirmed scan updates the warehouse data stored on that iPhone. Sending
those movements to PanelVault Cloud so the boss sees the same stock from any
computer is the next synchronization milestone.

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

### Warehouse app

- Shared PanelVault electrical-component catalog
- Custom warehouse parts
- On-hand stock derived from an append-only movement log
- Delivery-note camera scanning and on-device OCR
- Scan review before stock is committed
- Manual receiving, usage, corrections, history, and low-stock tracking

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

## Run the Warehouse app

Open `warehouse/Warehouse.xcodeproj` in Xcode and run the `Warehouse` scheme.
The app is pure SwiftUI and targets iOS 16 or newer. Use a physical iPhone to
test document scanning; manual receiving works in the simulator.

## Run the PanelVault app

Open `ios/Runner.xcodeproj` in Xcode, select the `Runner` scheme and choose an
iPhone or simulator. The current iOS app is native SwiftUI and does not require
Flutter, CocoaPods, or the removed `Runner.xcworkspace`.

## Roadmap

1. Add authenticated synchronization between the Warehouse app and PanelVault
   Cloud.
2. Push confirmed delivery-note movements to the company warehouse so stock
   updates appear on the website immediately.
3. Sync board component usage back to warehouse consumption.
4. Add conflict-safe offline merging by movement ID.
5. Add purchase orders and delivery reconciliation.

More implementation details are available in `webapp/README.md` and
`warehouse/README.md`.
