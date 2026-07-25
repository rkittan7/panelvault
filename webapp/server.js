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

const PORT = process.env.PORT || 8090;
const DATA_DIR = path.join(__dirname, "data");
const PUBLIC_DIR = path.join(__dirname, "public");
const DB_FILE = path.join(DATA_DIR, "companies.json");
const SECRET_FILE = path.join(DATA_DIR, "secret");

const CATALOG = JSON.parse(fs.readFileSync(path.join(__dirname, "catalog.json"), "utf8"));
const CATALOG_BY_ID = new Map(CATALOG.map((p) => [p.id, p]));

// ---------------------------------------------------------------- storage

fs.mkdirSync(DATA_DIR, { recursive: true });

/** Session-cookie signing secret, generated once per installation. */
const SECRET = (() => {
  try {
    return fs.readFileSync(SECRET_FILE, "utf8");
  } catch {
    const fresh = crypto.randomBytes(32).toString("hex");
    fs.writeFileSync(SECRET_FILE, fresh, { mode: 0o600 });
    return fresh;
  }
})();

/** { companies: { [code]: company } } — small enough to hold in memory. */
let db = { companies: {} };
try {
  db = JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
} catch {}

let saveTimer = null;
function save() {
  // Debounced atomic write; a burst of movements becomes one disk write.
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const tmp = DB_FILE + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(db));
    fs.renameSync(tmp, DB_FILE);
  }, 150);
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
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) reject(new Error("body too large"));
    });
    req.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error("invalid json"));
      }
    });
  });
}

function sessionFrom(req) {
  const cookie = req.headers.cookie || "";
  const match = cookie.match(/(?:^|;\s*)session=([^;]+)/);
  return match ? verifySession(match[1]) : null;
}

function sessionCookie(token, maxAgeSeconds) {
  return `session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSeconds}`;
}

const SESSION_DAYS = 30;

function issueSession(res, companyCode, userID) {
  const expires = Date.now() + SESSION_DAYS * 24 * 3600 * 1000;
  const token = signSession(companyCode, userID, expires);
  return { "Set-Cookie": sessionCookie(token, SESSION_DAYS * 24 * 3600) };
}

function publicUser(u) {
  return { id: u.id, name: u.name, role: u.role, active: u.active, createdAt: u.createdAt };
}

// ---------------------------------------------------------------- API

const routes = {
  // --- account & company -------------------------------------------------

  /** Owner registers the company and becomes its first admin. */
  "POST /api/company": async (req, res) => {
    const { companyName, name, password } = await readBody(req);
    if (!companyName?.trim() || !name?.trim() || (password || "").length < 6) {
      return fail(res, 400, "Company, your name, and a password of 6+ characters are required.");
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
    db.companies[code] = {
      code,
      name: companyName.trim(),
      createdAt: new Date().toISOString(),
      users: [owner],
      invites: [],
      movements: [],
      customParts: [],
      partSettings: {},
      boards: [],
    };
    save();
    sendJSON(res, 200, { companyCode: code }, issueSession(res, code, owner.id));
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

  "POST /api/logout": async (req, res) => {
    sendJSON(res, 200, { ok: true }, { "Set-Cookie": sessionCookie("", 0) });
  },

  /** Worker or manager joins through an invite link. */
  "POST /api/join": async (req, res) => {
    const { companyCode, inviteCode, name, password } = await readBody(req);
    const company = db.companies[(companyCode || "").trim().toUpperCase()];
    const invite = company?.invites.find(
      (i) => i.code === (inviteCode || "").trim().toUpperCase() && i.active
    );
    if (!invite) return fail(res, 400, "This invite link is not valid any more.");
    if (!name?.trim() || (password || "").length < 6) {
      return fail(res, 400, "Your name and a password of 6+ characters are required.");
    }
    if (company.users.some((u) => u.name.toLowerCase() === name.trim().toLowerCase())) {
      return fail(res, 400, "Someone with that name already exists — add a last initial.");
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
    save();
    sendJSON(res, 200, { ok: true }, issueSession(res, company.code, user.id));
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
      boards: company.boards.map((b) => ({
        ...b,
        assignedName: company.users.find((u) => u.id === b.assignedTo)?.name || "",
      })),
      customParts: company.customParts,
      members: admin ? company.users.map(publicUser) : undefined,
      invites: admin ? company.invites.filter((i) => i.active) : undefined,
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
    company.movements.push({
      id: id("mv"),
      partID,
      kind,
      quantity: kind === "adjust" ? qty : Math.abs(qty),
      reference: (reference || "").trim(),
      date: new Date().toISOString(),
      userID: user.id,
    });
    save();
    sendJSON(res, 200, { ok: true });
  },

  "POST /api/parts": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can add parts.");
    const { manufacturer, type, model, rating, poles, about } = await readBody(req);
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
    };
    company.customParts.push(part);
    save();
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
    save();
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
    save();
    sendJSON(res, 200, { board });
  },

  "POST /api/board-update": async (req, res, session) => {
    const { company, user } = session;
    const { boardID, status, assignedTo } = await readBody(req);
    const board = company.boards.find((b) => b.id === boardID);
    if (!board) return fail(res, 404, "Board not found.");

    // Workers may update the status of their own board; only admins reassign.
    const mayEditStatus = isAdmin(user) || board.assignedTo === user.id;
    if (status !== undefined) {
      if (!mayEditStatus) return fail(res, 403, "This board is not assigned to you.");
      if (!["Design", "In Progress", "Completed"].includes(status)) return fail(res, 400, "Bad status.");
      board.status = status;
    }
    if (assignedTo !== undefined) {
      if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can reassign boards.");
      if (assignedTo && !company.users.some((u) => u.id === assignedTo && u.active)) {
        return fail(res, 400, "Unknown assignee.");
      }
      board.assignedTo = assignedTo || null;
    }
    board.updatedAt = new Date().toISOString();
    save();
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
    save();
    sendJSON(res, 200, { invite });
  },

  "POST /api/invite-revoke": async (req, res, session) => {
    const { company, user } = session;
    if (!isAdmin(user)) return fail(res, 403, "Only the boss or a manager can revoke invites.");
    const { code } = await readBody(req);
    const invite = company.invites.find((i) => i.code === code);
    if (invite) invite.active = false;
    save();
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
      if (!["manager", "worker"].includes(role)) return fail(res, 400, "Bad role.");
      member.role = role;
    }
    save();
    sendJSON(res, 200, { ok: true });
  },
};

// Routes that must work without a session.
const OPEN_ROUTES = new Set(["POST /api/company", "POST /api/login", "POST /api/join"]);

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
      if (OPEN_ROUTES.has(key)) return await handler(req, res);
      const session = sessionFrom(req);
      if (!session) return fail(res, 401, "Please sign in.");
      return await handler(req, res, session);
    }
    if (url.pathname.startsWith("/api/")) return fail(res, 404, "No such endpoint.");
    return serveStatic(req, res, url.pathname);
  } catch (error) {
    return fail(res, 400, error.message || "Bad request.");
  }
});

server.listen(PORT, () => {
  console.log(`PanelVault Cloud listening on http://localhost:${PORT}`);
});
