# PanelVault Development Plan

## Goal

Build one connected PanelVault platform for electrical-board companies:

- Workers use an iPhone in the warehouse and workshop.
- The boss and managers use PanelVault Cloud from any computer.
- Projects, boards, components, warehouse stock, and activity share the same
  company data.
- A scanned delivery note can update warehouse stock after a worker reviews
  and confirms the recognized items.

## Guiding principles

- Stock changes are append-only movements, not directly edited totals.
- Every movement has a unique ID so retries cannot count the same delivery
  twice.
- Scanning never changes stock before human review and confirmation.
- The warehouse app remains useful offline.
- Every important action records who performed it and when.
- Build and verify one complete workflow before expanding the interface.

## Phase 1: Prove cloud synchronization

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

### Safety requirements

- No stock movement is created before confirmation.
- Uncertain matches are visibly marked.
- A worker can save a draft and finish reviewing later.
- Uploading a batch twice cannot duplicate its movements.
- Failed image uploads do not block the confirmed stock movements.

## Phase 4: Website warehouse control center

- Refresh stock and activity automatically after synchronized movements.
- Show on-hand, minimum level, reserved, and available quantities.
- Add low-stock and out-of-stock views.
- Show delivery batches with supplier, note number, worker, and sync time.
- Open a delivery to inspect its confirmed lines and original scan.
- Allow managers to add corrections with a required reason.
- Keep destructive actions behind confirmation dialogs.
- Add export for stock, movement history, and delivery records.

### Roles

- **Owner:** all company, team, warehouse, and project permissions.
- **Manager:** warehouse changes, board assignment, and operational reports.
- **Worker:** view stock, receive deliveries, consume parts, and update assigned
  boards.

## Phase 5: Link boards to warehouse stock

- Use the same component IDs in boards and warehouse stock.
- Let a board reserve selected components before construction begins.
- Distinguish reserved stock from physically consumed stock.
- Let a worker confirm component consumption from the board screen.
- Create consumption movements rather than editing totals.
- Release unused reservations when a board is changed or cancelled.
- Show shortages before work starts.
- Link every consumption movement back to its board and project.

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
- Move production data from one JSON file to a transactional database.
- Keep movement UUIDs and API behavior stable during the migration.
- Add automated encrypted backups and restore testing.
- Add rate limiting, session expiry, password-reset flows, and audit logs.
- Add API and synchronization tests.
- Add monitoring for failed syncs, server errors, and low disk space.
- Define retention rules for delivery scans and other large files.

## Recommended implementation order

1. Manual movement upload from one iPhone to one company.
2. Movement download and UUID deduplication.
3. Offline queue and retry states.
4. Delivery batch model.
5. Connect confirmed OCR scans to the queue.
6. Website delivery history and automatic refresh.
7. Board reservations and consumption.
8. Full project and board synchronization.
9. Production database, deployment, backups, and monitoring.

## Definition of the first major release

The first connected release is ready when a worker can scan and review a real
delivery note on an iPhone, confirm it while online or offline, and have the
resulting stock movements appear exactly once in the correct company's
PanelVault Cloud warehouse. The boss must be able to inspect who confirmed the
delivery, what changed, and which original document produced those changes.
