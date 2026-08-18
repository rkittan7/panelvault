// PanelVault Cloud — company warehouse portal.
//
// Zero-dependency Node server: node:http + node:crypto + JSON file storage.
// Deliberately no npm packages so it runs with nothing but `node server.js`
// on any machine or host.
//
// Storage follows the same movement-log design as the iPhone warehouse app:
// stock is an append-only log of receive/consume/adjust events, quantities
// are derived — which is what will let the phone apps sync to this server
// later by pushing their logs.

const http = require("node:http");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { createStorage } = require("./storage");

const PORT = Number.parseInt(process.env.PORT || "8090", 10);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");
const PUBLIC_DIR = path.join(__dirname, "public");
const SECRET_FILE = path.join(DATA_DIR, "secret");

const CATALOG = JSON.parse(fs.readFileSync(path.join(__dirname, "catalog.json"), "utf8"));
const CATALOG_BY_ID = new Map(CATALOG.map((p) => [p.id, p]));

// ---------------------------------------------------------------- storage

fs.mkdirSync(DATA_DIR, { recursive: true });

/** Session-cookie signing secret, generated once per installation. */
const SECRET = (() => {
  if (process.env.SESSION_SECRET) {
    if (process.env.SESSION_SECRET.length < 32) {
      throw new Error("SESSION_SECRET must contain at least 32 characters.");
    }
    return process.env.SESSION_SECRET;
  }
  if (process.env.SUPABASE_URL) {
    throw new Error("SESSION_SECRET is required when Supabase storage is enabled.");
  }
  try {
    return fs.readFileSync(SECRET_FILE, "utf8");
  } catch {
    const fresh = crypto.randomBytes(32).toString("hex");
    fs.writeFileSync(SECRET_FILE, fresh, { mode: 0o600 });
    return fresh;
  }
})();

/** { companies: { [code]: company } } — cached in one server process. */
let db = { companies: {} };
const storage = createStorage({ dataDir: DATA_DIR });

function normalizeCompanies() {
  for (const company of Object.values(db.companies || {})) {
    company.movements ||= [];
    company.customParts ||= [];
    company.partSettings ||= {};
    company.boards ||= [];
    company.barcodeMappings ||= [];
  }
}

let savePromise = Promise.resolve();
function save() {
  // Serialize durable snapshots so an older write cannot win. API handlers
  // await this promise and never acknowledge a mutation before it is stored.
  const snapshot = structuredClone(db);
  savePromise = savePromise.catch(() => {}).then(() => storage.save(snapshot));
  return savePromise.catch((error) => {
    console.error(`PanelVault data save failed: ${error.message}`);
    const unavailable = new Error("Could not save PanelVault data.");
    unavailable.statusCode = 503;
    throw unavailable;
  });
}

let mutationQueue = Promise.resolve();
function serializeMutation(action) {
  const run = mutationQueue.catch(() => {}).then(async () => {
    const snapshot = structuredClone(db);
    try {
      return await action();
    } catch (error) {
      db = snapshot;
      throw error;
    }
  });
  mutationQueue = run;
  return run;
}

// ---------------------------------------------------------------- helpers

const ROLES = ["owner", "manager", "worker"];
const isAdmin = (user) => user.role === "owner" || user.role === "manager";

function id(prefix) {
  return `${prefix}-${crypto.randomUUID()}`;
}

/** Short human-shareable code, unambiguous alphabet. */
function shortCode(length) {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  return Array.from(crypto.randomBytes(length))
    .map((b) => alphabet[b % alphabet.length])
    .join("");
}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 32).toString("hex");
}

function signSession(companyCode, userID, expires) {
  const payload = `${companyCode}.${userID}.${expires}`;
  const mac = crypto.createHmac("sha256", SECRET).update(payload).digest("hex");
  return Buffer.from(`${payload}.${mac}`).toString("base64url");
}

function createSession(companyCode, userID) {
  const expires = Date.now() + SESSION_DAYS * 24 * 3600 * 1000;
  return {
    token: signSession(companyCode, userID, expires),
    expiresAt: new Date(expires).toISOString(),
  };
}

function verifySession(token) {
  try {
    const [companyCode, userID, expires, mac] = Buffer.from(token, "base64url")
      .toString()
      .split(".");
    const payload = `${companyCode}.${userID}.${expires}`;
    const expected = crypto.createHmac("sha256", SECRET).update(payload).digest("hex");
    if (!crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(expected))) return null;
    if (Number(expires) < Date.now()) return null;
    const company = db.companies[companyCode];
    const user = company?.users.find((u) => u.id === userID && u.active);
    if (!user) return null;
    return { company, user };
  } catch {
    return null;
  }
}

function partFor(company, partID) {
  return CATALOG_BY_ID.get(partID) || company.customParts.find((p) => p.id === partID) || null;
}

/** Derived stock state, exactly like the iPhone app computes it. */
function stockEntries(company) {
  const counts = {};
  const lastDates = {};
  for (const m of company.movements) {
    const delta = m.kind === "receive" ? m.quantity : m.kind === "consume" ? -m.quantity : m.quantity;
    counts[m.partID] = (counts[m.partID] || 0) + delta;
    if (!lastDates[m.partID] || lastDates[m.partID] < m.date) lastDates[m.partID] = m.date;
  }
  const active = new Set([...Object.keys(counts), ...Object.keys(company.partSettings)]);
  const entries = [];
  for (const partID of active) {
    const part = partFor(company, partID);
    if (!part) continue;
    const settings = company.partSettings[partID] || {};
    entries.push({
      part,
      onHand: counts[partID] || 0,
      minimumLevel: settings.minimumLevel ?? null,
      location: settings.location || "",
      lastMovement: lastDates[partID] || null,
    });
  }
  entries.sort((a, b) => a.part.model.localeCompare(b.part.model));
  return entries;
}

function ensureMovementSequences(company) {
  let next = Math.max(1, Math.trunc(Number(company.nextMovementSequence)) || 1);
  for (const movement of company.movements) {
    if (!Number.isInteger(movement.sequence) || movement.sequence < 1) {
      movement.sequence = next;
    }
    next = Math.max(next, movement.sequence + 1);
  }
  company.nextMovementSequence = next;
  return next - 1;
}

function appendMovement(company, movement) {
  ensureMovementSequences(company);
  movement.sequence = company.nextMovementSequence++;
  company.movements.push(movement);
  return movement;
}

// ---------------------------------------------------------------- http plumbing

function sendJSON(res, status, body, headers = {}) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...headers,
  });
  res.end(data);
}

function fail(res, status, message) {
  sendJSON(res, status, { error: message });
}

function readBody(req) {
  if (req.panelVaultBodyPromise) return req.panelVaultBodyPromise;
  req.panelVaultBodyPromise = new Promise((resolve, reject) => {
    let raw = "";
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      req.off("data", onData);
      req.off("end", onEnd);
      req.off("error", onError);
      callback(value);
    };
    const onData = (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) {
        req.resume();
        finish(reject, new Error("body too large"));
      }
    };
    const onEnd = () => {
      try {
        finish(resolve, raw ? JSON.parse(raw) : {});
      } catch {
        finish(reject, new Error("invalid json"));
      }
    };
    const onError = (error) => finish(reject, error);
    const timer = setTimeout(() => {
      req.resume();
      finish(reject, new Error("request body timed out"));
    }, 10_000);
    req.on("data", onData);
    req.on("end", onEnd);
    req.on("error", onError);
  });
  return req.panelVaultBodyPromise;
}

function sessionFrom(req) {
  const authorization = req.headers.authorization || "";
  const bearer = authorization.match(/^Bearer\s+(.+)$/i);
  if (bearer) return verifySession(bearer[1]);
  const cookie = req.headers.cookie || "";
  const match = cookie.match(/(?:^|;\s*)session=([^;]+)/);
  return match ? verifySession(match[1]) : null;
}

function sessionCookie(token, maxAgeSeconds) {
  const secure = process.env.NODE_ENV === "production" || process.env.SUPABASE_URL ? "; Secure" : "";
  return `session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSeconds}${secure}`;
}

const SESSION_DAYS = 30;
const AUTH_WINDOW_MS = 15 * 60 * 1000;
const AUTH_ATTEMPT_LIMIT = 30;
const authAttempts = new Map();

function allowAuthAttempt(req, res) {
  const forwarded = process.env.TRUST_PROXY === "true" ? req.headers["x-forwarded-for"] : "";
  const address = String(forwarded || req.socket.remoteAddress || "unknown").split(",")[0].trim();
  const now = Date.now();
  if (authAttempts.size > 10_000) {
    for (const [key, attempts] of authAttempts) {
      if (!attempts.some((time) => now - time < AUTH_WINDOW_MS)) authAttempts.delete(key);
    }
  }
  const recent = (authAttempts.get(address) || []).filter((time) => now - time < AUTH_WINDOW_MS);
  if (recent.length >= AUTH_ATTEMPT_LIMIT) {
    sendJSON(res, 429, { error: "Too many sign-in attempts. Try again later." }, { "Retry-After": "900" });
    return false;
  }
  recent.push(now);
  authAttempts.set(address, recent);
  return true;
}

function issueSession(res, companyCode, userID) {
  const expires = Date.now() + SESSION_DAYS * 24 * 3600 * 1000;
  const token = signSession(companyCode, userID, expires);
  return { "Set-Cookie": sessionCookie(token, SESSION_DAYS * 24 * 3600) };
}

function publicUser(u) {
  return { id: u.id, name: u.name, role: u.role, active: u.active, createdAt: u.createdAt };
}

function accountError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function mobileAuthBody(company, user) {
  return {
    ...createSession(company.code, user.id),
    company: { code: company.code, name: company.name },
    user: publicUser(user),
  };
}

async function createCompanyAccount({ companyName, name, password }) {
  if (!companyName?.trim() || !name?.trim() || (password || "").length < 6) {
    throw accountError("Company, your name, and a password of 6+ characters are required.");
  }
  let code;
  do {
    code = shortCode(6);
  } while (db.companies[code]);

  const salt = crypto.randomBytes(16).toString("hex");
  const owner = {
    id: id("user"),
    name: name.trim(),
    role: "owner",
    salt,
    passHash: hashPassword(password, salt),
    active: true,
    createdAt: new Date().toISOString(),
  };
  const company = {
    code,
    name: companyName.trim(),
    createdAt: new Date().toISOString(),
    users: [owner],
    invites: [],
    movements: [],
    customParts: [],
    partSettings: {},
    boards: [],
    barcodeMappings: [],
  };
  db.companies[code] = company;
  await save();
  return { company, user: owner };
}

async function joinCompanyAccount({ companyCode, inviteCode, name, password }) {
  const company = db.companies[(companyCode || "").trim().toUpperCase()];
  const invite = company?.invites.find(
    (item) => item.code === (inviteCode || "").trim().toUpperCase() && item.active
  );
  if (!invite) throw accountError("This invite link is not valid any more.");
  if (!name?.trim() || (password || "").length < 6) {
    throw accountError("Your name and a password of 6+ characters are required.");
  }
  if (company.users.some((item) => item.name.toLowerCase() === name.trim().toLowerCase())) {
    throw accountError("Someone with that name already exists — add a last initial.");
  }
  const salt = crypto.randomBytes(16).toString("hex");
  const user = {
    id: id("user"),
    name: name.trim(),
    role: invite.role,
    salt,
    passHash: hashPassword(password, salt),
    active: true,
    createdAt: new Date().toISOString(),
  };
  company.users.push(user);
  await save();
  return { company, user };
}

// ---------------------------------------------------------------- API

const routes = {
  // --- account & company -------------------------------------------------

  /** Owner registers the company and becomes its first admin. */
  "POST /api/company": async (req, res) => {
    const { company, user } = await createCompanyAccount(await readBody(req));
    sendJSON(res, 200, { companyCode: company.code }, issueSession(res, company.code, user.id));
  },

  "POST /api/mobile/company": async (req, res) => {
    const { company, user } = await createCompanyAccount(await readBody(req));
    sendJSON(res, 200, mobileAuthBody(company, user));
  },

  "POST /api/login": async (req, res) => {
    const { companyCode, name, password } = await readBody(req);
    const company = db.companies[(companyCode || "").trim().toUpperCase()];
    const user = company?.users.find(
      (u) => u.name.toLowerCase() === (name || "").trim().toLowerCase() && u.active
    );
    if (!user || hashPassword(password || "", user.salt) !== user.passHash) {
      return fail(res, 401, "Wrong company code, name or password.");
    }
    sendJSON(res, 200, { ok: true }, issueSession(res, company.code, user.id));
  },

  "POST /api/mobile/login": async (req, res) => {
    const { companyCode, name, password } = await readBody(req);
    const company = db.companies[(companyCode || "").trim().toUpperCase()];
    const user = company?.users.find(
      (u) => u.name.toLowerCase() === (name || "").trim().toLowerCase() && u.active
    );
    if (!user || hashPassword(password || "", user.salt) !== user.passHash) {
      return fail(res, 401, "Wrong company code, name or password.");
    }
    sendJSON(res, 200, mobileAuthBody(company, user));
  },

  "POST /api/logout": async (req, res) => {
    sendJSON(res, 200, { ok: true }, { "Set-Cookie": sessionCookie("", 0) });
  },

  /** Worker or manager joins through an invite link. */
  "POST /api/join": async (req, res) => {
    const { company, user } = await joinCompanyAccount(await readBody(req));
    sendJSON(res, 200, { ok: true }, issueSession(res, company.code, user.id));
  },

  "POST /api/mobile/join": async (req, res) => {
    const { company, user } = await joinCompanyAccount(await readBody(req));
    sendJSON(res, 200, mobileAuthBody(company, user));
  },

  // --- state -------------------------------------------------------------

  "GET /api/state": async (req, res, session) => {
    const { company, user } = session;
    const admin = isAdmin(user);
    sendJSON(res, 200, {
      company: { code: company.code, name: company.name },
      me: publicUser(user),
      stock: stockEntries(company),
      movements: [...company.movements]
        .sort((a, b) => b.date.localeCompare(a.date))
        .slice(0, 100)
        .map((m) => ({
          ...m,
          partName: partFor(company, m.partID)?.model || m.partID,
          userName: company.users.find((u) => u.id === m.userID)?.name || "",
        })),
      boards: company.boards
        .filter((board) => admin || board.assignedTo === user.id)
        .map((b) => ({
          ...b,
          assignedName: company.users.find((u) => u.id === b.assignedTo)?.name || "",
        })),
      customParts: company.customParts,
      members: admin ? company.users.map(publicUser) : undefined,
      invites: admin ? company.invites.filter((i) => i.active) : undefined,
      barcodeMappings: company.barcodeMappings,
    });
  },

  "GET /api/catalog": async (req, res, session) => {
    sendJSON(res, 200, { parts: [...CATALOG, ...session.company.customParts] });
  },

  // --- warehouse (admin only) --------------------------------------------

  "POST /api/movements": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can change stock.");
    const { partID, kind, quantity, reference } = await readBody(req);
    if (!partFor(company, partID)) return fail(res, 400, "Unknown part.");
    if (!["receive", "consume", "adjust"].includes(kind)) return fail(res, 400, "Bad kind.");
    const qty = Math.trunc(Number(quantity));
    if (!Number.isFinite(qty) || qty === 0 || Math.abs(qty) > 100000) {
      return fail(res, 400, "Bad quantity.");
    }
    appendMovement(company, {
      id: id("mv"),
      partID,
      kind,
      quantity: kind === "adjust" ? qty : Math.abs(qty),
      reference: (reference || "").trim(),
      date: new Date().toISOString(),
      userID: user.id,
    });
    await save();
    sendJSON(res, 200, { ok: true });
  },

  // --- mobile synchronization ------------------------------------------

  "POST /api/sync/movements": async (req, res, session) => {
    const { company, user } = session;
    const { movements } = await readBody(req);
    if (!Array.isArray(movements) || movements.length > 500) {
      return fail(res, 400, "Send an array of at most 500 movements.");
    }

    ensureMovementSequences(company);
    const existingIDs = new Set(company.movements.map((movement) => movement.id));
    const acceptedIDs = [];
    const duplicateIDs = [];
    const validated = [];

    for (const incoming of movements) {
      const movementID = String(incoming.id || "").trim();
      if (!/^[A-Za-z0-9-]{8,100}$/.test(movementID)) {
        return fail(res, 400, "A movement has an invalid id.");
      }
      if (existingIDs.has(movementID)) {
        duplicateIDs.push(movementID);
        continue;
      }
      if (!partFor(company, incoming.partID)) return fail(res, 400, "Unknown part.");
      if (!["receive", "consume", "adjust"].includes(incoming.kind)) {
        return fail(res, 400, "A movement has an invalid kind.");
      }
      if (incoming.kind === "adjust" && !isAdmin(user)) {
        return fail(res, 403, "Only the boss or a manager can upload stock adjustments.");
      }
      const quantity = Math.trunc(Number(incoming.quantity));
      if (!Number.isFinite(quantity) || quantity === 0 || Math.abs(quantity) > 100000) {
        return fail(res, 400, "A movement has an invalid quantity.");
      }
      const parsedDate = new Date(incoming.date);
      const date = Number.isFinite(parsedDate.getTime())
        ? parsedDate.toISOString()
        : new Date().toISOString();

      validated.push({
        id: movementID,
        partID: incoming.partID,
        kind: incoming.kind,
        quantity: incoming.kind === "adjust" ? quantity : Math.abs(quantity),
        reference: String(incoming.reference || "").trim().slice(0, 240),
        date,
        deviceID: String(incoming.deviceID || "").trim().slice(0, 100),
        userID: user.id,
      });
      existingIDs.add(movementID);
    }

    for (const movement of validated) {
      appendMovement(company, movement);
      acceptedIDs.push(movement.id);
    }

    if (acceptedIDs.length) await save();
    sendJSON(res, 200, {
      acceptedIDs,
      duplicateIDs,
      latestSequence: ensureMovementSequences(company),
    });
  },

  "GET /api/sync/movements": async (req, res, session) => {
    const { company } = session;
    const url = new URL(req.url, `http://${req.headers.host}`);
    const after = Math.max(0, Math.trunc(Number(url.searchParams.get("after"))) || 0);
    const latestSequence = ensureMovementSequences(company);
    const movements = company.movements
      .filter((movement) => movement.sequence > after)
      .sort((a, b) => a.sequence - b.sequence)
      .slice(0, 1000);
    sendJSON(res, 200, {
      movements,
      latestSequence,
      hasMore: movements.length === 1000 && movements.at(-1).sequence < latestSequence,
      customParts: company.customParts,
      barcodeMappings: company.barcodeMappings,
    });
  },

  "POST /api/sync/barcodes": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can teach barcodes.");
    const { barcodeMappings } = await readBody(req);
    if (!Array.isArray(barcodeMappings) || barcodeMappings.length > 500) {
      return fail(res, 400, "Send an array of at most 500 barcode mappings.");
    }

    const validated = [];
    for (const incoming of barcodeMappings) {
      const code = String(incoming.code || "").trim().toUpperCase();
      if (code.length < 3 || code.length > 120 || /[\r\n]/.test(code)) {
        return fail(res, 400, "A barcode has an invalid value.");
      }
      if (!partFor(company, incoming.partID)) return fail(res, 400, "A barcode references an unknown part.");
      const packageQuantity = Math.trunc(Number(incoming.packageQuantity));
      if (!Number.isFinite(packageQuantity) || packageQuantity < 1 || packageQuantity > 100000) {
        return fail(res, 400, "A barcode has an invalid package quantity.");
      }
      const parsedDate = new Date(incoming.updatedAt);
      validated.push({
        code,
        symbology: String(incoming.symbology || "barcode").trim().slice(0, 60),
        partID: incoming.partID,
        packageQuantity,
        boxLabel: String(incoming.boxLabel || "").trim().slice(0, 160),
        updatedAt: Number.isFinite(parsedDate.getTime())
          ? parsedDate.toISOString()
          : new Date().toISOString(),
        updatedByDeviceID: String(incoming.updatedByDeviceID || "").trim().slice(0, 100),
        updatedByUserID: user.id,
      });
    }

    let changed = false;
    for (const mapping of validated) {
      const index = company.barcodeMappings.findIndex((item) => item.code === mapping.code);
      if (index < 0) {
        company.barcodeMappings.push(mapping);
        changed = true;
      } else if (company.barcodeMappings[index].updatedAt < mapping.updatedAt) {
        company.barcodeMappings[index] = mapping;
        changed = true;
      }
    }
    if (changed) await save();
    sendJSON(res, 200, { barcodeMappings: company.barcodeMappings });
  },

  "POST /api/sync/parts": async (req, res, session) => {
    const { company } = session;
    const { customParts } = await readBody(req);
    if (!Array.isArray(customParts) || customParts.length > 500) {
      return fail(res, 400, "Send an array of at most 500 custom parts.");
    }

    const existingIDs = new Set(company.customParts.map((part) => part.id));
    const validated = [];
    for (const incoming of customParts) {
      const partID = String(incoming.id || "").trim();
      if (!/^custom-[A-Za-z0-9-]{8,100}$/.test(partID) || CATALOG_BY_ID.has(partID)) {
        return fail(res, 400, "A custom part has an invalid id.");
      }
      if (!String(incoming.model || "").trim() || !String(incoming.type || "").trim()) {
        return fail(res, 400, "Every custom part needs a model and type.");
      }
      if (existingIDs.has(partID)) continue;
      validated.push({
        id: partID,
        manufacturer: String(incoming.manufacturer || "Generic").trim().slice(0, 100),
        type: String(incoming.type).trim().slice(0, 100),
        model: String(incoming.model).trim().slice(0, 140),
        rating: String(incoming.rating || "").trim().slice(0, 100),
        poles: String(incoming.poles || "").trim().slice(0, 60),
        curve: String(incoming.curve || "").trim().slice(0, 80),
        about: String(incoming.about || "").trim().slice(0, 500),
        serialNumber: String(incoming.serialNumber || "").trim().slice(0, 160),
      });
      existingIDs.add(partID);
    }
    if (validated.length) {
      company.customParts.push(...validated);
      await save();
    }
    sendJSON(res, 200, { customParts: company.customParts });
  },

  "POST /api/parts": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can add parts.");
    const { manufacturer, type, model, rating, poles, about, serialNumber } = await readBody(req);
    if (!model?.trim() || !type?.trim()) return fail(res, 400, "Model and type are required.");
    const part = {
      id: id("custom"),
      manufacturer: (manufacturer || "Generic").trim(),
      type: type.trim(),
      model: model.trim(),
      rating: (rating || "").trim(),
      poles: (poles || "").trim(),
      curve: "",
      about: (about || "").trim(),
      serialNumber: String(serialNumber || "").trim().slice(0, 160),
    };
    company.customParts.push(part);
    await save();
    sendJSON(res, 200, { part });
  },

  "POST /api/part-settings": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can change part settings.");
    const { partID, minimumLevel, location } = await readBody(req);
    if (!partFor(company, partID)) return fail(res, 400, "Unknown part.");
    company.partSettings[partID] = {
      minimumLevel: minimumLevel == null ? null : Math.max(0, Math.trunc(Number(minimumLevel)) || 0),
      location: (location || "").trim(),
    };
    await save();
    sendJSON(res, 200, { ok: true });
  },

  // --- boards ------------------------------------------------------------

  "POST /api/boards": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can create boards.");
    const { number, name, customer, assignedTo } = await readBody(req);
    if (!number?.trim() && !name?.trim()) return fail(res, 400, "Give the board a number or a name.");
    if (assignedTo && !company.users.some((u) => u.id === assignedTo && u.active)) {
      return fail(res, 400, "Unknown assignee.");
    }
    const board = {
      id: id("board"),
      number: (number || "").trim(),
      name: (name || "").trim(),
      customer: (customer || "").trim(),
      assignedTo: assignedTo || null,
      status: "Design",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    company.boards.push(board);
    await save();
    sendJSON(res, 200, { board });
  },

  "POST /api/board-update": async (req, res, session) => {
    const { company, user } = session;
    const { boardID, status, assignedTo } = await readBody(req);
    const board = company.boards.find((b) => b.id === boardID);
    if (!board) return fail(res, 404, "Board not found.");

    // Workers may update the status of their own board; only admins reassign.
    const mayEditStatus = isAdmin(user) || board.assignedTo === user.id;
    if (status !== undefined && !mayEditStatus) return fail(res, 403, "This board is not assigned to you.");
    if (status !== undefined && !["Design", "In Progress", "Completed"].includes(status)) {
      return fail(res, 400, "Bad status.");
    }
    if (assignedTo !== undefined) {
      if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can reassign boards.");
      if (assignedTo && !company.users.some((u) => u.id === assignedTo && u.active)) {
        return fail(res, 400, "Unknown assignee.");
      }
    }
    if (status !== undefined) board.status = status;
    if (assignedTo !== undefined) {
      board.assignedTo = assignedTo || null;
    }
    board.updatedAt = new Date().toISOString();
    await save();
    sendJSON(res, 200, { ok: true });
  },

  // --- team (admin only) -------------------------------------------------

  "POST /api/invites": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can invite people.");
    const { role } = await readBody(req);
    if (!["manager", "worker"].includes(role)) return fail(res, 400, "Role must be manager or worker.");
    // Managers must not mint manager invites — only the owner can grow admins.
    if (role === "manager" && user.role !== "owner") {
      return fail(res, 403, "Only the owner can invite managers.");
    }
    const invite = {
      code: shortCode(8),
      role,
      active: true,
      createdBy: user.id,
      createdAt: new Date().toISOString(),
    };
    company.invites.push(invite);
    await save();
    sendJSON(res, 200, { invite });
  },

  "POST /api/invite-revoke": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can revoke invites.");
    const { code } = await readBody(req);
    const invite = company.invites.find((i) => i.code === code);
    if (invite) invite.active = false;
    await save();
    sendJSON(res, 200, { ok: true });
  },

  "POST /api/member-update": async (req, res, session) => {
    const { company, user } = session;
    if (user.role !== "owner") return fail(res, 403, "Only the owner can manage members.");
    const { userID, active, role } = await readBody(req);
    const member = company.users.find((u) => u.id === userID);
    if (!member) return fail(res, 404, "No such member.");
    if (member.role === "owner") return fail(res, 400, "The owner account cannot be changed here.");
    if (role !== undefined && !["manager", "worker"].includes(role)) return fail(res, 400, "Bad role.");
    if (active !== undefined) member.active = Boolean(active);
    if (role !== undefined) member.role = role;
    await save();
    sendJSON(res, 200, { ok: true });
  },
};

// Routes that must work without a session.
const OPEN_ROUTES = new Set([
  "POST /api/company",
  "POST /api/login",
  "POST /api/mobile/login",
  "POST /api/mobile/company",
  "POST /api/mobile/join",
  "POST /api/join",
]);

// ---------------------------------------------------------------- static files

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

function serveStatic(req, res, urlPath) {
  const clean = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, "");
  let filePath = path.join(PUBLIC_DIR, clean);
  if (!filePath.startsWith(PUBLIC_DIR)) return fail(res, 403, "no");
  if (urlPath === "/" || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(PUBLIC_DIR, "index.html");
  }
  const ext = path.extname(filePath);
  res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
  fs.createReadStream(filePath).pipe(res);
}

// ---------------------------------------------------------------- server

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const key = `${req.method} ${url.pathname}`;

  try {
    const handler = routes[key];
    if (handler) {
      const invoke = async () => {
        if (OPEN_ROUTES.has(key)) return await handler(req, res);
        const session = sessionFrom(req);
        if (!session) return fail(res, 401, "Please sign in.");
        return await handler(req, res, session);
      };
      if (req.method === "POST") {
        if (OPEN_ROUTES.has(key) && !allowAuthAttempt(req, res)) return;
        await readBody(req);
        return await serializeMutation(invoke);
      }
      await mutationQueue.catch(() => {});
      return await invoke();
    }
    if (url.pathname.startsWith("/api/")) return fail(res, 404, "No such endpoint.");
    return serveStatic(req, res, url.pathname);
  } catch (error) {
    return fail(res, error.statusCode || 400, error.message || "Bad request.");
  }
});

async function start() {
  db = await storage.load();
  if (storage.kind === "supabase" && Object.keys(db.companies).length === 0) {
    const localFile = path.join(DATA_DIR, "companies.json");
    try {
      const local = JSON.parse(fs.readFileSync(localFile, "utf8"));
      if (Object.keys(local.companies || {}).length > 0) {
        throw new Error(
          "Supabase is empty but local company data exists. Run import-json-to-supabase.js first."
        );
      }
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  normalizeCompanies();
  server.listen(PORT, () => {
    const address = server.address();
    const activePort = typeof address === "object" && address ? address.port : PORT;
    const backend = process.env.SUPABASE_URL ? "Supabase" : "local JSON";
    console.log(`PanelVault Cloud listening on http://localhost:${activePort} (${backend})`);
  });
}

start().catch((error) => {
  console.error(`PanelVault Cloud could not start: ${error.message}`);
  process.exitCode = 1;
});
