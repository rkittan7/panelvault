const fs = require("node:fs");
const path = require("node:path");

const STATE_ID = "primary";

function emptyState() {
  return { companies: {} };
}

function normalizeState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("PanelVault state must be a JSON object.");
  }
  if (!value.companies || typeof value.companies !== "object" || Array.isArray(value.companies)) {
    throw new Error("PanelVault state must contain a companies object.");
  }
  return value;
}

function canonicalJSON(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value);
}

class LocalJSONStorage {
  constructor(dataDir) {
    this.kind = "local";
    this.dataDir = dataDir;
    this.file = path.join(dataDir, "companies.json");
  }

  async load() {
    fs.mkdirSync(this.dataDir, { recursive: true });
    try {
      const state = normalizeState(JSON.parse(fs.readFileSync(this.file, "utf8")));
      fs.chmodSync(this.file, 0o600);
      return state;
    } catch (error) {
      if (error.code === "ENOENT") return emptyState();
      throw new Error(`Could not load PanelVault data: ${error.message}`);
    }
  }

  async save(state) {
    fs.mkdirSync(this.dataDir, { recursive: true });
    const temporary = `${this.file}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(normalizeState(state)), { mode: 0o600 });
    fs.renameSync(temporary, this.file);
  }
}

class SupabaseStorage {
  constructor(url, serviceRoleKey, fetchImplementation = globalThis.fetch) {
    if (typeof fetchImplementation !== "function") {
      throw new Error("Supabase storage requires Node.js 18 or newer.");
    }
    const parsedURL = new URL(url);
    const loopback = ["localhost", "127.0.0.1", "::1"].includes(parsedURL.hostname);
    if (parsedURL.protocol !== "https:" && !(parsedURL.protocol === "http:" && loopback)) {
      throw new Error("SUPABASE_URL must use HTTPS (HTTP is allowed only for loopback development).");
    }
    this.kind = "supabase";
    this.url = parsedURL.toString().replace(/\/$/, "");
    this.serviceRoleKey = serviceRoleKey;
    this.fetch = fetchImplementation;
    this.endpoint = `${this.url}/rest/v1/panelvault_state`;
    this.version = null;
  }

  headers(extra = {}) {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      "Content-Type": "application/json",
      ...extra,
    };
  }

  async request(url, options = {}) {
    let response;
    let raw;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    try {
      response = await this.fetch(url, {
        ...options,
        headers: this.headers(options.headers),
        signal: controller.signal,
      });
      raw = await response.text();
    } catch (error) {
      throw new Error(`Could not reach Supabase: ${error.message}`);
    } finally {
      clearTimeout(timeout);
    }
    if (!response.ok) {
      const detail = raw.slice(0, 500);
      throw new Error(`Supabase returned ${response.status}${detail ? `: ${detail}` : ""}`);
    }
    return {
      json: async () => JSON.parse(raw),
      text: async () => raw,
    };
  }

  async load() {
    const response = await this.request(`${this.endpoint}?id=eq.${STATE_ID}&select=state,version`, {
      method: "GET",
    });
    const rows = await response.json();
    if (rows.length !== 1 || !Number.isInteger(rows[0].version)) {
      throw new Error("Supabase migration is missing or returned an invalid state row.");
    }
    this.version = rows[0].version;
    return normalizeState(rows[0].state);
  }

  async save(state) {
    if (!Number.isInteger(this.version)) throw new Error("Supabase state must be loaded before saving.");
    const response = await this.request(`${this.url}/rest/v1/rpc/panelvault_save_state`, {
      method: "POST",
      body: JSON.stringify({ expected_version: this.version, new_state: normalizeState(state) }),
    });
    const nextVersion = await response.json();
    if (!Number.isInteger(nextVersion)) throw new Error("Supabase returned an invalid state version.");
    this.version = nextVersion;
  }
}

function createStorage({ dataDir, env = process.env, fetchImplementation } = {}) {
  const url = (env.SUPABASE_URL || "").trim();
  const serviceRoleKey = (env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
  if (Boolean(url) !== Boolean(serviceRoleKey)) {
    throw new Error("Set both SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, or neither.");
  }
  if (url) return new SupabaseStorage(url, serviceRoleKey, fetchImplementation);
  return new LocalJSONStorage(dataDir);
}

module.exports = { LocalJSONStorage, SupabaseStorage, canonicalJSON, createStorage, normalizeState };
