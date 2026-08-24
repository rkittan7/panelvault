# Supabase backup and restore drill

Database backups do not include Supabase Storage objects. A valid PanelVault
backup therefore has two separately encrypted artifacts: a logical database
dump and a copy of every object in the private `panelvault-attachments` bucket.

## Backup

1. Create a temporary encrypted working directory outside the repository.
2. Run `supabase db dump --linked --file panelvault.sql` using an authorized
   operator session. Do not place the database password or service-role key in
   shell history.
3. Enumerate and download every private bucket object through the authenticated
   Storage API, preserving its exact storage key.
4. Write a SHA-256 manifest for `panelvault.sql` and every object.
5. Encrypt the dump, objects, and manifest with the company's backup key; upload
   the encrypted archive to the approved backup destination.
6. Remove the unencrypted temporary directory.

## Restore drill

1. Create an isolated Supabase project. Never rehearse against production.
2. Verify the encrypted archive and SHA-256 manifest before importing anything.
3. Apply `webapp/supabase/migrations` in timestamp order.
4. Restore the logical dump to the isolated database.
5. Recreate the private bucket through the Storage API and upload every object
   at its original storage key. Do not write directly to the `storage` schema.
6. Start PanelVault Cloud against the isolated project with a new test-only
   `SESSION_SECRET`.
7. Verify company/user counts, project and board revisions, stock totals,
   delivery-to-movement links, audit entries, and attachment checksums.
8. Download at least one board PDF and one scanned delivery document through an
   authenticated account.
9. Record date, operator, source backup timestamp, restore duration, counts,
   checksum result, and any remediation. Destroy the isolated project when the
   evidence is retained.

Run this drill before pilot data is entered and after every material schema or
backup-process change.
