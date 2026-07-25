# PanelVault Warehouse

Companion iPhone app for PanelVault: stock levels for the parts the workshop
actually builds with, keyed to the **same component ids** as PanelVault's
catalog, so boards and stock can be linked.

## Run it

Open `Warehouse.xcodeproj` in Xcode, pick an iPhone simulator, ⌘R.
No CocoaPods, no packages — pure SwiftUI, iOS 16+.

The scan flow needs a real camera, so test scanning on a physical device;
manual receive works everywhere.

## Architecture notes

- **Movement log, not quantities.** `movements.json` is an append-only log of
  receive / consume / adjust events; on-hand counts are derived by replaying
  it. This is deliberate: when company-wide sync arrives (boss's computer,
  multiple phones), independent logs merge by event id — a mutable
  "quantity: 37" cannot.
- **Catalog is generated.** `Sources/Catalog.swift` is produced from
  PanelVault's `ComponentGroup.samples` so part ids never drift between the
  apps. Do not edit it by hand.
- **Scan → review → confirm.** OCR (Vision, on-device, English + Hebrew) reads
  the delivery note, the parser extracts quantities and fuzzy-matches lines to
  the catalog, and a review screen is the gate — nothing touches the stock log
  until the user confirms.

## Not built yet, by design

- Sync/backend (the movement log is shaped for it)
- App Group data sharing with PanelVault on-device
- Purchase orders and delivery reconciliation
