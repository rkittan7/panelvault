# PanelVault Cloud

PanelVault's browser-based company and warehouse portal. The boss and managers
can run the warehouse and assign boards from any computer; workers can see
stock and their own boards.

The companion Warehouse iPhone app scans delivery notes, reviews recognized
components, records confirmed receipts locally, and synchronizes those stock
movements to the correct company here.

## Run

```
node server.js
```

That's it: zero dependencies, Node 18+. Serves the web app and API on
port 8090 (override with `PORT=...`). Local development stores data in
`webapp/data/companies.json`.

## Supabase persistence

The hosted server can persist the same validated PanelVault state in Supabase
without changing the browser or iPhone APIs:

1. Create a Supabase project.
2. Run `supabase/migrations/202608180001_panelvault_state.sql` in its SQL editor.
3. Add `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and a stable
   `SESSION_SECRET` to the hosting service, following `.env.example`.
4. Start the server normally. Its startup line will say `(Supabase)`.

The service-role key is a server secret. Never place it in `public/`, either
iPhone app, Git, or any environment whose values are sent to the browser. RLS
is enabled and client roles are denied table access; authorization continues
to pass through PanelVault's API.

Supabase-backed sessions always use Secure cookies. The server rate-limits
public account and sign-in endpoints. Set `TRUST_PROXY=true` only when the
host's trusted proxy overwrites `X-Forwarded-For`; otherwise rate limiting uses
the direct socket address.

This is a first, compatibility-preserving persistence boundary. Run only one
PanelVault server instance: state is still saved as one document and is not
safe for concurrent writers. Split companies, users, movements, boards, and
parts into transactionally updated relational tables before horizontal scaling.

If `data/companies.json` already contains real companies, preview and apply the
guarded import before the first Supabase-backed start:

```bash
node import-json-to-supabase.js
node import-json-to-supabase.js --apply
```

The script prints entity counts and SHA-256 checksums, refuses to overwrite a
non-empty remote state, creates a mode-0600 local backup, and reads Supabase
back to verify the import.

## Accounts and roles

- **Create company** — whoever registers becomes the **owner** and gets a
  6-character company code.
- **Invite links** — generated on the Team tab, one per role, revocable.
  Workers join with the link and choose their own password.
- **Owner / Manager / Staff Manager** — change stock, add parts, teach
  barcodes, create and assign boards, and invite people. Only the owner can
  change roles or disable members, and each role can only invite roles below
  its own.
- **QA** — signs off finished boards, on top of what Staff can do.
- **Staff** — sees stock and assigned boards, records receipts and
  consumption, can add a previously unknown delivery part, and updates the
  status of a board assigned to them.

The same capability block is sent to the browser and to both iPhone apps, so
every client permits exactly what the server accepts. See "Roles and
permissions" in the root README.

Passwords are scrypt-hashed; browser sessions are HMAC-signed http-only
cookies. The iPhone client uses an expiring HMAC bearer token stored in
Keychain.

## Deploying so the team can reach it

Any host that runs Node works (a small VPS, Render, Railway, a spare machine
with a tunnel). Two things matter in production:

1. **HTTPS** — put it behind a TLS proxy (Caddy is one line of config).
2. **Use durable storage** — configure Supabase as above, or back up `data/` if
   the local JSON backend is used. The directory is gitignored: never commit it.

## Design notes

- Stock is the same **append-only movement log** as the iPhone Warehouse app,
  with the same part ids (catalog.json is generated from PanelVault's
  catalog). This is what will let the phone apps sync to this server by pushing
  confirmed delivery and consumption movements.
- Storage is selected at startup: atomic local JSON for development, or a
  private version-checked Supabase row for hosted durability. Neither backend
  changes the API contract.
- Mobile movement uploads are validated as a complete batch before anything is
  appended. Stable movement IDs make retries idempotent.
- Movement downloads use an increasing company sequence cursor, while stock
  remains derived from the immutable movement log.
- Permissions have one definition, `capabilitiesFor()`. `/api/state` and
  `/api/mobile/login` both send it, so the browser and the phones gate their UI
  on what the server will actually allow rather than re-deriving role rules.
- `POST /api/ai/board-scheme` reads an AutoCAD board scheme and returns a board
  draft with its component schedule matched to catalog parts. It writes
  nothing, so it runs outside the mutation queue — a minute-long read must not
  hold the company's stock writes behind it — and it is the one route allowed a
  document-sized body. Matching is deliberately strict: an ambiguous line comes
  back unmatched rather than placed on a board. See `scheme.js`.
- `catalog.json` is generated from the app's own component catalog by
  `tools/gen_web_catalog.py` and carries each part's category, so the Catalog
  page can show the same eighteen groups the iPhone apps browse. It is loaded
  once at startup; regenerate it and restart to pick up catalog changes.
- Component and manufacturer pictures are served at `/catalog-images/` straight
  out of `../assets/catalog`, the same folder the three iPhone apps bundle, so
  the browser and the phones cannot end up showing different pictures of the
  same part. Nothing is copied into `public/`. The route is unauthenticated —
  these are pictures of products, identical for every company on the server —
  and it serves only image types from inside that one directory. The browser
  reads `index.json` there once per page load and draws a photo only for the
  ids it lists.

## Mobile sync API

- `POST /api/mobile/company` creates an owner and company in the same account
  database used by the website.
- `POST /api/mobile/login` returns the company, user, and expiring bearer token.
- `POST /api/mobile/join` accepts a company/invite code and creates a worker in
  that website company.
- `POST /api/sync/movements` validates and deduplicates up to 500 movements.
- `GET /api/sync/movements?after=<sequence>` downloads ordered changes.
- `POST /api/sync/parts` uploads phone-created company catalog parts first.
- `POST /api/sync/barcodes` shares barcode, component, and box-quantity
  mappings across the company.

Run the integration test with `node --test server.test.js`.
