// Guarded one-time import of the existing PanelVault JSON state.
// Dry-run by default. Pass --apply only after reviewing the printed counts.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { SupabaseStorage, canonicalJSON, normalizeState } = require("./storage");

function digest(state) {
  return crypto.createHash("sha256").update(canonicalJSON(state)).digest("hex");
}

function counts(state) {
  const companies = Object.values(state.companies || {});
  return {
    companies: companies.length,
    users: companies.reduce((total, item) => total + (item.users?.length || 0), 0),
    movements: companies.reduce((total, item) => total + (item.movements?.length || 0), 0),
    customParts: companies.reduce((total, item) => total + (item.customParts?.length || 0), 0),
    boards: companies.reduce((total, item) => total + (item.boards?.length || 0), 0),
  };
}

async function main() {
  const apply = process.argv.includes("--apply");
  const sourceArgument = process.argv.find((argument) => !argument.startsWith("--") && argument !== process.argv[0] && argument !== process.argv[1]);
  const source = path.resolve(sourceArgument || path.join(__dirname, "data", "companies.json"));
  const url = (process.env.SUPABASE_URL || "").trim();
  const key = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
  if (!url || !key) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");

  const local = normalizeState(JSON.parse(fs.readFileSync(source, "utf8")));
  const storage = new SupabaseStorage(url, key);
  const remote = await storage.load();
  const localHash = digest(local);
  const remoteHash = digest(remote);
  console.log("Local counts:", counts(local));
  console.log("Remote counts:", counts(remote));
  console.log(`Local SHA-256:  ${localHash}`);
  console.log(`Remote SHA-256: ${remoteHash}`);

  if (localHash === remoteHash) {
    console.log("Supabase already matches the local state; nothing to import.");
    return;
  }
  if (canonicalJSON(remote) !== canonicalJSON({ companies: {} })) {
    throw new Error("Refusing to overwrite non-empty Supabase state. Reconcile it manually.");
  }
  if (!apply) {
    console.log("Dry run only. Re-run with --apply to create a backup and import this state.");
    return;
  }

  const backup = `${source}.pre-supabase-${new Date().toISOString().replace(/[:.]/g, "-")}.bak`;
  fs.copyFileSync(source, backup, fs.constants.COPYFILE_EXCL);
  fs.chmodSync(backup, 0o600);
  await storage.save(local);
  const verified = await storage.load();
  if (digest(verified) !== localHash) {
    throw new Error(`Import verification failed. The local backup remains at ${backup}`);
  }
  console.log(`Import verified. Sensitive local backup: ${backup}`);
}

main().catch((error) => {
  console.error(`Import failed: ${error.message}`);
  process.exitCode = 1;
});
