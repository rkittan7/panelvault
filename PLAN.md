# PanelVault Development Plan

## Goal

Build one connected PanelVault platform for electrical-board companies:

- Workers use the PanelVault Worker iPhone app in the warehouse and workshop.
- The boss and managers use PanelVault Cloud from any computer.
- Projects, boards, components, warehouse stock, and activity share the same
  company data.
- A scanned delivery note can update warehouse stock after a worker reviews
  and confirms the recognized items.

## Pilot readiness update (24 August 2026)

- The Cloud bundle is module-checked and fresh-loaded in Chromium in CI; the
  sign-in screen must render with no console or runtime errors.
- Projects and boards carry per-record revisions. The incremental workspace
  change API deduplicates `changeID`, merges edits to different records, and
  returns the current server record on a same-record `409`.
- The legacy Manager client no longer retries a conflict by resending its stale
  complete workspace after downloading a newer version.
- Production security headers and persistent audit records cover account,
  role, board, and stock administration.
- Board attachments use private object storage and now record storage key,
  MIME type, size, checksum, uploader, and timestamps.
- The normalized Supabase target schema exists, but the compatibility JSON
  document remains the live runtime store until a controlled backfill and
  dual-write migration is completed.
- The one-company release gates and external operations are tracked in
  `PILOT_RUNBOOK.md`.

## Guiding principles

- Stock changes are append-only movements, not directly edited totals.
- Every movement has a unique ID so retries cannot count the same delivery
  twice.
- Scanning never changes stock before human review and confirmation.
- The warehouse app remains useful offline.
- Every important action records who performed it and when.
- Build and verify one complete workflow before expanding the interface.

## Phase 0: Digitize the existing warehouse

**Status: first barcode stocktake workflow implemented (August 2026).**

- Scan EAN, UPC, Code 39/93/128, ITF-14, Data Matrix, QR, and PDF417 labels.
- Teach an unknown barcode its component, exact box label, and units per box.
- Reuse and synchronize that mapping for the whole company.
- Count repeated boxes without changing live stock during scanning.
- Review counted quantities against recorded quantities.
- Confirm the opening stock as auditable adjustment movements.
- Upload custom parts before their barcode mappings and stock movements.

Next, run this workflow against representative ABB, Schneider, Siemens, and
other real boxes. Record which labels encode a useful GTIN and which require a
company-taught mapping before considering an external product-data provider.

## Phase 1: Prove cloud synchronization

**Status: implemented and integration-tested (August 2026).** Manual and
scan-confirmed movements use the same local append path, upload queue, stable
IDs, and Cloud endpoints.

Start with manual stock receiving. Do not connect OCR yet.

### Warehouse app

- Add a PanelVault Cloud sign-in screen.
- Support company code, email or username, and password.
- Store the authenticated session securely in Keychain.
- Show the active company and signed-in user in Settings.
- Add Sign Out and Change Company actions.

### Cloud server

- Add a mobile authentication endpoint.
- Return the user ID, company ID, role, and an expiring session token.
- Add an authenticated endpoint for uploading stock movements.
- Add an endpoint for downloading movements after a sync cursor.
- Validate that uploaded parts belong to the shared or custom company catalog.
- Reject warehouse-changing actions from unauthorized roles.

### First vertical slice

1. Sign into the Warehouse app.
2. Manually receive one known component.
3. Save the movement locally.
4. Upload it to PanelVault Cloud.
5. Confirm the website shows the new quantity and activity entry.

### Acceptance criteria

- Retrying the upload does not increase stock twice.
- A failed upload remains visible as pending on the phone.
- The website identifies the user and device that created the movement.
- Signing into the wrong company cannot expose another company's stock.

## Phase 2: Offline sync queue

**Status: core queue implemented.** Local persistence, UUID deduplication,
cursor downloads, launch/foreground retries, pending count, errors, and manual
retry are working. Network monitoring and exponential backoff remain.

- Give every movement a UUID generated on the device.
- Track local sync state: `pending`, `syncing`, `synced`, or `failed`.
- Retry pending movements when the app opens and when connectivity returns.
- Use exponential backoff instead of repeatedly hitting the server.
- Store the last successful download cursor per company.
- Merge downloaded movements by UUID.
- Never delete a local movement merely because an upload failed.
- Display a compact sync indicator and a manual Retry action.

### Conflict model

Stock movements are immutable events. Devices may append new events, but they
do not overwrite existing ones. Corrections create a new adjustment movement.
This makes offline merging predictable and preserves the audit history.

## Phase 3: Connect delivery-note scanning

**Status: delivery batches implemented and synchronized (August 2026).**
Confirming a reviewed scan now writes the batch and its movements together,
uploads both through the offline queue, and PanelVault Cloud shows the
paperwork behind every receipt. Page images are the one piece still missing —
see "Scanned pages" below.

Reuse the existing scan, OCR, matching, and review flow.

### Scan workflow

1. Scan all delivery-note pages with the iPhone camera.
2. Run on-device English and Hebrew OCR.
3. Extract likely quantities, manufacturers, models, and ratings.
4. Match each line to the shared or company component catalog.
5. Show confidence and the original recognized text.
6. Let the worker correct, replace, add, or remove every line.
7. Enter or confirm the supplier and delivery-note number.
8. Confirm the reviewed delivery.
9. Save all receipt movements locally in one batch.
10. Upload the batch to PanelVault Cloud through the sync queue.

### Delivery batch data

Each scanned delivery should store:

- Batch UUID
- Company ID
- Delivery-note number
- Supplier name
- Scan date and confirmation date
- Confirming user ID
- Original OCR text
- Optional scanned page images or PDF
- Confirmed movement UUIDs
- Sync state and last error

All of these are stored except the page images; the batch records how many
pages were scanned, and the confirming user is taken from the uploading
session rather than the request body.

### Scanned pages

The page images are the remaining gap. PanelVault Cloud currently persists one
guarded JSON document — locally or in Supabase — and a delivery note is
megabytes of JPEG. Putting them in that document would bloat every read and
every save of the whole company state, and an ephemeral Render disk would lose
them on the next deploy. Pages therefore stay on the phone until the delivery
queue is connected to the private object store already used by board files; the
batch already carries the page count, so the website can say what it does not
yet hold.

### Upload ordering

Batches and movements upload through the same queue but as separate requests,
and the server accepts a batch whose movements have not arrived yet. It reports
the shortfall instead of rejecting the batch, because an offline queue that had
to upload in a fixed order would stall the whole warehouse behind one failed
request. The website marks such a delivery until the rest lands.

### Safety requirements

- No stock movement is created before confirmation.
- Uncertain matches are visibly marked.
- A worker can save a draft and finish reviewing later.
- Uploading a batch twice cannot duplicate its movements.
- Failed image uploads do not block the confirmed stock movements.

## Phase 4: Website warehouse control center

**Status: delivery history implemented (August 2026).** The Deliveries page
lists every confirmed batch and opens each one on its read lines — accepted and
rejected — and the stock it created. The remaining items below are still open.

- Refresh stock and activity automatically after synchronized movements.
- Show on-hand, minimum level, reserved, and available quantities.
- Add low-stock and out-of-stock views.
- ~~Show delivery batches with supplier, note number, worker, and sync time.~~ Done.
- Open a delivery to inspect its confirmed lines and original scan — lines are
  done; the original scan still needs the phone-to-object-store upload path.
- Allow managers to add corrections with a required reason.
- Keep destructive actions behind confirmation dialogs.
- Add export for stock, movement history, and delivery records.

### Roles

- **Owner:** all company, team, warehouse, and project permissions.
- **Manager:** warehouse changes, board assignment, and operational reports.
- **Worker:** view stock, receive deliveries, consume parts, and update assigned
  boards.

The role boundary is now enforced by the client as well as the server. The
worker app (`worker/`) simply has no interface for creating or renaming a
project, board, customer, manufacturer, board type or company — see
`worker/README.md`. The server must still reject those actions by role; a
client that cannot ask is not the same as a server that will not answer.

## Phase 5: Link boards to warehouse stock

- Use the same component IDs in boards and warehouse stock.
- Let a board reserve selected components before construction begins.
- Distinguish reserved stock from physically consumed stock.
- Let a worker confirm component consumption from the board screen.
- Create consumption movements rather than editing totals.
- Release unused reservations when a board is changed or cancelled.
- Show shortages before work starts.
- Link every consumption movement back to its board and project.

## Phase 5b: Split the manager and worker apps

**Status: worker app assembled, not yet compiled (August 2026).**

- `ios/` stays as it is and is now the manager app.
- `worker/` is a generated copy of it: the warehouse replaces the creation tab,
  and every screen that creates or renames a record is gone.
- `warehouse/` stays as a standalone app for staff who only handle stock.
- The copy is produced by `tools/split_worker.py` and `tools/port_warehouse.py`
  rather than maintained by hand, so the manager app remains the source of truth
  for the interface and the data model.

Next:

1. Compile it in Xcode and fix what the first build surfaces.
2. Give it its own app icon.
3. Collapse the two component catalogs (`ComponentGroup` and `CatalogPart`) into
   one, now that both ship in the same binary.
4. Decide whether the worker app should read its archive from Cloud rather than
   the local snapshot — this is the same question Phase 6 answers for the
   website, and both should get the same answer.

## Phase 6: Full PanelVault desktop experience

Expand PanelVault Cloud beyond the warehouse:

- Projects and boards with the same properties as the iPhone app
- Customers, companies, manufacturers, and board types
- Board photos, project photos, schemes, and PDFs
- Board completion workflow and checklists
- Assignment, due dates, priorities, and activity history
- Search and filters across boards, projects, customers, and components
- Desktop editing with immediate synchronization to phones

The website and iPhone app should use the same server records rather than
maintaining separate versions of a project or board.

## Phase 7: Production readiness

- Deploy the server behind HTTPS.
- Replace the first Supabase JSON persistence boundary with normalized,
  transactionally updated tables before horizontal scaling.
- Keep movement UUIDs and API behavior stable during the migration.
- Add automated encrypted backups and restore testing.
- Add rate limiting, session expiry, password-reset flows, and audit logs.
- Add API and synchronization tests.
- Add monitoring for failed syncs, server errors, and low disk space.
- Define retention rules for delivery scans and other large files.

## Recommended implementation order

0. Split the manager and worker apps (Phase 5b) — done, pending first compile.
1. Manual movement upload from one iPhone to one company.
2. Movement download and UUID deduplication.
3. Offline queue and retry states.
4. Delivery batch model. — done.
5. Connect confirmed OCR scans to the queue. — done.
6. Website delivery history and automatic refresh. — history done; automatic
   refresh and scanned-page storage remain.
7. Board reservations and consumption.
8. Full project and board synchronization.
9. Production database, deployment, backups, and monitoring.

## Definition of the first major release

The first connected release is ready when a worker can scan and review a real
delivery note on an iPhone, confirm it while online or offline, and have the
resulting stock movements appear exactly once in the correct company's
PanelVault Cloud warehouse. The boss must be able to inspect who confirmed the
delivery, what changed, and which original document produced those changes.
