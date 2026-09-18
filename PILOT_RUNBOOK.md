# PanelVault one-company pilot runbook

This is the release checklist for the first real company. Do not store real
company data until every release gate below is complete.

## 1. Cloud and DNS

- [ ] Sync `render.yaml` in Render and confirm the service uses the always-on
  Starter instance, not Free.
- [ ] Set Render secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, a stable
  random `SESSION_SECRET` of at least 32 characters, and production
  `GEMINI_API_KEY`/`GEMINI_MODEL` values. Configure the HTTPS password-reset
  mail webhook and secret before inviting pilot users.
- [ ] Add `cloud.panel-vault.com` as the Render custom domain. At the DNS
  provider, create the exact CNAME target Render displays for `cloud`, then
  wait until Render reports a valid certificate.
- [ ] Until a separate marketing site exists, configure the apex
  `panel-vault.com` as a permanent redirect to
  `https://cloud.panel-vault.com`. Do not maintain two independently cached
  copies of the application.
- [ ] Confirm `/api/health` returns `{"ok":true,"storage":"supabase"}` over
  HTTPS and HSTS is present.

## 2. Supabase and recovery

- [ ] Apply every file in `webapp/supabase/migrations` in timestamp order.
- [ ] Confirm `panelvault_state` and all `panelvault_*` tables have RLS enabled,
  no `anon`/`authenticated` grants, and only the server-side service role can
  access them.
- [ ] Confirm the private `panelvault-attachments` bucket exists and is not
  public.
- [ ] Store the service-role key only in Render. It must never be copied into a
  browser build or iPhone app.
- [ ] Complete the backup and restore drill in `webapp/supabase/BACKUP_RESTORE.md`
  and attach the dated result to the pilot approval record.

## 3. Automated release gates

- [ ] Protect `main` so `.github/workflows/ci.yml` must pass before merge.
- [ ] Confirm Cloud CI runs the module parse, all API tests, and the fresh
  Chromium sign-in smoke test.
- [ ] Confirm macOS CI builds the Manager (`Runner`), Worker, and Warehouse
  schemes for an iOS Simulator and runs the catalog/generated-source checks.
- [ ] After deploy, open a private/cache-free browser at
  `https://cloud.panel-vault.com`; the **PanelVault Cloud** sign-in heading must
  appear and the browser console must contain no errors.

## 4. Simulator and physical iPhone verification

- [ ] Resolve every Xcode compiler error and warning on the CI toolchain.
- [ ] Owner creates the pilot company and an invitation.
- [ ] Worker joins the expected company; a wrong-company session cannot read or
  mutate pilot data.
- [ ] Count representative ABB, Schneider, Siemens, and miscellaneous boxes.
- [ ] Receive one manual delivery online.
- [ ] Scan, review, and confirm one delivery offline, reconnect, and verify the
  upload appears exactly once in Cloud after retries.
- [ ] In Cloud, verify the delivery shows worker, device, recognized/rejected
  lines, movements, and stock changes.
- [ ] Assign a board to the worker; complete it through QA while another client
  edits a different board. Neither edit may disappear.
- [ ] Force a same-board conflict and verify the server returns `409` with the
  current record; no client may silently resend an old full snapshot.

## 5. Pilot approval

Approve the pilot only after a real scanned delivery appears exactly once in
Cloud with its source document, the backup restore drill has passed, and an
assigned worker completes a board through QA without losing another client's
edits.

## External actions still requiring account access

DNS records, Render plan/domain changes, Supabase secrets/migrations, GitHub
branch protection, a full Xcode build, and physical-device tests cannot be
completed from a source checkout. Record the operator, date, and evidence for
each checkbox above.
