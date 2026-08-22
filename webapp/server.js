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
const { createGeminiClient } = require("./gemini");

const PORT = Number.parseInt(process.env.PORT || "8090", 10);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");
const PUBLIC_DIR = path.join(__dirname, "public");
const SECRET_FILE = path.join(DATA_DIR, "secret");

/** Shared with the iPhone apps — see assets/catalog/README.md. */
const CATALOG_IMAGE_DIR = path.resolve(__dirname, "..", "assets", "catalog");
const CATALOG_IMAGE_TYPES = new Set([".png", ".jpg", ".jpeg", ".webp", ".heic", ".json"]);

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
const gemini = createGeminiClient();

function normalizeCompanies() {
  for (const company of Object.values(db.companies || {})) {
    company.movements ||= [];
    company.customParts ||= [];
    company.partSettings ||= {};
    company.projects ||= [];
    company.boards ||= [];
    company.barcodeMappings ||= [];
    company.deliveries ||= [];
    // The role set gained Staff Manager and QA, and "worker" was renamed to
    // "staff". Migrate on load so existing sessions keep their access.
    for (const user of company.users || []) {
      if (user.role === "worker") user.role = "staff";
    }
    for (const invite of company.invites || []) {
      if (invite.role === "worker") invite.role = "staff";
    }
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

// Roles, most privileged first. "owner" is the account that created the company
// and is not invitable. Legacy "worker" rows migrate to "staff" on load.
const ROLES = ["owner", "manager", "staff-manager", "qa", "staff"];
const ROLE_LABELS = {
  owner: "Owner",
  manager: "Manager",
  "staff-manager": "Staff Manager",
  qa: "QA",
  staff: "Staff",
};

// Capabilities, not role checks, so a permission can be re-granted in one place.
//
// `canSeeCosts` is deliberately narrower than `canAdminister`: a staff manager
// runs the floor and may move stock and boards, but unit costs and board totals
// are commercial data kept to the owner and managers.
const CAN_ADMINISTER = new Set(["owner", "manager", "staff-manager"]);
const CAN_SEE_COSTS = new Set(["owner", "manager"]);
const CAN_SIGN_OFF_QA = new Set(["owner", "manager", "staff-manager", "qa"]);

const isOwner = (user) => user.role === "owner";
const isAdmin = (user) => CAN_ADMINISTER.has(user.role);
const canSeeCosts = (user) => CAN_SEE_COSTS.has(user.role);
const canSignOffQA = (user) => CAN_SIGN_OFF_QA.has(user.role);

/** Which roles a given user may hand out through an invite. */
function invitableRoles(user) {
  if (isOwner(user)) return ["manager", "staff-manager", "qa", "staff"];
  if (user.role === "manager") return ["staff-manager", "qa", "staff"];
  if (user.role === "staff-manager") return ["qa", "staff"];
  return [];
}

/** Money is stored in minor units so totals never accumulate float error. */
function normalizeMinorUnits(value) {
  if (value == null || value === "") return null;
  const cents = Math.round(Number(value) * 100);
  if (!Number.isFinite(cents) || cents < 0 || cents > 100_000_000) return null;
  return cents;
}

function id(prefix) {
  return `${prefix}-${crypto.randomUUID()}`;
}

/** A phone's timestamp, or now when its clock sent us something unusable. */
function isoDate(value) {
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed.toISOString() : new Date().toISOString();
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

/** Derived stock state, exactly like the iPhone app computes it.
 *
 * Cost fields are only populated when `withCosts` is true. The caller decides
 * from the session role, so a staff or QA response never carries prices at all
 * rather than relying on the client to hide them.
 */
function stockEntries(company, withCosts = false) {
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
    const onHand = counts[partID] || 0;
    const entry = {
      part,
      onHand,
      minimumLevel: settings.minimumLevel ?? null,
      location: settings.location || "",
      lastMovement: lastDates[partID] || null,
    };
    if (withCosts) {
      const unit = settings.unitCostMinor ?? null;
      entry.unitCostMinor = unit;
      // What the shelf is worth right now. Negative stock would invent value,
      // so clamp it.
      entry.stockValueMinor = unit == null ? null : unit * Math.max(onHand, 0);
    }
    entries.push(entry);
  }
  entries.sort((a, b) => a.part.model.localeCompare(b.part.model));
  return entries;
}

/** A movement belongs to a board by explicit id, else by its reference text
 *  matching the board number — the link the warehouse app already writes. */
function movementMatchesBoard(movement, board) {
  if (movement.boardID) return movement.boardID === board.id;
  const reference = (movement.reference || "").trim().toLowerCase();
  const number = (board.number || "").trim().toLowerCase();
  return number.length > 0 && reference === number;
}

/** Cost of the parts consumed by one board, replayed from the movement log.
 *
 * Never stored: like stock, a board's cost is always derived, so correcting a
 * movement or a price corrects every total that depends on it.
 */
function boardCost(company, board) {
  let totalMinor = 0;
  let lines = 0;
  let pricedLines = 0;
  const byPart = new Map();

  for (const movement of company.movements) {
    if (movement.kind !== "consume") continue;
    if (!movementMatchesBoard(movement, board)) continue;
    const settings = company.partSettings[movement.partID] || {};
    const unit = settings.unitCostMinor ?? null;
    const existing = byPart.get(movement.partID) || { quantity: 0, unitCostMinor: unit, lineTotalMinor: null };
    existing.quantity += movement.quantity;
    existing.unitCostMinor = unit;
    existing.lineTotalMinor = unit == null ? null : unit * existing.quantity;
    byPart.set(movement.partID, existing);
  }

  const items = [];
  for (const [partID, line] of byPart) {
    const part = partFor(company, partID);
    lines += 1;
    if (line.lineTotalMinor != null) {
      totalMinor += line.lineTotalMinor;
      pricedLines += 1;
    }
    items.push({
      partID,
      partName: part ? `${part.manufacturer} ${part.model}` : partID,
      quantity: line.quantity,
      unitCostMinor: line.unitCostMinor,
      lineTotalMinor: line.lineTotalMinor,
    });
  }
  items.sort((a, b) => (b.lineTotalMinor ?? -1) - (a.lineTotalMinor ?? -1));

  return {
    totalMinor,
    items,
    // Surfaced so the UI can say "partial" instead of implying a complete total
    // when some consumed parts have no price yet.
    unpricedLines: lines - pricedLines,
  };
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

// ---------------------------------------------------------------- deliveries

/** A confirmed delivery note: the paperwork a batch of receipts came from.
 *
 * Batches are evidence, not stock. The movements they created are the stock,
 * and they upload through their own endpoint, so a batch never has to arrive
 * in the same request — or even the same order — as its movements. That is
 * why `movementIDs` is stored as written by the phone and only resolved when
 * a batch is read: an offline queue that had to upload in a fixed order would
 * stall the whole warehouse behind one failed request.
 */
const DELIVERY_SOURCES = ["scan", "manual", "stocktake"];

function ensureDeliverySequences(company) {
  let next = Math.max(1, Math.trunc(Number(company.nextDeliverySequence)) || 1);
  for (const delivery of company.deliveries) {
    if (!Number.isInteger(delivery.sequence) || delivery.sequence < 1) {
      delivery.sequence = next;
    }
    next = Math.max(next, delivery.sequence + 1);
  }
  company.nextDeliverySequence = next;
  return next - 1;
}

/** What a delivery did to stock, replayed from the movements that arrived.
 *
 * `movementsByID` is passed in when summarizing a whole list, so building the
 * index does not repeat once per delivery.
 */
function deliveryTotals(company, delivery, movementsByID) {
  const byID = movementsByID || new Map(company.movements.map((movement) => [movement.id, movement]));
  const present = delivery.movementIDs.map((id) => byID.get(id)).filter(Boolean);
  return {
    movementCount: present.length,
    // A batch whose movements have not all uploaded yet is still worth showing;
    // saying so is more honest than quietly reporting a short total.
    missingMovements: delivery.movementIDs.length - present.length,
    unitCount: present.reduce((sum, movement) => sum + Math.abs(movement.quantity), 0),
    movements: present,
  };
}

/** List shape: enough to scan the history, without every OCR line. */
function deliverySummary(company, delivery, movementsByID) {
  const totals = deliveryTotals(company, delivery, movementsByID);
  return {
    id: delivery.id,
    noteNumber: delivery.noteNumber,
    supplier: delivery.supplier,
    source: delivery.source,
    scannedAt: delivery.scannedAt,
    confirmedAt: delivery.confirmedAt,
    uploadedAt: delivery.uploadedAt,
    pageCount: delivery.pageCount,
    lineCount: delivery.lines.length,
    confirmedLineCount: delivery.lines.filter((line) => line.included).length,
    movementCount: totals.movementCount,
    missingMovements: totals.missingMovements,
    unitCount: totals.unitCount,
    userName: company.users.find((user) => user.id === delivery.userID)?.name || "",
    deviceID: delivery.deviceID,
  };
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
    projects: [],
    boards: [],
    barcodeMappings: [],
    deliveries: [],
  };
  db.companies[code] = company;
  await save();
  return { company, user: owner };
}

/** Companies holding an active invite with this code.
 *
 * Invite codes are minted globally unique, so this is normally empty or a
 * single company. The array shape exists only so a legacy duplicate minted
 * before that guarantee can be disambiguated by company code, rather than
 * silently joining somebody to the wrong company. */
function companiesWithInvite(inviteCode) {
  const code = (inviteCode || "").trim().toUpperCase();
  if (!code) return [];
  return Object.values(db.companies).filter((company) =>
    (company.invites || []).some((item) => item.code === code && item.active)
  );
}

function inviteCodeTaken(code) {
  return Object.values(db.companies).some((company) =>
    (company.invites || []).some((item) => item.code === code)
  );
}

async function joinCompanyAccount({ companyCode, inviteCode, name, password }) {
  const code = (companyCode || "").trim().toUpperCase();
  // The website asks for the invite code on its own — one code to type instead
  // of two. A company code is still honoured when sent, so the iPhone apps and
  // older invite links keep working with no change.
  let company = code ? db.companies[code] : null;
  if (!company && !code) {
    const matches = companiesWithInvite(inviteCode);
    if (matches.length > 1) {
      throw accountError("That invite code matches more than one company. Add your company code.");
    }
    company = matches[0] || null;
  }
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

  "GET /api/health": async (_req, res) => {
    sendJSON(res, 200, { ok: true, storage: storage.kind });
  },

  "POST /api/ai/generate": async (req, res) => {
    const { prompt } = await readBody(req);
    const result = await gemini.generate(prompt, {
      systemInstruction:
        "You are PanelVault's electrical-panel and warehouse assistant. Be concise, practical, and explicit when a qualified electrician must verify safety-critical information.",
    });
    sendJSON(res, 200, result);
  },

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
    const withCosts = canSeeCosts(user);
    sendJSON(res, 200, {
      company: { code: company.code, name: company.name },
      me: {
        ...publicUser(user),
        // Capabilities travel with the session so the UI mirrors what the
        // server will actually allow, instead of re-deriving role rules.
        can: {
          administer: admin,
          seeCosts: withCosts,
          signOffQA: canSignOffQA(user),
          manageMembers: isOwner(user),
        },
        invitableRoles: invitableRoles(user),
      },
      roleLabels: ROLE_LABELS,
      stock: stockEntries(company, withCosts),
      movements: [...company.movements]
        .sort((a, b) => b.date.localeCompare(a.date))
        .slice(0, 100)
        .map((m) => ({
          ...m,
          partName: partFor(company, m.partID)?.model || m.partID,
          userName: company.users.find((u) => u.id === m.userID)?.name || "",
        })),
      projects: company.projects,
      boards: company.boards.map((b) => {
        const board = {
          ...b,
          assignedName: company.users.find((u) => u.id === b.assignedTo)?.name || "",
        };
        if (withCosts) {
          const cost = boardCost(company, b);
          board.costMinor = cost.totalMinor;
          board.costItems = cost.items;
          board.unpricedLines = cost.unpricedLines;
        }
        return board;
      }),
      // Company-wide figures worth a manager's glance on the dashboard.
      costSummary: withCosts
        ? (() => {
            const entries = stockEntries(company, true);
            return {
              stockValueMinor: entries.reduce((sum, e) => sum + (e.stockValueMinor || 0), 0),
              pricedParts: entries.filter((e) => e.unitCostMinor != null).length,
              unpricedParts: entries.filter((e) => e.unitCostMinor == null).length,
              boardCostMinor: company.boards.reduce((sum, b) => sum + boardCost(company, b).totalMinor, 0),
            };
          })()
        : undefined,
      // Newest first, and summarized — the OCR lines live behind /api/delivery
      // so a company with a year of paperwork does not ship it on every load.
      deliveries: (() => {
        const movementsByID = new Map(company.movements.map((m) => [m.id, m]));
        return [...company.deliveries]
          .sort((a, b) => b.confirmedAt.localeCompare(a.confirmedAt))
          .slice(0, 100)
          .map((delivery) => deliverySummary(company, delivery, movementsByID));
      })(),
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
      validated.push({
        id: movementID,
        partID: incoming.partID,
        kind: incoming.kind,
        quantity: incoming.kind === "adjust" ? quantity : Math.abs(quantity),
        reference: String(incoming.reference || "").trim().slice(0, 240),
        date: isoDate(incoming.date),
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

  "POST /api/sync/deliveries": async (req, res, session) => {
    const { company, user } = session;
    const { deliveries } = await readBody(req);
    if (!Array.isArray(deliveries) || deliveries.length > 50) {
      return fail(res, 400, "Send an array of at most 50 deliveries.");
    }

    ensureDeliverySequences(company);
    const existingIDs = new Set(company.deliveries.map((delivery) => delivery.id));
    const acceptedIDs = [];
    const duplicateIDs = [];
    const validated = [];

    for (const incoming of deliveries) {
      const deliveryID = String(incoming.id || "").trim();
      if (!/^[A-Za-z0-9-]{8,100}$/.test(deliveryID)) {
        return fail(res, 400, "A delivery has an invalid id.");
      }
      // Confirmed paperwork is immutable, like the movements it produced: a
      // retry re-sends the same batch, and re-sending must never rewrite it.
      if (existingIDs.has(deliveryID)) {
        duplicateIDs.push(deliveryID);
        continue;
      }
      if (!Array.isArray(incoming.lines) || incoming.lines.length > 500) {
        return fail(res, 400, "A delivery has an invalid line list.");
      }
      if (!Array.isArray(incoming.movementIDs) || incoming.movementIDs.length > 500) {
        return fail(res, 400, "A delivery has an invalid movement list.");
      }

      const lines = [];
      for (const line of incoming.lines) {
        const partID = line.partID == null ? null : String(line.partID);
        // An unmatched line is the point of the review screen, so null is
        // valid — but a named part that this company does not have is not.
        if (partID !== null && !partFor(company, partID)) {
          return fail(res, 400, "A delivery line references an unknown part.");
        }
        const quantity = Math.trunc(Number(line.quantity));
        if (!Number.isFinite(quantity) || quantity < 0 || quantity > 100000) {
          return fail(res, 400, "A delivery line has an invalid quantity.");
        }
        lines.push({
          rawText: String(line.rawText || "").trim().slice(0, 400),
          quantity,
          partID,
          included: Boolean(line.included),
          movementID: line.movementID ? String(line.movementID).trim().slice(0, 100) : null,
        });
      }

      const movementIDs = [];
      for (const rawID of incoming.movementIDs) {
        const movementID = String(rawID || "").trim();
        if (!/^[A-Za-z0-9-]{8,100}$/.test(movementID)) {
          return fail(res, 400, "A delivery references an invalid movement id.");
        }
        movementIDs.push(movementID);
      }

      const pageCount = Math.trunc(Number(incoming.pageCount)) || 0;
      validated.push({
        id: deliveryID,
        noteNumber: String(incoming.noteNumber || "").trim().slice(0, 120),
        supplier: String(incoming.supplier || "").trim().slice(0, 160),
        source: DELIVERY_SOURCES.includes(incoming.source) ? incoming.source : "manual",
        scannedAt: isoDate(incoming.scannedAt),
        confirmedAt: isoDate(incoming.confirmedAt),
        // Server clock, so "when did the boss actually see this" is answerable
        // even when a phone has been offline in a van for two days.
        uploadedAt: new Date().toISOString(),
        pageCount: Math.min(Math.max(pageCount, 0), 100),
        lines,
        movementIDs,
        deviceID: String(incoming.deviceID || "").trim().slice(0, 100),
        // Whoever's session uploaded it — never a user id from the body.
        userID: user.id,
      });
      existingIDs.add(deliveryID);
    }

    for (const delivery of validated) {
      delivery.sequence = company.nextDeliverySequence++;
      company.deliveries.push(delivery);
      acceptedIDs.push(delivery.id);
    }

    if (acceptedIDs.length) await save();
    sendJSON(res, 200, {
      acceptedIDs,
      duplicateIDs,
      latestSequence: ensureDeliverySequences(company),
    });
  },

  "GET /api/sync/deliveries": async (req, res, session) => {
    const { company } = session;
    const url = new URL(req.url, `http://${req.headers.host}`);
    const after = Math.max(0, Math.trunc(Number(url.searchParams.get("after"))) || 0);
    const latestSequence = ensureDeliverySequences(company);
    const deliveries = company.deliveries
      .filter((delivery) => delivery.sequence > after)
      .sort((a, b) => a.sequence - b.sequence)
      .slice(0, 200);
    sendJSON(res, 200, {
      deliveries,
      latestSequence,
      hasMore: deliveries.length === 200 && deliveries.at(-1).sequence < latestSequence,
    });
  },

  /** One delivery in full: every read line, matched or not, and what it did. */
  "GET /api/delivery": async (req, res, session) => {
    const { company } = session;
    const url = new URL(req.url, `http://${req.headers.host}`);
    const delivery = company.deliveries.find((item) => item.id === url.searchParams.get("id"));
    if (!delivery) return fail(res, 404, "No such delivery.");
    const totals = deliveryTotals(company, delivery);
    sendJSON(res, 200, {
      delivery: {
        ...deliverySummary(company, delivery),
        lines: delivery.lines.map((line) => ({
          ...line,
          partName: line.partID
            ? (() => {
                const part = partFor(company, line.partID);
                return part ? `${part.manufacturer} ${part.model}` : line.partID;
              })()
            : "",
        })),
        movements: totals.movements.map((movement) => ({
          ...movement,
          partName: partFor(company, movement.partID)?.model || movement.partID,
        })),
      },
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
      validated.push({
        code,
        symbology: String(incoming.symbology || "barcode").trim().slice(0, 60),
        partID: incoming.partID,
        packageQuantity,
        boxLabel: String(incoming.boxLabel || "").trim().slice(0, 160),
        updatedAt: isoDate(incoming.updatedAt),
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
    const { partID, minimumLevel, location, unitCost } = await readBody(req);
    if (!partFor(company, partID)) return fail(res, 400, "Unknown part.");
    const existing = company.partSettings[partID] || {};
    // Unit cost is commercial data: a staff manager may set stock levels and
    // locations, but must not write — or silently clear — a price.
    let unitCostMinor = existing.unitCostMinor ?? null;
    if (unitCost !== undefined) {
      if (!canSeeCosts(user)) return fail(res, 403, "Only the owner or a manager can set prices.");
      unitCostMinor = normalizeMinorUnits(unitCost);
      if (unitCost != null && unitCost !== "" && unitCostMinor === null) {
        return fail(res, 400, "Enter a valid unit price.");
      }
    }
    company.partSettings[partID] = {
      minimumLevel: minimumLevel == null ? null : Math.max(0, Math.trunc(Number(minimumLevel)) || 0),
      location: (location || "").trim(),
      unitCostMinor,
    };
    await save();
    sendJSON(res, 200, { ok: true });
  },

  // --- projects & boards -------------------------------------------------

  "POST /api/projects": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can create projects.");
    const { name, customer, site, dueDate, colorHex } = await readBody(req);
    if (!name?.trim() || !customer?.trim()) {
      return fail(res, 400, "Project name and customer are required.");
    }
    if (company.projects.some((project) => project.name.toLowerCase() === name.trim().toLowerCase())) {
      return fail(res, 409, "A project with that name already exists.");
    }
    const parsedDueDate = dueDate ? new Date(dueDate) : null;
    if (parsedDueDate && !Number.isFinite(parsedDueDate.getTime())) {
      return fail(res, 400, "Enter a valid expected finish date.");
    }
    const project = {
      id: id("project"),
      name: name.trim(),
      customer: customer.trim(),
      site: (site || "").trim(),
      detail: site?.trim() ? `0 boards • ${site.trim()}` : "0 boards",
      status: "Design",
      colorHex: /^#[0-9a-f]{6}$/i.test(colorHex || "") ? colorHex.toUpperCase() : "#5E78FF",
      dueDate: parsedDueDate?.toISOString() || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    company.projects.push(project);
    await save();
    sendJSON(res, 200, { project });
  },

  "POST /api/boards": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can create boards.");
    const body = await readBody(req);
    const { number, name, assignedTo } = body;
    let customer = (body.customer || "").trim();
    const projectName = (body.project || "No Project").trim() || "No Project";
    const project = projectName === "No Project"
      ? null
      : company.projects.find((item) => item.name === projectName);
    if (projectName !== "No Project" && !project) return fail(res, 400, "Unknown project.");
    if (project) customer = project.customer;
    if (!number?.trim() || !name?.trim() || !customer) {
      return fail(res, 400, "Board number, name and customer are required.");
    }
    if (assignedTo && !company.users.some((u) => u.id === assignedTo && u.active)) {
      return fail(res, 400, "Unknown assignee.");
    }
    const cabinetCount = Math.max(1, Math.min(12, Math.trunc(Number(body.cabinetCount)) || 1));
    const parseOptionalDate = (value, label) => {
      if (!value) return null;
      const parsed = new Date(value);
      if (!Number.isFinite(parsed.getTime())) {
        const error = new Error(`Enter a valid ${label}.`);
        error.statusCode = 400;
        throw error;
      }
      return parsed.toISOString();
    };
    const ampere = (body.mainBreakerAmpere || body.ampere || "630A").trim().toUpperCase();
    const board = {
      id: id("board"),
      number: number.trim(),
      group: (body.group || "").trim(),
      name: name.trim(),
      customer,
      company: (body.company || "").trim(),
      project: projectName,
      type: (body.type || "MDB").trim(),
      subtype: (body.subtype || "Standard").trim(),
      manufacturer: (body.manufacturer || "Generic").trim(),
      ampere: ampere.endsWith("A") ? ampere : `${ampere}A`,
      cabinetCount: String(cabinetCount),
      buildFormat: ["Panels", "Plate"].includes(body.buildFormat) ? body.buildFormat : "Panels",
      dateOut: parseOptionalDate(body.dateOut, "out date") || new Date().toISOString(),
      dueDate: parseOptionalDate(body.dueDate, "due date"),
      finishDate: parseOptionalDate(body.finishDate, "finish date"),
      mainBreakerType: (body.mainBreakerType || "Main Breaker").trim(),
      mainBreakerModel: (body.mainBreakerModel || "").trim(),
      mainBreakerAmpere: ampere.endsWith("A") ? ampere : `${ampere}A`,
      assignedTo: assignedTo || null,
      status: "In Progress",
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
    // Nobody may invite a role at or above their own: the allowed set is
    // derived from the inviter, so a staff manager cannot mint a manager.
    const allowed = invitableRoles(user);
    if (!allowed.includes(role)) {
      return fail(res, 403, `You can invite: ${allowed.join(", ") || "nobody"}.`);
    }
    // Globally unique, so a joiner can be resolved from the invite code alone.
    let inviteCode;
    do {
      inviteCode = shortCode(8);
    } while (inviteCodeTaken(inviteCode));
    const invite = {
      code: inviteCode,
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
    if (active !== undefined) member.active = Boolean(active);
    if (role !== undefined) {
      if (!ROLES.includes(role) || role === "owner") return fail(res, 400, "Bad role.");
      member.role = role;
    }
    await save();
    sendJSON(res, 200, { ok: true });
  },
};

// Routes that must work without a session.
const OPEN_ROUTES = new Set([
  "GET /api/health",
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
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".heic": "image/heic",
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

/** Component and manufacturer photos, served straight out of assets/catalog.
 *
 * The same folder is what the three iPhone apps bundle, so the browser and the
 * phones cannot drift onto different pictures of the same part. Nothing here
 * is generated into public/ — one copy of each photo exists in the repo, and
 * this is it.
 *
 * Unauthenticated on purpose: these are catalog pictures of products, the same
 * for every company on the server, and gating them behind a session would mean
 * no logo could render on the sign-in screen.
 */
function serveCatalogImage(req, res, urlPath) {
  const relative = decodeURIComponent(urlPath.slice("/catalog-images/".length));
  const filePath = path.resolve(CATALOG_IMAGE_DIR, relative);
  // path.resolve collapses `..`, so this rejects anything that climbed out.
  if (filePath !== CATALOG_IMAGE_DIR && !filePath.startsWith(CATALOG_IMAGE_DIR + path.sep)) {
    return fail(res, 403, "no");
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    return fail(res, 404, "No such image.");
  }
  const ext = path.extname(filePath).toLowerCase();
  if (!CATALOG_IMAGE_TYPES.has(ext)) return fail(res, 403, "no");
  res.writeHead(200, {
    "Content-Type": MIME[ext] || "application/octet-stream",
    // Photos change only when someone drops a new file in and redeploys, and
    // the manifest is re-fetched on every page load, so a long cache is safe.
    "Cache-Control": ext === ".json" ? "no-cache" : "public, max-age=86400",
  });
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
    if (url.pathname.startsWith("/catalog-images/")) {
      if (req.method !== "GET") return fail(res, 405, "No such endpoint.");
      return serveCatalogImage(req, res, url.pathname);
    }
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
