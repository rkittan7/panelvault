# PanelVault Cloud

PanelVault's browser-based company and warehouse portal. The boss and managers
can run the warehouse and assign boards from any computer; workers can see
stock and their own boards.

The companion Warehouse iPhone app already scans delivery notes, reviews the
recognized components, and records confirmed receipts in its local movement
log. Cloud synchronization is the next milestone: once connected, a confirmed
scan will push those movements here so the website's stock updates immediately.

## Run

```
node server.js
```

That's it: zero dependencies, Node 18+. Serves the web app and API on
port 8090 (override with `PORT=...`).

## Accounts and roles

- **Create company** — whoever registers becomes the **owner** and gets a
  6-character company code.
- **Invite links** — generated on the Team tab, one per role, revocable.
  Workers join with the link and choose their own password.
- **owner / manager** — change stock, add parts, create and assign boards,
  invite people. Only the owner can mint manager invites, change roles, or
  disable members.
- **worker** — sees stock and boards, and can update the status of boards
  assigned to them. Nothing else.

Passwords are scrypt-hashed; sessions are HMAC-signed http-only cookies.

## Deploying so the team can reach it

Any host that runs Node works (a small VPS, Render, Railway, a spare machine
with a tunnel). Two things matter in production:

1. **HTTPS** — put it behind a TLS proxy (Caddy is one line of config).
2. **Back up `data/`** — it holds every account and the whole movement log.
   The directory is gitignored on purpose: never commit it.

## Design notes

- Stock is the same **append-only movement log** as the iPhone Warehouse app,
  with the same part ids (catalog.json is generated from PanelVault's
  catalog). This is what will let the phone apps sync to this server by pushing
  confirmed delivery and consumption movements.
- Storage is one JSON file with debounced atomic writes — right-sized for a
  company-scale team, easy to move to a database later without changing the
  API.
- The PanelVault iOS app and the Warehouse iOS app are untouched by any of
  this.

## Next integration milestone

1. Authenticate the Warehouse app against a PanelVault Cloud company.
2. Upload confirmed delivery-note movements after the scan review screen.
3. Merge movements by their unique event IDs so offline devices cannot double
   count a delivery.
4. Refresh the website stock and activity feed as soon as the upload succeeds.
