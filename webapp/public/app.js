import { renderMovementChart } from "/chart.js";

// PanelVault Cloud frontend — vanilla JS, no build step.

let state = null; // last /api/state payload
let catalog = null; // lazy-loaded parts list
let currentView = "dashboard";
let selectedBoardID = null;
let selectedBoardCabinet = 0;
let boardCreationType = null;
let boardChecklistSyncing = false;
let boardChecklistRevision = 0;
let boardChecklistQueue = Promise.resolve();
let boardChecklistAnimation = null;

// Kept in the same order as AmpereRating and PoleRating in the iPhone app.
const AMPERE_RATINGS = [
  "0.5A", "1A", "2A", "3A", "4A", "6A", "10A", "13A", "16A", "20A", "25A", "32A",
  "40A", "50A", "63A", "80A", "100A", "125A", "160A", "200A", "225A", "250A",
  "315A", "400A", "500A", "630A", "800A", "1000A", "1250A", "1600A", "2000A",
  "2500A", "3200A", "4000A", "5000A", "6300A",
];
const POLE_RATINGS = ["1P", "1P+N", "2P", "3P", "3P+N", "4P", "3PH", "1PH", "DIN"];

const $ = (sel) => document.querySelector(sel);

const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
};

// ---------------------------------------------------------------- icons

const ICON_PATHS = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  box: '<path d="M21 8l-9-5-9 5v8l9 5 9-5z"/><path d="M3 8l9 5 9-5"/><path d="M12 13v8"/>',
  board: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M4 9h16"/><path d="M9 3v6"/><path d="M9 14h6"/><path d="M9 17h4"/>',
  folder: '<path d="M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  team: '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 20c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/><circle cx="17" cy="9" r="2.6"/><path d="M16 15.2c2.6.3 4.5 2 4.5 4.8"/>',
  alert: '<path d="M12 3l10 17H2z"/><path d="M12 10v4"/><path d="M12 17.5v.5"/>',
  pulse: '<path d="M3 12h4l2.5-6 4 12L16 12h5"/>',
  hash: '<path d="M5 9h14"/><path d="M5 15h14"/><path d="M10 4L8 20"/><path d="M16 4l-2 16"/>',
  plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  arrowIn: '<path d="M12 4v12"/><path d="M7 11l5 5 5-5"/><path d="M5 20h14"/>',
  arrowOut: '<path d="M12 20V8"/><path d="M7 13l5-5 5 5"/><path d="M5 4h14"/>',
  sliders: '<path d="M4 7h10"/><circle cx="17" cy="7" r="2.5"/><path d="M20 16H10"/><circle cx="7" cy="16" r="2.5"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a1 1 0 0 1 1-1h9"/>',
  x: '<path d="M6 6l12 12"/><path d="M18 6L6 18"/>',
  chevron: '<path d="M9 6l6 6-6 6"/>',
  link: '<path d="M10 14a4 4 0 0 0 6 .5l3-3a4 4 0 0 0-5.5-5.5l-1.5 1.5"/><path d="M14 10a4 4 0 0 0-6-.5l-3 3a4 4 0 0 0 5.5 5.5l1.5-1.5"/>',
  note: '<path d="M6 2h8l4 4v16H6z"/><path d="M14 2v5h4"/><path d="M9 12h6"/><path d="M9 16h6"/>',
  scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M3 12h18"/>',

  // Catalog categories. These mirror the SF Symbols the iPhone apps use for
  // the same fifteen groups, so a category is recognisable on either screen.
  catalog: '<path d="M4 5a2 2 0 0 1 2-2h11v18H6a2 2 0 0 1-2-2z"/><path d="M17 3h1a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-1"/><path d="M8 7h5"/><path d="M8 11h5"/>',
  bolt: '<path d="M13 2 4.5 13.5H11l-1 8.5 8.5-11.5H12z"/>',
  shield: '<path d="M12 3l7.5 3v5.5c0 4.3-3.1 8.2-7.5 9.5-4.4-1.3-7.5-5.2-7.5-9.5V6z"/>',
  boltShield: '<path d="M12 3l7.5 3v5.5c0 4.3-3.1 8.2-7.5 9.5-4.4-1.3-7.5-5.2-7.5-9.5V6z"/><path d="M12.5 8 10 12.2h3L10.5 16"/>',
  toggle: '<rect x="2.5" y="7" width="19" height="10" rx="5"/><circle cx="16.5" cy="12" r="2.6"/>',
  gauge: '<path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4-5"/><circle cx="12" cy="17" r="1.4"/>',
  motor: '<rect x="3" y="7" width="12" height="10" rx="2"/><path d="M15 10h3l3-3v10l-3-3h-3"/><path d="M6.5 12h5"/>',
  plug: '<path d="M9 3v5"/><path d="M15 3v5"/><path d="M5.5 8h13v3a6.5 6.5 0 0 1-13 0z"/><path d="M12 17.5V21"/>',
  cpu: '<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M10 3v4"/><path d="M14 3v4"/><path d="M10 17v4"/><path d="M14 17v4"/><path d="M3 10h4"/><path d="M3 14h4"/><path d="M17 10h4"/><path d="M17 14h4"/>',
  terminal: '<circle cx="6.5" cy="8" r="1.6"/><circle cx="12" cy="8" r="1.6"/><circle cx="17.5" cy="8" r="1.6"/><circle cx="6.5" cy="16" r="1.6"/><circle cx="12" cy="16" r="1.6"/><circle cx="17.5" cy="16" r="1.6"/>',
  layers: '<path d="M3 8.5h18"/><path d="M3 12h18"/><path d="M3 15.5h18"/>',
  tag: '<path d="M3 11.5V4a1 1 0 0 1 1-1h7.5L21 12.5 12.5 21z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
  cabinet: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M12 3v18"/><path d="M9 11.5h.01"/><path d="M15 11.5h.01"/>',
  button: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.2"/>',
};

/** Category id -> icon, matching warehouse/Sources/Catalog.swift's group ids. */
const CATEGORY_ICONS = {
  mcbs: "bolt",
  rcbo: "shield",
  mccbs: "boltShield",
  "surge-arc": "alert",
  switching: "toggle",
  drives: "gauge",
  "motor-protection": "motor",
  "control-power": "plug",
  "control-automation": "cpu",
  metering: "gauge",
  "power-quality": "pulse",
  terminals: "terminal",
  busbars: "layers",
  enclosure: "cabinet",
  "door-devices": "button",
  custom: "sliders",
};

function icon(name, size = 18) {
  const span = el("span");
  span.innerHTML = `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICON_PATHS[name] || ""}</svg>`;
  return span.firstChild;
}

function chipIcon(name, color) {
  const chip = el("div", "chip-icon");
  chip.style.background = `color-mix(in srgb, ${color} 14%, transparent)`;
  chip.style.color = color;
  chip.append(icon(name));
  return chip;
}

// ---------------------------------------------------------------- catalog photos

/* Component and manufacturer pictures live in assets/catalog and are listed in
   its generated index.json — the same folder and the same manifest the three
   iPhone apps bundle. The manifest is loaded once at boot so no render site has
   to probe the server for a photo that may not exist: a part is only drawn with
   an <img> when the manifest says a file is really there. */
let catalogImages = { components: {}, manufacturers: {} };

async function loadCatalogImages() {
  try {
    const res = await fetch("/catalog-images/index.json");
    if (!res.ok) return;
    const index = await res.json();
    catalogImages = {
      components: index.components || {},
      manufacturers: index.manufacturers || {},
    };
  } catch {
    /* No photos dropped in yet, or the folder is missing: every render site
       falls back to its icon, which is what the site looked like before. */
  }
}

/** Matches the id slugging in tools/sync_catalog_images.py. */
function brandSlug(name) {
  return (name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/* ---- brand accents (ported from the iPhone apps, value for value) ----

   The apps tint a catalog row, its pills and its photo glow by manufacturer.
   Two separate tables do that work there and both are reproduced here, because
   they genuinely differ:

     ACCENTS     ManufacturerItem.defaults in worker/Sources/Models.swift — the
                 saturated brand accent behind a row, its pills and the glow on
                 a component photo.
     LOGO_GLOWS  EquipmentBrandBadge.brandGlowColor in Badges.swift — a muted
                 set used only for the halo behind a brand logo, so a wall of
                 logos does not turn into a wall of neon.

   Both fall back the way the app does: an unlisted brand takes the theme
   accent for its row, and a soft blue for its logo halo. */
const BRAND_ACCENTS = {
  rittal: "#5E78FF", abb: "#FF3B30", yakir: "#35E177", tamhash: "#FF9F0A",
  hager: "#64D2FF", delta: "#0A84FF", schneider: "#35E177", siemens: "#18D4E8",
  eaton: "#5E78FF", legrand: "#D85CFF", "mean-well": "#FFD60A",
  phoenix: "#FF9F0A", danfoss: "#E2231A", socomec: "#00A0DF",
  generic: "#AEB4BC",
};

const BRAND_LOGO_GLOWS = {
  abb: "#FF0000", schneider: "#5F9F79", siemens: "#4F9AA8",
};
const BRAND_LOGO_GLOW_FALLBACK = "#7FA6C9";

/** A brand's row/photo accent, or the theme accent when the app has none. */
function brandAccent(name) {
  return BRAND_ACCENTS[brandSlug(name)] || "var(--primary)";
}

/** The muted halo behind a brand logo. */
function brandLogoGlow(name) {
  return BRAND_LOGO_GLOWS[brandSlug(name)] || BRAND_LOGO_GLOW_FALLBACK;
}

/** Hands a subtree its brand accent; every tint below reads `--brand`. */
function tintByBrand(node, name) {
  node.style.setProperty("--brand", brandAccent(name));
  return node;
}

function imageURL(file) {
  return file ? `/catalog-images/${file.split("/").map(encodeURIComponent).join("/")}` : null;
}

function partPhotoURL(part) {
  return imageURL(catalogImages.components[part && (part.sourceID || part.id)]);
}

function brandLogoURL(name) {
  return imageURL(catalogImages.manufacturers[brandSlug(name)]);
}

/** The 30px chip at the head of a part row: its photo, or the type icon. */
function partChip(part) {
  const url = partPhotoURL(part);
  if (!url) return chipIcon("box", colorForType(part && part.type));
  // Matching TransparentImageBubble: the photo is a cut-out, so the halo is
  // cast from its silhouette in the brand's accent rather than from a plate.
  const chip = tintByBrand(el("div", "chip-icon chip-photo"), part && part.manufacturer);
  const img = el("img");
  img.src = url;
  img.alt = "";
  img.loading = "lazy";
  // A file listed in the manifest but missing on disk must not leave a broken
  // image glyph in the middle of a stock row.
  img.addEventListener("error", () => chip.replaceWith(chipIcon("box", colorForType(part && part.type))));
  chip.append(img);
  return chip;
}

/** The brand's logo, or null when it has none yet.
 *
 * Deliberately just the mark: every row and modal that shows one already spells
 * the manufacturer out in its title, and the sub-line it sits on is narrow
 * enough to ellipsis away the part's type and location if the name is repeated
 * there as well. */
function brandMark(name) {
  const url = brandLogoURL(name);
  if (!url) return null;
  // Not `brand-mark`: that class is the PanelVault logo bubble on the auth
  // screen, and it is a grid container.
  const img = el("img", "brand-logo");
  img.style.setProperty("--glow", brandLogoGlow(name));
  img.src = url;
  img.alt = name || "";
  img.title = name || "";
  img.loading = "lazy";
  img.addEventListener("error", () => img.remove());
  return img;
}

/** A part's sub-line: its brand mark, then the details it was given. */
function partSubLine(part, bits) {
  const sub = el("div", "row-sub");
  const mark = brandMark(part && part.manufacturer);
  if (mark) sub.append(mark);
  if (bits) sub.append(el("span", null, bits));
  return sub;
}

/* ComponentIcon.symbol(for:) in worker/Sources/Badges.swift, mapped onto the
   icons this stylesheet actually ships. Order matters exactly as it does
   there — "mccb" has to be tested before "mcb", and first match wins. */
const TYPE_ICONS = [
  ["vfd drive", "gauge"],
  ["soft starter", "pulse"],
  ["motor starter", "motor"],
  ["mpcb motor protection", "motor"],
  ["overload", "alert"],
  ["ups", "bolt"],
  ["psu power supply", "plug"],
  ["current transformer", "pulse"],
  ["transformer", "layers"],
  ["rcbo rccb rcd", "pulse"],
  ["afdd", "alert"],
  ["mcb mccb acb breaker", "boltShield"],
  ["spd surge", "alert"],
  ["fuse", "bolt"],
  ["contactor relay", "toggle"],
  ["ats changeover", "link"],
  ["isolator switch", "button"],
  ["interlock", "shield"],
  ["emergency stop", "alert"],
  ["analyzer meter metering", "gauge"],
  ["terminal", "terminal"],
  ["busbar bar bonding", "layers"],
  ["enclosure cabinet climate", "cabinet"],
  ["plc hmi controller io", "cpu"],
];

function iconForType(type) {
  const lowered = (type || "").toLowerCase();
  for (const [keys, name] of TYPE_ICONS) {
    if (keys.split(" ").some((k) => lowered.includes(k))) return name;
  }
  return "box";
}

const TYPE_COLORS = [
  ["mcb mccb acb breaker fuse", "var(--warning)"],
  ["rcbo rcd", "var(--secondary)"],
  ["vfd drive starter motor", "var(--positive)"],
  ["psu ups power transformer", "var(--primary)"],
];

function colorForType(type) {
  const lowered = (type || "").toLowerCase();
  for (const [keys, color] of TYPE_COLORS) {
    if (keys.split(" ").some((k) => lowered.includes(k))) return color;
  }
  return "var(--secondary)";
}

// ---------------------------------------------------------------- api

async function api(path, body) {
  const res = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "Something went wrong.");
  return data;
}

// Capabilities come from the server with the session, so the UI can never show
// an action the API would refuse — and never hides one it would allow.
const isAdmin = () => Boolean(state?.me?.can?.administer);
const canSeeCosts = () => Boolean(state?.me?.can?.seeCosts);
const canManageMembers = () => Boolean(state?.me?.can?.manageMembers);
const roleLabel = (role) => state?.roleLabels?.[role] || role;

/** Minor units to a readable amount. Money is integer cents end to end. */
function money(minor) {
  if (minor == null) return "\u2014";
  return (minor / 100).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

// ---------------------------------------------------------------- auth

function showAuth() {
  $("#auth").classList.remove("hidden");
  $("#main").classList.add("hidden");

  // Invite links look like /#join/COMPANY/INVITE. Land straight on the filled-in
  // join form: someone following an invite has already made both choices.
  const parts = location.hash.split("/");
  if (parts[0] === "#join" && parts.length >= 3) {
    switchAuthTab("signup");
    setSignupMode("join");
    const form = $("#form-signup");
    form.companyCode.value = parts[1];
    form.inviteCode.value = parts[2];
  }
}

function switchAuthTab(tab) {
  document.querySelectorAll(".seg button").forEach((b) => {
    const on = b.dataset.tab === tab;
    b.classList.toggle("active", on);
    b.setAttribute("aria-selected", String(on));
  });
  ["signin", "signup"].forEach((name) =>
    $(`#form-${name}`).classList.toggle("hidden", name !== tab));
  $("#auth-error").classList.add("hidden");
}

// Which half of sign-up is showing: joining an existing company, or opening a
// new one. Held here because the submit handler picks its endpoint from it.
let signupMode = "join";

/** Show one sign-up branch and disable the other's fields.
 *
 * Disabling matters twice over: a disabled input is left out of FormData, so a
 * blank company name can't ride along on a join, and `required` stops applying,
 * which would otherwise block submit on a field nobody can see. */
function setSignupMode(mode) {
  signupMode = mode;
  document.querySelectorAll("#signup-mode .choice").forEach((b) => {
    const on = b.dataset.mode === mode;
    b.classList.toggle("active", on);
    b.setAttribute("aria-checked", String(on));
  });
  [["#signup-join", "join"], ["#signup-create", "create"]].forEach(([id, owner]) => {
    const group = $(id);
    const on = owner === mode;
    group.classList.toggle("hidden", !on);
    group.querySelectorAll("input").forEach((input) => { input.disabled = !on; });
  });
  $("#signup-hint").textContent = mode === "join"
    ? "Your boss creates the invite code in Team. Ask for one if you don't have it yet."
    : "You become the owner, and get a company code plus invite links for your team.";
  $("#auth-error").classList.add("hidden");
}

document.querySelectorAll(".seg button").forEach((b) =>
  b.addEventListener("click", () => switchAuthTab(b.dataset.tab)));
document.querySelectorAll("#signup-mode .choice").forEach((b) =>
  b.addEventListener("click", () => setSignupMode(b.dataset.mode)));

function submitAuth(id, endpointFor) {
  $(id).addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target));
    try {
      await api(endpointFor(), data);
      location.hash = "";
      await boot();
    } catch (error) {
      const box = $("#auth-error");
      box.textContent = error.message;
      box.classList.remove("hidden");
    }
  });
}

submitAuth("#form-signin", () => "/api/login");
submitAuth("#form-signup", () => (signupMode === "join" ? "/api/join" : "/api/company"));

setSignupMode("join");

$("#logout").addEventListener("click", async () => {
  await api("/api/logout", {});
  state = null;
  showAuth();
});

// ---------------------------------------------------------------- shell

const NAV_ITEMS = [
  { view: "dashboard", label: "Dashboard", icon: "grid" },
  { view: "stock", label: "Stock", icon: "box", count: () => state.stock.length },
  { view: "catalog", label: "Catalog", icon: "catalog" },
  { view: "deliveries", label: "Deliveries", icon: "note", count: () => state.deliveries.length },
  { view: "projects", label: "Projects", icon: "folder", count: () => state.projects.length },
  { view: "boards", label: "Boards", icon: "board", count: () => state.boards.length },
  { view: "team", label: "Team", icon: "team", adminOnly: true, count: () => (state.members || []).length },
];

function renderNav() {
  const nav = $("#nav");
  nav.replaceChildren();
  NAV_ITEMS.forEach((item) => {
    if (item.adminOnly && !isAdmin()) return;
    const btn = el("button");
    // Explicit label: the text span is hidden on mobile, so without this the
    // button would be an unnamed icon to a screen reader.
    btn.setAttribute("aria-label", item.label);
    btn.append(icon(item.icon));
    const label = el("span", "nav-label", item.label);
    btn.append(label);
    if (item.count) btn.append(el("span", "count", String(item.count())));
    const activeView = ["board-create", "board-detail"].includes(currentView) ? "boards" : currentView;
    btn.classList.toggle("active", activeView === item.view);
    btn.addEventListener("click", () => switchView(item.view));
    nav.append(btn);
  });
}

function switchView(view) {
  currentView = view;
  document.querySelectorAll(".view").forEach((v) =>
    v.classList.toggle("hidden", v.id !== `view-${view}`));
  renderNav();
  // The catalog is the one view whose data is not in /api/state, so it loads
  // when it is first opened rather than on every refresh.
  if (view === "catalog") renderCatalog();
  if (view === "board-create") renderBoardCreate();
  if (view === "board-detail") renderBoardDetail();
}

async function refresh() {
  state = await api("/api/state");
  $("#company-name").textContent = state.company.name;
  $("#company-code").textContent = state.company.code;
  $("#me-name").textContent = state.me.name;
  $("#me-role").textContent = roleLabel(state.me.role);
  $("#me-avatar").textContent = state.me.name
    .split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase();
  renderNav();
  renderDashboard();
  renderStock();
  // Stock badges in the catalog move with every receipt, so redraw it when it
  // is already loaded. When a custom part was just added the list is stale, so
  // re-fetch instead of drawing the old one.
  if (catalog) drawCatalog();
  else if (currentView === "catalog") renderCatalog();
  renderDeliveries();
  renderProjects();
  renderBoards();
  if (currentView === "board-create") renderBoardCreate();
  if (currentView === "board-detail") renderBoardDetail();
  if (isAdmin()) renderTeam();
}

async function boot() {
  // Ahead of the session check, not inside it: signing in from the auth screen
  // renders straight from `refresh()` and never comes back through boot, so a
  // manifest loaded only on the authenticated path would be empty there.
  await loadCatalogImages();
  try {
    await refresh();
    $("#auth").classList.add("hidden");
    $("#main").classList.remove("hidden");
  } catch {
    showAuth();
  }
}

// ---------------------------------------------------------------- shared pieces

function viewHead(title, ...actions) {
  const head = el("div", "view-head");
  head.append(el("h2", null, title));
  actions.forEach((a) => head.append(a));
  return head;
}

function emptyState(iconName, text) {
  const box = el("div", "empty");
  const chip = el("div", "chip-icon");
  chip.append(icon(iconName, 20));
  box.append(chip, el("p", null, text));
  return box;
}

function smallBtn(label, cls, iconName, onClick) {
  const btn = el("button", `btn-small ${cls || ""}`);
  if (iconName) btn.append(icon(iconName, 14));
  btn.append(document.createTextNode(label));
  btn.addEventListener("click", onClick);
  return btn;
}

const STATUS_META = {
  "Design": { cls: "s-design" },
  "In Progress": { cls: "s-progress" },
  "Completed": { cls: "s-done" },
};

function statusBadge(status) {
  const meta = STATUS_META[status] || { cls: "" };
  const badge = el("span", `badge ${meta.cls}`);
  badge.append(el("span", "dot"), document.createTextNode(status));
  return badge;
}

function movementRow(m) {
  const row = el("div", "row");
  const inbound = m.kind !== "consume";
  row.append(chipIcon(inbound ? "arrowIn" : "arrowOut", inbound ? "var(--positive)" : "var(--secondary)"));
  const main = el("div", "row-main");
  main.append(el("div", "row-title", m.partName));
  const when = new Date(m.date).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" });
  main.append(el("div", "row-sub", [m.reference, m.userName, when].filter(Boolean).join(" · ")));
  const delta = m.kind === "consume" ? -m.quantity : m.quantity;
  row.append(main, el("div", `delta ${delta >= 0 ? "pos" : "neg"}`, delta >= 0 ? `+${delta}` : `${delta}`));
  return row;
}

// ---------------------------------------------------------------- dashboard

function statTile(color, label, value, sub) {
  const tile = el("div", "stat");
  const top = el("div", "stat-top");
  const dot = el("div", "dot-i");
  dot.style.background = color;
  top.append(dot, el("div", "label", label));
  tile.append(top, el("div", "value", String(value)));
  tile.append(el("div", "sub", sub || "\u00a0"));
  return tile;
}

function panel(title, meta, ...actions) {
  const box = el("div", "panel");
  const head = el("div", "panel-head");
  head.append(el("h3", null, title));
  if (meta) head.append(el("span", "meta", meta));
  actions.forEach((a) => head.append(a));
  box.append(head);
  const body = el("div", "panel-body");
  box.append(body);
  box.body = body;
  return box;
}

function renderDashboard() {
  const view = $("#view-dashboard");
  view.replaceChildren();
  const today = new Date();
  const low = state.stock
    .filter((item) => item.minimumLevel != null && item.onHand <= item.minimumLevel)
    .sort((a, b) => (a.onHand - a.minimumLevel) - (b.onHand - b.minimumLevel));
  const activeProjects = state.projects.filter((project) => project.status !== "Completed");
  const openBoards = state.boards.filter((board) => board.status !== "Completed");
  const unassignedBoards = openBoards.filter((board) => !board.assignedTo);
  const overdueProjects = activeProjects.filter((project) => project.dueDate && new Date(project.dueDate) < today);
  const units = state.stock.reduce((sum, item) => sum + Math.max(item.onHand, 0), 0);

  const hero = el("section", "manager-hero");
  const heroCopy = el("div", "manager-hero-copy");
  heroCopy.append(
    el("div", "manager-eyebrow", today.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })),
    el("h2", null, `Good ${today.getHours() < 12 ? "morning" : today.getHours() < 18 ? "afternoon" : "evening"}, ${state.me.name.split(/\s+/)[0]}`),
    el("p", null, "Projects, production and stock—one clear view of what needs your attention."),
  );
  hero.append(heroCopy);
  if (isAdmin()) {
    const quick = el("div", "manager-quick-actions");
    quick.append(
      smallBtn("New project", "accent", "plus", openNewProjectModal),
      smallBtn("New board", "", "plus", openNewBoardModal),
    );
    hero.append(quick);
  }
  view.append(hero);

  const kpis = el("div", "manager-kpis");
  const managerKpi = (iconName, color, label, value, note, target) => {
    const card = el("button", "manager-kpi");
    card.type = "button";
    card.append(chipIcon(iconName, color));
    const copy = el("div", "manager-kpi-copy");
    copy.append(el("span", null, label), el("strong", null, String(value)), el("small", null, note));
    card.append(copy, icon("chevron", 16));
    card.addEventListener("click", () => switchView(target));
    return card;
  };
  kpis.append(
    managerKpi("folder", "var(--primary)", "Active projects", activeProjects.length, `${state.projects.length} total`, "projects"),
    managerKpi("board", "var(--secondary)", "Boards in production", openBoards.length, `${unassignedBoards.length} unassigned`, "boards"),
    managerKpi("alert", low.length ? "var(--warning)" : "var(--positive)", "Low stock", low.length, low.length ? "needs ordering" : "stock is healthy", "stock"),
    managerKpi("box", "var(--positive)", "Parts on hand", units.toLocaleString(), `${state.stock.length} tracked types`, "stock"),
  );
  view.append(kpis);

  const managerGrid = el("div", "manager-grid");
  const mainColumn = el("div", "manager-main");
  const sideColumn = el("div", "manager-side");
  managerGrid.append(mainColumn, sideColumn);
  view.append(managerGrid);

  const attentionCount = low.length + unassignedBoards.length + overdueProjects.length;
  const attentionPanel = panel("Needs attention", attentionCount ? `${attentionCount} items` : "All clear");
  attentionPanel.classList.add("attention-panel");
  attentionPanel.body.classList.add("manager-attention-list");
  const attentionItem = (iconName, color, title, detail, actionLabel, action) => {
    const item = el("button", "attention-item");
    item.type = "button";
    item.append(chipIcon(iconName, color));
    const copy = el("span", "attention-copy");
    copy.append(el("strong", null, title), el("small", null, detail));
    item.append(copy, el("span", "attention-action", actionLabel), icon("chevron", 15));
    item.addEventListener("click", action);
    return item;
  };
  overdueProjects.slice(0, 2).forEach((project) => attentionPanel.body.append(attentionItem(
    "folder", "var(--warning)", `${project.name} is overdue`,
    `${project.customer} · due ${new Date(project.dueDate).toLocaleDateString()}`, "Open projects", () => switchView("projects"),
  )));
  unassignedBoards.slice(0, 2).forEach((board) => attentionPanel.body.append(attentionItem(
    "board", "var(--secondary)", `${board.number} needs an owner`,
    [board.name, board.project !== "No Project" ? board.project : board.customer].filter(Boolean).join(" · "), "Assign", () => openAssignModal(board),
  )));
  low.slice(0, 3).forEach((item) => attentionPanel.body.append(attentionItem(
    "alert", "var(--warning)", `${item.part.manufacturer} ${item.part.model}`,
    `${item.onHand} on hand · minimum ${item.minimumLevel}${item.location ? ` · ${item.location}` : ""}`, "Review stock", () => switchView("stock"),
  )));
  if (!attentionCount) {
    attentionPanel.body.append(el("div", "manager-clear", "No overdue projects, unassigned boards or low-stock parts."));
  }
  mainColumn.append(attentionPanel);

  const projectsPanel = panel("Projects", `${activeProjects.length} active`, smallBtn("View all", "", null, () => switchView("projects")));
  projectsPanel.body.classList.add("project-snapshot");
  if (!state.projects.length) {
    projectsPanel.body.append(emptyState("folder", isAdmin() ? "Create your first project to organize its boards and customer." : "No projects yet."));
  } else {
    state.projects.slice(0, 5).forEach((project) => {
      const projectBoards = state.boards.filter((board) => board.project === project.name);
      const completed = projectBoards.filter((board) => board.status === "Completed").length;
      const progress = projectBoards.length ? Math.round((completed / projectBoards.length) * 100) : 0;
      const row = el("button", "project-snapshot-row");
      row.type = "button";
      const identity = el("span", "project-identity");
      const color = el("i");
      color.style.background = project.colorHex || "var(--primary)";
      const names = el("span");
      names.append(el("strong", null, project.name), el("small", null, [project.customer, project.site].filter(Boolean).join(" · ")));
      identity.append(color, names);
      const progressWrap = el("span", "project-progress");
      const meter = el("span", "manager-meter");
      const fill = el("i");
      fill.style.width = `${progress}%`;
      meter.append(fill);
      progressWrap.append(el("small", null, `${completed}/${projectBoards.length} boards complete`), meter);
      row.append(identity, progressWrap, el("strong", "project-percent", `${progress}%`), icon("chevron", 15));
      row.addEventListener("click", () => switchView("projects"));
      projectsPanel.body.append(row);
    });
  }
  mainColumn.append(projectsPanel);

  const boardCounts = ["Design", "In Progress", "Completed"].map((status) => ({
    status,
    count: state.boards.filter((board) => board.status === status).length,
  }));
  const boardsPanel = panel("Board workload", `${state.boards.length} total`, smallBtn("Open boards", "", null, () => switchView("boards")));
  const pipeline = el("div", "board-pipeline");
  boardCounts.forEach(({ status, count }) => {
    const stage = el("button", "pipeline-stage");
    stage.type = "button";
    stage.append(statusBadge(status), el("strong", null, String(count)), el("small", null, status === "Completed" ? "finished" : "boards"));
    stage.addEventListener("click", () => switchView("boards"));
    pipeline.append(stage);
  });
  boardsPanel.body.append(pipeline);
  sideColumn.append(boardsPanel);

  const stockPanel = panel("Low stock", low.length ? `${low.length} to review` : "Healthy", smallBtn("All stock", "", null, () => switchView("stock")));
  stockPanel.body.classList.add("flush");
  if (!low.length) {
    stockPanel.body.append(el("div", "manager-clear compact", "Every tracked part is above its minimum."));
  } else {
    const rows = el("div", "rows");
    low.slice(0, 5).forEach((item) => {
      const row = el("div", "row click");
      row.append(partChip(item.part));
      const copy = el("div", "row-main");
      copy.append(el("div", "row-title", `${item.part.manufacturer} ${item.part.model}`), el("div", "row-sub", item.location || item.part.type));
      const quantity = el("div", "qty-col");
      quantity.append(el("div", "num low", String(item.onHand)), el("div", "cap", `min ${item.minimumLevel}`));
      row.append(copy, quantity);
      row.addEventListener("click", () => switchView("stock"));
      rows.append(row);
    });
    stockPanel.body.append(rows);
  }
  sideColumn.append(stockPanel);

  if (canSeeCosts() && state.costSummary) {
    const costs = panel("Financial snapshot", "Private to managers");
    const financials = el("div", "financial-summary");
    financials.append(
      statTile("var(--primary)", "Stock value", money(state.costSummary.stockValueMinor), "current shelf value"),
      statTile("var(--secondary)", "Board parts", money(state.costSummary.boardCostMinor), "consumed on boards"),
    );
    costs.body.append(financials);
    sideColumn.append(costs);
  }

  const activity = panel("Latest stock activity", state.movements.length ? `${state.movements.length} recent events` : "");
  activity.body.classList.add("flush");
  if (!state.movements.length) {
    activity.body.append(el("div", "manager-clear compact", "No warehouse activity yet."));
  } else {
    const feed = el("div", "rows");
    state.movements.slice(0, 5).forEach((movement) => feed.append(movementRow(movement)));
    activity.body.append(feed);
  }
  mainColumn.append(activity);
}

// ---------------------------------------------------------------- stock

function renderStock() {
  const view = $("#view-stock");
  view.replaceChildren();

  const actions = [];
  if (isAdmin()) {
    actions.push(smallBtn("Add part", "accent", "plus", () => openPartPicker()));
    actions.push(smallBtn("New custom part", "", "plus", () => openNewPartModal()));
  }
  view.append(viewHead("Stock", ...actions));

  const toolbar = el("div", "toolbar");
  const wrap = el("div", "search-wrap");
  wrap.append(icon("search", 16));
  const search = el("input");
  search.placeholder = "Search stock";
  wrap.append(search);
  toolbar.append(wrap);
  view.append(toolbar);

  const list = el("div", "list");
  view.append(list);

  const draw = () => {
    list.replaceChildren();
    const q = search.value.trim().toLowerCase();
    const rows = state.stock.filter((s) =>
      !q || `${s.part.manufacturer} ${s.part.model} ${s.part.type} ${s.part.rating || ""} ${s.part.poles || ""} ${s.part.curve || ""} ${s.part.serialNumber || ""} ${s.location}`.toLowerCase().includes(q));
    if (!rows.length) {
      list.append(emptyState("box", state.stock.length
        ? "Nothing matches that search."
        : isAdmin()
          ? "No stock yet. Add a part to start tracking the warehouse."
          : "No stock yet — the boss or a manager adds parts here."));
      return;
    }
    rows.forEach((s) => {
      const row = el("div", "row");
      row.append(partChip(s.part));
      const main = el("div", "row-main");
      main.append(el("div", "row-title", `${s.part.manufacturer} ${s.part.model}`));
      const bits = [s.part.type, s.part.rating, s.part.poles, s.part.curve,
        s.part.serialNumber && `Serial: ${s.part.serialNumber}`, s.location].filter(Boolean).join(" · ");
      main.append(partSubLine(s.part, bits));
      row.append(main);

      const isLow = s.minimumLevel != null && s.onHand <= s.minimumLevel;
      const qty = el("div", "qty-col");
      qty.append(el("div", `num ${isLow ? "low" : "ok"}`, String(s.onHand)), el("div", "cap", "on hand"));
      row.append(qty);

      if (canSeeCosts()) {
        const cost = el("div", "qty-col money-col");
        const unset = s.unitCostMinor == null;
        cost.append(
          el("div", `num${unset ? " muted" : ""}`, money(s.unitCostMinor)),
          el("div", "cap", unset ? "no price" : "each"),
        );
        row.append(cost);

        const value = el("div", "qty-col money-col");
        value.append(
          el("div", `num${s.stockValueMinor == null ? " muted" : ""}`, money(s.stockValueMinor)),
          el("div", "cap", "value"),
        );
        row.append(value);
      }

      if (isAdmin()) {
        const rowActions = el("div", "row-actions");
        rowActions.append(
          smallBtn("In", "accent", "arrowIn", () => openMovementModal(s, "receive")),
          smallBtn("Out", "", "arrowOut", () => openMovementModal(s, "consume")),
        );
        const settings = el("button", "icon-btn");
        settings.title = "Part settings";
        settings.append(icon("sliders"));
        settings.addEventListener("click", () => openSettingsModal(s));
        rowActions.append(settings);
        row.append(rowActions);
      }
      list.append(row);
    });
  };
  search.addEventListener("input", draw);
  draw();
}

// ---------------------------------------------------------------- deliveries

const SOURCE_LABELS = { scan: "Scanned note", manual: "Entered by hand", stocktake: "Stocktake" };

function when(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" });
}

function deliveryTitle(d) {
  return [d.noteNumber && `Note ${d.noteNumber}`, d.supplier].filter(Boolean).join(" · ")
    || SOURCE_LABELS[d.source] || "Delivery";
}

function renderDeliveries() {
  const view = $("#view-deliveries");
  view.replaceChildren();
  view.append(viewHead("Deliveries"));

  const note = el("div", "card");
  note.style.color = "var(--ink-3)";
  note.style.fontSize = "13px";
  note.textContent =
    "Every delivery a worker confirmed on a phone, with the lines that were read and the stock they created. " +
    "Confirmations are immutable — a correction is a new stock movement, never an edit to the paperwork.";
  view.append(note);

  if (!state.deliveries.length) {
    view.append(emptyState("note", "No deliveries confirmed yet. They appear here as soon as a phone syncs."));
    return;
  }

  const list = el("div", "list");
  view.append(list);
  state.deliveries.forEach((d) => {
    const row = el("div", "row click");
    row.append(chipIcon(d.source === "scan" ? "scan" : "note",
      d.source === "scan" ? "var(--primary)" : "var(--secondary)"));
    const main = el("div", "row-main");
    main.append(el("div", "row-title", deliveryTitle(d)));
    const bits = [
      SOURCE_LABELS[d.source] || d.source,
      d.userName && `confirmed by ${d.userName}`,
      when(d.confirmedAt),
      d.pageCount ? `${d.pageCount} page${d.pageCount === 1 ? "" : "s"}` : null,
    ].filter(Boolean);
    main.append(el("div", "row-sub", bits.join(" · ")));
    row.append(main);

    // A batch is only trustworthy once every movement it claims has landed.
    if (d.missingMovements) {
      const badge = el("span", "badge s-design");
      badge.append(el("span", "dot"), document.createTextNode(`${d.missingMovements} not synced`));
      row.append(badge);
    }

    const lines = el("div", "qty-col");
    lines.append(el("div", "num", String(d.confirmedLineCount)), el("div", "cap", `of ${d.lineCount} lines`));
    row.append(lines);

    const units = el("div", "qty-col");
    units.append(el("div", "num ok", `+${d.unitCount}`), el("div", "cap", "units"));
    row.append(units);

    row.addEventListener("click", () => openDeliveryModal(d.id));
    list.append(row);
  });
}

async function openDeliveryModal(deliveryID) {
  const { delivery } = await api(`/api/delivery?id=${encodeURIComponent(deliveryID)}`);
  openModal((modal, close) => {
    modal.classList.add("wide");
    modal.append(el("h3", null, deliveryTitle(delivery)));
    modal.append(el("div", "modal-sub", [
      SOURCE_LABELS[delivery.source] || delivery.source,
      delivery.userName && `confirmed by ${delivery.userName}`,
      when(delivery.confirmedAt),
      delivery.uploadedAt !== delivery.confirmedAt ? `synced ${when(delivery.uploadedAt)}` : null,
    ].filter(Boolean).join(" · ")));

    if (delivery.pageCount) {
      const pages = el("div", "modal-sub",
        `${delivery.pageCount} page${delivery.pageCount === 1 ? "" : "s"} scanned — the original images stay on the phone for now.`);
      modal.append(pages);
    }

    modal.append(el("div", "section-label", `Lines read (${delivery.lineCount})`));
    const lines = el("div", "list-scroll");
    delivery.lines.forEach((line) => {
      const row = el("div", "row");
      const main = el("div", "row-main");
      main.append(el("div", "row-title", line.partName || "No match — not received"));
      // The raw OCR text is what makes this evidence rather than a summary.
      main.append(el("div", "row-sub", line.rawText));
      row.append(main);
      const qty = el("div", "qty-col");
      qty.append(
        el("div", `num ${line.included ? "ok" : "muted"}`, line.included ? `+${line.quantity}` : "—"),
        el("div", "cap", line.included ? "received" : "skipped"),
      );
      row.append(qty);
      lines.append(row);
    });
    modal.append(lines);

    if (delivery.missingMovements) {
      const warn = el("div", "modal-sub",
        `${delivery.missingMovements} stock movement${delivery.missingMovements === 1 ? " has" : "s have"} not reached the server yet. The phone retries automatically.`);
      warn.style.color = "var(--warning)";
      modal.append(warn);
    }

    modal.append(el("div", "section-label", `Stock created (${delivery.unitCount} units)`));
    const created = el("div", "list-scroll");
    if (!delivery.movements.length) {
      created.append(emptyState("box", "No stock movements from this delivery have synced yet."));
    } else {
      delivery.movements.forEach((m) => created.append(movementRow({ ...m, userName: delivery.userName })));
    }
    modal.append(created);

    const actions = el("div", "actions");
    const done = el("button", "btn-primary", "Close");
    done.addEventListener("click", close);
    actions.append(done);
    modal.append(actions);
  });
}

// ---------------------------------------------------------------- projects & boards

function renderProjects() {
  const view = $("#view-projects");
  view.replaceChildren();
  const actions = [];
  if (isAdmin()) actions.push(smallBtn("New project", "accent", "plus", openNewProjectModal));
  view.append(viewHead("Projects", ...actions));

  if (!state.projects.length) {
    view.append(emptyState("folder", isAdmin()
      ? "No projects yet. Create the project container, then attach boards to it."
      : "No projects yet."));
    return;
  }
  const list = el("div", "list");
  state.projects.forEach((project) => {
    const linked = state.boards.filter((board) => board.project === project.name);
    const completed = linked.filter((board) => board.status === "Completed").length;
    const row = el("div", "row");
    row.append(chipIcon("folder", project.colorHex || "var(--primary)"));
    const main = el("div", "row-main");
    main.append(el("div", "row-title", project.name));
    main.append(el("div", "row-sub", [project.customer, project.site, `${linked.length} board${linked.length === 1 ? "" : "s"}`].filter(Boolean).join(" · ")));
    row.append(main);
    if (project.dueDate) row.append(el("div", "row-sub", `Due ${new Date(project.dueDate).toLocaleString()}`));
    row.append(statusBadge(linked.length && completed === linked.length ? "Completed" : project.status));
    list.append(row);
  });
  view.append(list);
}

function renderBoards() {
  const view = $("#view-boards");
  view.replaceChildren();

  const actions = [];
  if (isAdmin()) actions.push(smallBtn("New board", "accent", "plus", openNewBoardModal));
  view.append(viewHead("Boards", ...actions));

  if (!state.boards.length) {
    view.append(emptyState("board", isAdmin()
      ? "No boards yet. Create one and assign it to whoever builds it."
      : "No boards yet."));
    return;
  }

  const mine = state.boards.filter((b) => b.assignedTo === state.me.id);
  const others = state.boards.filter((b) => b.assignedTo !== state.me.id);
  const listFor = () => { const l = el("div", "list"); view.append(l); return l; };

  const boardRow = (b, isMine) => {
    const row = el("div", "row click board-list-row");
    row.append(chipIcon("board", isMine ? "var(--primary)" : "var(--secondary)"));
    const main = el("div", "row-main");
    const title = [b.number, b.name].filter(Boolean).join(" — ");
    main.append(el("div", "row-title", title));
    main.append(el("div", "row-sub",
      [b.project !== "No Project" ? b.project : null, b.customer, b.type, b.subtype, b.assignedName ? `assigned to ${b.assignedName}` : "unassigned"].filter(Boolean).join(" · ")));
    const progress = el("div", "board-row-progress");
    const track = el("span", "progress-track");
    const fill = el("i");
    fill.style.width = `${b.completion || 0}%`;
    track.append(fill);
    progress.append(track, el("strong", null, `${b.completion || 0}%`));
    main.append(progress);
    row.append(main);

    if (canSeeCosts()) {
      const cost = el("div", "qty-col money-col");
      cost.append(el("div", "num", money(b.costMinor ?? 0)));
      cost.append(el("div", "cap", b.unpricedLines ? `${b.unpricedLines} unpriced` : "parts cost"));
      cost.title = (b.costItems || []).length
        ? (b.costItems || [])
            .map((i) => `${i.partName} x${i.quantity} = ${money(i.lineTotalMinor)}`)
            .join("\n")
        : "No parts consumed against this board yet.";
      row.append(cost);
    }

    row.append(statusBadge(b.status));

    const rowActions = el("div", "row-actions");
    if (isAdmin()) {
      rowActions.append(smallBtn("Assign", "", null, (event) => {
        event.stopPropagation();
        openAssignModal(b);
      }));
    }
    if (rowActions.childElementCount) row.append(rowActions);
    row.addEventListener("click", () => openBoardDetail(b.id));
    return row;
  };

  if (mine.length) {
    view.append(el("div", "section-label", "Your boards"));
    const l = listFor();
    mine.forEach((b) => l.append(boardRow(b, true)));
  }
  if (others.length) {
    view.append(el("div", "section-label", mine.length ? "All boards" : "Boards"));
    const l = listFor();
    others.forEach((b) => l.append(boardRow(b, false)));
  }
}

function openBoardDetail(boardID) {
  selectedBoardID = boardID;
  selectedBoardCabinet = 0;
  switchView("board-detail");
}

function boardStatusNote(board) {
  if (board.status === "Completed") return "Every required build check is complete.";
  if (board.completion > 0) return board.assignedName
    ? `Work is underway with ${board.assignedName}.`
    : "Checklist work has started; this board still needs an assignee.";
  if (board.assignedName) return `Assigned to ${board.assignedName}; ready for the first build check.`;
  return "Unassigned with no checklist work, so it remains in Design.";
}

function recalculateBoardProgress(board) {
  const totalWeight = Math.max(1, (board.checklist || []).reduce((sum, item) => sum + item.weight, 0));
  board.cabinetProgress = (board.cabinetChecklists || []).map((items) => {
    const checked = new Set(items);
    const done = (board.checklist || []).reduce((sum, item) => sum + (checked.has(item.id) ? item.weight : 0), 0);
    return Math.round((done / totalWeight) * 100);
  });
  board.completion = board.cabinetProgress.length
    ? Math.round(board.cabinetProgress.reduce((sum, value) => sum + value, 0) / board.cabinetProgress.length)
    : 0;
  board.status = board.completion >= 100
    ? "Completed"
    : (!board.assignedTo && board.completion === 0 ? "Design" : "In Progress");
}

function updateBoardChecklist(board, cabinetIndex, itemID, checked) {
  const previousCompletion = Number(board.completion) || 0;
  const selected = new Set(board.cabinetChecklists[cabinetIndex] || []);
  if (checked) selected.add(itemID);
  else selected.delete(itemID);
  board.cabinetChecklists[cabinetIndex] = [...selected];
  recalculateBoardProgress(board);
  boardChecklistAnimation = {
    boardID: board.id,
    cabinetIndex,
    itemID,
    from: previousCompletion,
  };
  boardChecklistSyncing = true;
  const revision = ++boardChecklistRevision;
  renderBoardDetail();

  boardChecklistQueue = boardChecklistQueue
    .catch(() => {})
    .then(() => api("/api/board-checklist", {
      boardID: board.id,
      cabinetIndex,
      itemID,
      checked,
    }))
    .then(async () => {
      if (revision !== boardChecklistRevision) return;
      boardChecklistSyncing = false;
      await refresh();
    })
    .catch(async () => {
      if (revision !== boardChecklistRevision) return;
      boardChecklistSyncing = false;
      await refresh();
    });
}

function animateProgressNumber(node, from, to, duration = 560) {
  if (from === to || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    node.textContent = `${to}%`;
    return;
  }
  const startedAt = performance.now();
  const frame = (now) => {
    const elapsed = Math.min((now - startedAt) / duration, 1);
    const eased = 1 - ((1 - elapsed) ** 3);
    node.textContent = `${Math.round(from + ((to - from) * eased))}%`;
    if (elapsed < 1) requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

function boardProperty(iconName, label, value) {
  const card = el("div", "board-property");
  card.append(chipIcon(iconName, "var(--primary)"));
  const copy = el("div");
  copy.append(el("span", null, label), el("strong", null, value || "Not set"));
  card.append(copy);
  return card;
}

function renderBoardDetail() {
  const view = $("#view-board-detail");
  if (!view) return;
  view.replaceChildren();
  const board = state.boards.find((item) => item.id === selectedBoardID);
  if (!board) {
    view.append(smallBtn("← Back to boards", "", null, () => switchView("boards")));
    view.append(emptyState("board", "This board is no longer available."));
    return;
  }
  const progressAnimation = boardChecklistAnimation?.boardID === board.id
    ? boardChecklistAnimation
    : null;
  const progressFrom = progressAnimation?.from ?? (Number(board.completion) || 0);
  const progressTo = Number(board.completion) || 0;

  const top = el("div", "board-detail-top");
  const identity = el("div", "board-detail-identity");
  identity.append(smallBtn("← Boards", "", null, () => switchView("boards")));
  identity.append(el("div", "eyebrow", [board.type, board.subtype].filter(Boolean).join(" · ")));
  identity.append(el("h2", null, board.name));
  identity.append(el("p", "mono", board.number));
  const actions = el("div", "board-detail-actions");
  const saveState = el("span", `board-save-state${boardChecklistSyncing ? " syncing" : ""}`,
    boardChecklistSyncing ? "Saving…" : "Cloud synced");
  saveState.prepend(el("i"));
  actions.append(saveState);
  actions.append(statusBadge(board.status));
  if (isAdmin()) actions.append(smallBtn(board.assignedTo ? "Reassign" : "Assign board", "accent", null, () => openAssignModal(board)));
  top.append(identity, actions);
  view.append(top);

  const progressCard = el("section", "board-progress-card");
  const progressLayout = el("div", "board-progress-layout");
  const progressHead = el("div", "board-progress-head");
  const progressTitle = el("div");
  progressTitle.append(el("span", "eyebrow", "Production status"), el("h3", null, board.status));
  progressHead.append(progressTitle, el("p", null, boardStatusNote(board)));
  const dial = el("div", "board-progress-dial");
  dial.style.setProperty("--progress", `${progressFrom}%`);
  const dialInner = el("div");
  const dialValue = el("strong", null, `${progressFrom}%`);
  dialValue.setAttribute("aria-live", "polite");
  dialInner.append(dialValue, el("span", null, "complete"));
  dial.append(dialInner);
  progressLayout.append(progressHead, dial);
  const progressTrack = el("div", "board-progress-track");
  const progressFill = el("i");
  progressFill.style.width = `${progressFrom}%`;
  progressTrack.append(progressFill);
  progressCard.append(progressLayout, progressTrack);
  view.append(progressCard);

  const properties = el("div", "board-property-grid");
  const outDate = board.dateOut ? new Date(board.dateOut).toLocaleDateString() : "Not set";
  const dueDate = board.dueDate ? new Date(board.dueDate).toLocaleDateString() : "No due date";
  properties.append(
    boardProperty("folder", "Project", board.project === "No Project" ? "No project" : board.project),
    boardProperty("team", "Builder", board.assignedName || "Unassigned"),
    boardProperty("cabinet", "Build", `${board.cabinetCount} cabinet${String(board.cabinetCount) === "1" ? "" : "s"} · ${board.buildFormat}`),
    boardProperty("boltShield", "Main breaker", [board.mainBreakerType, board.mainBreakerModel, board.mainBreakerAmpere].filter(Boolean).join(" · ")),
    boardProperty("hash", "Customer", board.customer),
    boardProperty("note", "Schedule", `Out ${outDate} · Due ${dueDate}`),
  );
  view.append(properties);

  const work = el("div", "board-detail-grid");
  const checklistPanel = el("section", "panel board-checklist-panel");
  const cabinetCount = Math.max(1, Number(board.cabinetCount) || 1);
  const checklistHead = el("div", "panel-head");
  const heading = el("div");
  heading.append(el("span", "eyebrow", "Workshop progress"), el("h3", null, "Build checklist"),
    el("p", null, "Tap a plate once—the update is instant and syncs in the background."));
  checklistHead.append(heading, el("strong", "checklist-cabinet-label", cabinetCount > 1
    ? `Cabinet ${selectedBoardCabinet + 1} of ${cabinetCount}`
    : "Single cabinet"));
  checklistPanel.append(checklistHead);

  selectedBoardCabinet = Math.min(Math.max(selectedBoardCabinet, 0), cabinetCount - 1);
  if (cabinetCount > 1) {
    const tabs = el("div", "cabinet-tabs");
    for (let index = 0; index < cabinetCount; index += 1) {
      const tab = el("button", index === selectedBoardCabinet ? "active" : "");
      tab.append(document.createTextNode(`Cabinet ${index + 1}`), el("span", null, `${board.cabinetProgress[index] || 0}%`));
      tab.addEventListener("click", () => {
        selectedBoardCabinet = index;
        renderBoardDetail();
      });
      tabs.append(tab);
    }
    checklistPanel.append(tabs);
  }

  const canCheck = isAdmin() || board.assignedTo === state.me.id;
  const checked = new Set(board.cabinetChecklists[selectedBoardCabinet] || []);
  const checklist = el("div", "board-checklist");
  (board.checklist || []).forEach((item) => {
    const isChecked = checked.has(item.id);
    const isChanging = progressAnimation
      && progressAnimation.cabinetIndex === selectedBoardCabinet
      && progressAnimation.itemID === item.id;
    const button = el("button", `check-row${isChecked ? " checked" : ""}${isChanging ? " just-changed" : ""}`);
    button.setAttribute("aria-pressed", String(isChecked));
    button.disabled = !canCheck;
    const mark = el("span", "check-mark", isChecked ? "✓" : "");
    const text = el("span", "check-copy");
    text.append(el("strong", null, item.title), el("small", null, `${item.weight}% weight`));
    button.append(mark, text);
    button.addEventListener("click", () => updateBoardChecklist(
      board, selectedBoardCabinet, item.id, !isChecked));
    checklist.append(button);
  });
  checklistPanel.append(checklist);
  if (!canCheck) checklistPanel.append(el("p", "board-permission-note", "Assign this board to yourself, or ask a manager, to update its checklist."));
  work.append(checklistPanel);

  const linkedPanel = el("section", "panel board-linked-panel");
  const linkedHead = el("div", "panel-head");
  linkedHead.append(el("h3", null, "Linked production data"));
  linkedPanel.append(linkedHead);
  const linkedList = el("div", "board-linked-list");
  linkedList.append(boardProperty("box", "Stock issues", (board.costItems || []).length
    ? `${(board.costItems || []).length} part type${(board.costItems || []).length === 1 ? "" : "s"}`
    : "No stock issued yet"));
  if (canSeeCosts()) linkedList.append(boardProperty("pulse", "Parts cost", money(board.costMinor || 0)));
  linkedList.append(boardProperty("folder", "Customer / project", [board.customer, board.project !== "No Project" ? board.project : null].filter(Boolean).join(" · ")));
  linkedPanel.append(linkedList);
  if ((board.costItems || []).length) {
    const parts = el("div", "linked-parts");
    (board.costItems || []).slice(0, 8).forEach((item) => {
      parts.append(el("div", null, `${item.partName} × ${item.quantity}`));
    });
    linkedPanel.append(parts);
  }
  work.append(linkedPanel);
  view.append(work);

  if (progressAnimation) {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        dial.style.setProperty("--progress", `${progressTo}%`);
        progressFill.style.width = `${progressTo}%`;
        animateProgressNumber(dialValue, progressFrom, progressTo);
      });
    });
    boardChecklistAnimation = null;
  }
}

// ---------------------------------------------------------------- team

function renderTeam() {
  const view = $("#view-team");
  view.replaceChildren();

  const actions = (state.me.invitableRoles || []).map((role, index) =>
    smallBtn(`${roleLabel(role)} link`, index === 0 ? "accent" : "", "link", () => createInvite(role)));
  view.append(viewHead("Team", ...actions));

  const info = el("div", "card");
  info.style.color = "var(--ink-3)";
  info.style.fontSize = "13px";
  info.textContent =
    "Managers run the warehouse and see costs. Staff Managers run the floor \u2014 stock and boards \u2014 but not prices. " +
    "QA reviews work without changing stock. Staff see stock and their own boards.";
  view.append(info);

  if ((state.invites || []).length) {
    view.append(el("div", "section-label", "Active invite links"));
    state.invites.forEach((invite) => {
      const card = el("div", "card");
      const head = el("div", "row");
      head.style.cssText = "border:0;background:none;padding:0";
      const roleBadge = el("span", `badge ${invite.role}`, roleLabel(invite.role));
      const grow = el("div", "row-main");
      grow.append(roleBadge);
      head.append(grow);
      const link = `${location.origin}/#join/${state.company.code}/${invite.code}`;
      const copy = smallBtn("Copy link", "accent", "copy", async () => {
        await navigator.clipboard.writeText(link);
        copy.replaceChildren(icon("copy", 14), document.createTextNode("Copied"));
        setTimeout(() => copy.replaceChildren(icon("copy", 14), document.createTextNode("Copy link")), 1500);
      });
      const revoke = smallBtn("Revoke", "danger", "x", async () => {
        await api("/api/invite-revoke", { code: invite.code });
        await refresh();
        switchView("team");
      });
      head.append(copy, revoke);
      card.append(head, Object.assign(el("div", "invite-link", link)));
      view.append(card);
    });
  }

  view.append(el("div", "section-label", "Members"));
  const memberList = el("div", "list");
  view.append(memberList);
  (state.members || []).forEach((member) => {
    const row = el("div", "row");
    const avatar = el("div", "avatar", member.name.split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase());
    row.append(avatar);
    const main = el("div", "row-main");
    main.append(el("div", "row-title", member.name + (member.active ? "" : " (disabled)")));
    main.append(el("div", "row-sub", `joined ${new Date(member.createdAt).toLocaleDateString()}`));
    row.append(main, el("span", `badge ${member.role}`, roleLabel(member.role)));
    if (canManageMembers() && member.role !== "owner") {
      const rowActions = el("div", "row-actions");

      // Owner-only role change. The API re-checks, so this is convenience.
      const roleSelect = el("select", "role-select");
      ["manager", "staff-manager", "qa", "staff"].forEach((role) => {
        const option = el("option", null, roleLabel(role));
        option.value = role;
        if (role === member.role) option.selected = true;
        roleSelect.append(option);
      });
      roleSelect.addEventListener("change", async () => {
        await api("/api/member-update", { userID: member.id, role: roleSelect.value });
        await refresh();
        switchView("team");
      });
      rowActions.append(roleSelect);

      rowActions.append(smallBtn(member.active ? "Disable" : "Enable", member.active ? "danger" : "accent", null, async () => {
        await api("/api/member-update", { userID: member.id, active: !member.active });
        await refresh();
        switchView("team");
      }));
      row.append(rowActions);
    }
    memberList.append(row);
  });
}

async function createInvite(role) {
  await api("/api/invites", { role });
  await refresh();
  switchView("team");
}

// ---------------------------------------------------------------- modals

function openModal(build) {
  const root = $("#modal-root");
  const backdrop = el("div", "modal-backdrop");
  const modal = el("div", "modal");
  const close = () => root.replaceChildren();
  backdrop.addEventListener("click", (event) => {
    if (event.target === backdrop) close();
  });
  build(modal, close);
  backdrop.append(modal);
  root.replaceChildren(backdrop);
  modal.querySelector("input")?.focus();
}

function modalActions(close, submitLabel, onSubmit) {
  const actions = el("div", "actions");
  const cancel = el("button", "btn-ghost", "Cancel");
  cancel.addEventListener("click", close);
  const ok = el("button", "btn-primary", submitLabel);
  ok.addEventListener("click", onSubmit);
  actions.append(cancel, ok);
  return actions;
}

function field(labelText, placeholder, type = "text") {
  const label = el("label", null, labelText);
  const input = el("input");
  input.placeholder = placeholder;
  input.type = type;
  label.append(input);
  return { label, input };
}

function selectField(labelText, values, selected) {
  const label = el("label", null, labelText);
  const select = el("select");
  values.forEach((value) => select.append(new Option(value, value, false, value === selected)));
  label.append(select);
  return { label, select };
}

/** The part a modal is acting on: its photo, its name, and its brand.
 *
 * `lead` is for a modal whose subject *is* the part, so the head stands in for
 * the `<h3>` instead of sitting under one and repeating it. */
function partModalHead(part, note, lead = false) {
  const head = el("div", `part-head${lead ? " lead" : ""}`);
  const url = partPhotoURL(part);
  if (url) {
    const figure = el("div", "part-photo");
    const img = el("img");
    img.src = url;
    img.alt = `${part.manufacturer} ${part.model}`;
    img.addEventListener("error", () => figure.remove());
    figure.append(img);
    head.append(figure);
  }
  const text = el("div", "part-head-text");
  text.append(el("div", "part-head-title", `${part.manufacturer} ${part.model}`));
  const bits = [part.type, part.rating, note].filter(Boolean).join(" · ");
  const sub = el("div", "modal-sub brand-line");
  const mark = brandMark(part.manufacturer);
  if (mark) sub.append(mark);
  if (bits) sub.append(el("span", null, bits));
  text.append(sub);
  head.append(text);
  return head;
}

function openMovementModal(entry, kind) {
  openModal((modal, close) => {
    modal.append(el("h3", null, kind === "receive" ? "Stock in" : "Stock out"));
    modal.append(partModalHead(entry.part, `${entry.onHand} on hand`));
    const qty = field("Quantity", "e.g. 10", "number");
    const ref = field(kind === "consume" ? "Board number" : "Delivery note / reference", "optional");
    modal.append(qty.label, ref.label);
    modal.append(modalActions(close, "Save", async () => {
      const quantity = parseInt(qty.input.value, 10);
      if (!quantity || quantity <= 0) return;
      await api("/api/movements", { partID: entry.part.id, kind, quantity, reference: ref.input.value });
      close();
      await refresh();
      switchView("stock");
    }));
  });
}

function openSettingsModal(entry) {
  openModal((modal, close) => {
    modal.append(el("h3", null, "Part settings"));
    modal.append(partModalHead(entry.part));
    const min = field("Minimum level (0 = no alert)", "0", "number");
    min.input.value = entry.minimumLevel ?? 0;
    const loc = field("Location", "Shelf / drawer");
    loc.input.value = entry.location;
    modal.append(min.label, loc.label);

    // Only rendered when the server sent prices; posting unitCost from anyone
    // else is refused server-side regardless.
    let price = null;
    if (canSeeCosts()) {
      price = field("Unit price (blank = unpriced)", "0.00", "number");
      price.input.step = "0.01";
      price.input.min = "0";
      price.input.value = entry.unitCostMinor == null ? "" : (entry.unitCostMinor / 100).toFixed(2);
      modal.append(price.label);
    }

    modal.append(modalActions(close, "Save", async () => {
      const minimum = parseInt(min.input.value, 10) || 0;
      const payload = {
        partID: entry.part.id,
        minimumLevel: minimum === 0 ? null : minimum,
        location: loc.input.value,
      };
      if (price) {
        const raw = price.input.value.trim();
        payload.unitCost = raw === "" ? null : Number(raw);
      }
      await api("/api/part-settings", payload);
      close();
      await refresh();
      switchView("stock");
    }));
  });
}

function stockCurveOptions(part) {
  const type = String(part.type || "").toUpperCase();
  if (type.includes("RCBO")) {
    return ["B Curve · 30mA", "C Curve · 30mA", "D Curve · 30mA", "C Curve · 100mA", "C Curve · 300mA"];
  }
  if (type.includes("RCD") || type.includes("RCCB")) {
    return ["30mA Type AC", "30mA Type A", "30mA Type F", "100mA Type A", "300mA Type A"];
  }
  if (type.includes("MCCB") || type.includes("ACB")) {
    return ["Thermal-magnetic", "Electronic trip", "LSI", "LSIG"];
  }
  if (type.includes("MCB")) return ["B Curve", "C Curve", "D Curve"];
  return [];
}

function exactChoiceField(labelText, placeholder, values, selected = "") {
  const field = selectField(labelText, [placeholder, ...values], values.includes(selected) ? selected : placeholder);
  field.placeholder = placeholder;
  return field;
}

/** Turn a generic catalog model into the exact item a manager physically stocks. */
function openStockVariantModal(template) {
  openModal((modal, close) => {
    modal.classList.add("wide");
    modal.append(partModalHead(template, "Choose the exact stock variant", true));

    const grid = el("div", "creation-grid stock-variant-grid");
    const ratingValues = [...AMPERE_RATINGS];
    if (template.rating && template.rating !== "Set A" && !ratingValues.includes(template.rating)) {
      ratingValues.unshift(template.rating);
    }
    const poleValues = [...POLE_RATINGS];
    if (template.poles && !poleValues.includes(template.poles)) poleValues.unshift(template.poles);
    const rating = exactChoiceField("Amp / rating", "Select amp rating", ratingValues, template.rating);
    const poles = exactChoiceField("Poles / phase", "Select poles", poleValues, template.poles);
    const curveValues = stockCurveOptions(template);
    if (template.curve && !curveValues.includes(template.curve)) curveValues.unshift(template.curve);
    const curve = curveValues.length
      ? exactChoiceField("Curve / trip", "Select curve or trip", curveValues, template.curve)
      : null;
    const serialNumber = field("Serial number", "optional");
    const quantity = field("Opening quantity", "0", "number");
    quantity.input.min = "0";
    quantity.input.step = "1";
    quantity.input.value = "0";
    const minimum = field("Low-stock level", "optional", "number");
    minimum.input.min = "0";
    minimum.input.step = "1";
    const location = field("Stock location", "e.g. Rack A3");
    grid.append(rating.label, poles.label);
    if (curve) grid.append(curve.label);
    grid.append(serialNumber.label, quantity.label, minimum.label, location.label);
    modal.append(grid);

    const error = el("div", "form-error hidden");
    error.setAttribute("role", "alert");
    modal.append(error);
    modal.append(modalActions(close, "Add exact variant", async () => {
      error.classList.add("hidden");
      if (rating.select.value === rating.placeholder || poles.select.value === poles.placeholder
          || (curve && curve.select.value === curve.placeholder)) {
        error.textContent = "Choose the amp rating, poles, and curve/trip for this item.";
        error.classList.remove("hidden");
        return;
      }
      const openingQuantity = Math.max(0, Math.trunc(Number(quantity.input.value) || 0));
      const minimumRaw = minimum.input.value.trim();
      const minimumLevel = minimumRaw === "" ? null : Math.max(0, Math.trunc(Number(minimumRaw) || 0));
      try {
        const { part } = await api("/api/parts", {
          manufacturer: template.manufacturer,
          type: template.type,
          model: template.model,
          rating: rating.select.value,
          poles: poles.select.value,
          curve: curve ? curve.select.value : "",
          serialNumber: serialNumber.input.value,
          about: template.about || "",
          sourceID: template.sourceID || template.id,
        });
        await api("/api/part-settings", {
          partID: part.id,
          minimumLevel,
          location: location.input.value,
        });
        if (openingQuantity > 0) {
          await api("/api/movements", {
            partID: part.id,
            kind: "receive",
            quantity: openingQuantity,
            reference: "Opening stock",
          });
        }
        catalog = null;
        close();
        await refresh();
        switchView("stock");
      } catch (caught) {
        error.textContent = caught.message || "Could not add this stock variant.";
        error.classList.remove("hidden");
      }
    }));
  });
}

async function openPartPicker() {
  if (!catalog) catalog = (await api("/api/catalog")).parts;
  openModal((modal, close) => {
    modal.append(el("h3", null, "Add part to stock"));
    const wrap = el("div", "search-wrap");
    wrap.style.maxWidth = "none";
    wrap.append(icon("search", 16));
    const search = el("input");
    search.placeholder = `Search ${catalog.length} parts`;
    wrap.append(search);
    modal.append(wrap);
    const list = el("div", "list-scroll");
    modal.append(list);

    const draw = () => {
      list.replaceChildren();
      const q = search.value.trim().toLowerCase();
      catalog
        .filter((p) => !q || `${p.manufacturer} ${p.model} ${p.type} ${p.rating || ""} ${p.poles || ""} ${p.curve || ""} ${p.serialNumber || ""}`.toLowerCase().includes(q))
        .slice(0, 40)
        .forEach((p) => {
          const row = el("div", "row click");
          row.append(partChip(p));
          const main = el("div", "row-main");
          main.append(el("div", "row-title", `${p.manufacturer} ${p.model}`));
          const bits = [p.type, p.rating, p.poles, p.curve, p.serialNumber && `Serial: ${p.serialNumber}`]
            .filter(Boolean).join(" · ");
          main.append(partSubLine(p, bits));
          row.append(main);
          row.addEventListener("click", () => openStockVariantModal(p));
          list.append(row);
        });
    };
    search.addEventListener("input", draw);
    draw();
  });
}

// ---------------------------------------------------------------- catalog

/* The same catalog the iPhone apps browse: the fifteen categories come from
   `group`/`groupName` in catalog.json, which tools/gen_web_catalog.py carries
   over from the app's own component catalog. Two levels, like the app — a grid
   of categories, then the parts inside one — plus a search that cuts across
   every category at once. */

/** Which category is open, or null for the category grid. */
let catalogCategory = null;
let catalogQuery = "";

/** partID -> on-hand count, for the stock badges. */
function stockByPart() {
  return new Map(state.stock.map((s) => [s.part.id, s]));
}

/** [{id, name, parts}] in catalog order, custom parts first as in the app. */
function catalogGroups() {
  const groups = [];
  const byID = new Map();
  const bucket = (id, name) => {
    let group = byID.get(id);
    if (!group) {
      group = { id, name, parts: [] };
      byID.set(id, group);
      groups.push(group);
    }
    return group;
  };
  for (const part of catalog || []) {
    // A part the company invented has no category of its own.
    if (part.group) bucket(part.group, part.groupName || part.group).parts.push(part);
    else bucket("custom", "Custom parts").parts.push(part);
  }
  return groups.sort((a, b) => (a.id === "custom" ? -1 : b.id === "custom" ? 1 : 0));
}

function matchesQuery(part, q) {
  if (!q) return true;
  return `${part.manufacturer} ${part.model} ${part.type} ${part.rating} ${part.poles} ${part.curve} ${part.serialNumber || ""}`
    .toLowerCase().includes(q);
}

async function renderCatalog() {
  const view = $("#view-catalog");
  if (!catalog) {
    view.replaceChildren(viewHead("Catalog"), emptyState("box", "Loading the catalog…"));
    catalog = (await api("/api/catalog")).parts;
  }
  drawCatalog();
}

function drawCatalog() {
  const view = $("#view-catalog");
  view.replaceChildren();

  const groups = catalogGroups();
  const stock = stockByPart();
  const q = catalogQuery.trim().toLowerCase();
  const open = groups.find((g) => g.id === catalogCategory) || null;

  const actions = [];
  if (isAdmin()) actions.push(smallBtn("New custom part", "ghost", "plus", openNewPartModal));
  view.append(viewHead(open ? open.name : "Catalog", ...actions));

  const wrap = el("div", "search-wrap");
  wrap.append(icon("search", 16));
  const search = el("input");
  search.placeholder = `Search ${(catalog || []).length} parts`;
  search.value = catalogQuery;
  search.addEventListener("input", () => {
    catalogQuery = search.value;
    drawCatalog();
    // Redrawing replaces the input, so put the caret back where it was.
    const next = view.querySelector(".search-wrap input");
    if (next) { next.focus(); next.setSelectionRange(next.value.length, next.value.length); }
  });
  wrap.append(search);
  view.append(wrap);

  // Searching cuts across every category — the same as typing in the app's
  // catalog search rather than drilling into a category first.
  if (q) {
    const hits = (catalog || []).filter((p) => matchesQuery(p, q));
    view.append(el("div", "cat-note", hits.length === 1 ? "1 part" : `${hits.length} parts`));
    if (!hits.length) {
      view.append(emptyState("search", `Nothing in the catalog matches "${catalogQuery.trim()}".`));
      return;
    }
    const list = el("div", "list");
    hits.slice(0, 120).forEach((p) => list.append(catalogRow(p, stock)));
    view.append(list);
    if (hits.length > 120) {
      view.append(el("div", "cat-note", `Showing the first 120 of ${hits.length}. Narrow the search to see the rest.`));
    }
    return;
  }

  if (open) {
    const back = el("button", "back-link");
    back.append(icon("chevron", 14), el("span", null, "All categories"));
    back.addEventListener("click", () => { catalogCategory = null; drawCatalog(); });
    view.append(back);
    const list = el("div", "list");
    open.parts.forEach((p) => list.append(catalogRow(p, stock)));
    view.append(list);
    return;
  }

  const grid = el("div", "cat-grid");
  groups.forEach((group) => {
    const held = group.parts.reduce((sum, p) => sum + (stock.get(p.id)?.onHand || 0), 0);

    const card = el("button", "cat-card");
    // The card's text is split across three divs and an icon; name it outright
    // so it does not reach a screen reader as an unlabelled button.
    card.setAttribute("aria-label",
      `${group.name}, ${group.parts.length} parts${held ? `, ${held} in stock` : ""}`);
    const head = el("div", "cat-card-head");
    head.append(chipIcon(CATEGORY_ICONS[group.id] || "box", "var(--primary)"));
    // Only when there is something on the shelf. A green "0 in stock" pill on a
    // category whose parts are merely tracked reads as noise, and the Stock
    // view is where an empty tracked part needs to be seen.
    if (held) head.append(el("span", "cat-stock", `${held} in stock`));
    head.append(icon("chevron", 14));
    card.append(head);
    card.append(el("div", "cat-card-title", group.name));
    const sub = el("div", "cat-card-sub",
      group.parts.length === 1 ? "1 part" : `${group.parts.length} parts`);
    // Carried as an attribute as well as the pill above, because the narrow
    // layout drops the pill and prints this next to the part count instead.
    if (held) sub.dataset.stock = `${held} in stock`;
    card.append(sub);
    card.addEventListener("click", () => { catalogCategory = group.id; drawCatalog(); });
    grid.append(card);
  });
  view.append(grid);
}

/** One part in the catalog: photo, name, brand, specs, and its stock. */
/* The three pills under a catalog row, straight out of EquipmentPill: the
   type takes the brand accent, poles and rating keep the fixed blue and green
   the app gives them so the eye can find them in the same place every row. */
function partPills(part) {
  const pills = el("div", "pills");
  const add = (text, color) => {
    if (!text || text === "—") return;
    const pill = el("span", "pill", text);
    pill.style.setProperty("--pill", color);
    pills.append(pill);
  };
  add(part.type, "var(--brand)");
  add(part.poles, "#7FA6C9");
  add(part.rating, "#7FAE9A");
  return pills;
}

function catalogRow(part, stock) {
  const row = tintByBrand(el("div", "row click brand-row"), part.manufacturer);
  row.append(partChip(part));
  const main = el("div", "row-main");
  main.append(el("div", "row-title", `${part.manufacturer} ${part.model}`));
  const bits = [part.type, part.rating, part.poles, part.curve]
    .filter((bit) => bit && bit !== "—").join(" · ");
  main.append(partSubLine(part, bits));
  main.append(partPills(part));
  row.append(main);

  const entry = stock.get(part.id);
  if (entry) {
    const isLow = entry.minimumLevel != null && entry.onHand <= entry.minimumLevel;
    const qty = el("div", "qty-col");
    qty.append(el("div", `num ${isLow ? "low" : "ok"}`, String(entry.onHand)),
      el("div", "cap", "on hand"));
    row.append(qty);
  } else {
    row.append(el("div", "cap muted-cap", "not tracked"));
  }

  row.addEventListener("click", () => openCatalogPartModal(part));
  return row;
}

/* BoardReferenceSection: a titled block headed by a tinted symbol. Every
   reference panel in the app is built from this, so the part sheet reads the
   same on the web as it does on the phone. */
function refSection(title, symbol, body) {
  const section = el("section", "ref-section");
  const head = el("div", "ref-head");
  head.append(icon(symbol, 13), el("span", null, title));
  section.append(head, body);
  return section;
}

/** InfoLine: label left, value right, on one row. */
function infoLines(rows) {
  const list = el("div", "info-lines");
  rows.forEach(([title, value]) => {
    if (!value || value === "—") return;
    const line = el("div", "info-line");
    line.append(el("span", "info-title", title), el("span", "info-value", value));
    list.append(line);
  });
  return list;
}

/* The catalog part sheet, following ComponentDetailSheet: the photo first
   under its brand-coloured halo, then the type tile beside the model and its
   manufacturer, then Description and Specification. */
function openCatalogPartModal(part) {
  const entry = stockByPart().get(part.id);
  openModal((modal, close) => {
    tintByBrand(modal, part.manufacturer);
    modal.classList.add("part-sheet");

    const url = partPhotoURL(part);
    if (url) {
      const figure = el("div", "part-hero");
      const img = el("img");
      img.src = url;
      img.alt = `${part.manufacturer} ${part.model}`;
      img.addEventListener("error", () => figure.remove());
      figure.append(img);
      modal.append(figure);
    }

    const head = el("div", "part-title-row");
    const tile = el("div", "type-tile");
    tile.append(icon(iconForType(part.type), 28));
    head.append(tile);
    const text = el("div", "part-title-text");
    text.append(el("div", "part-title", part.model));
    const brand = el("div", "part-brand");
    brand.append(icon("tag", 13), el("span", null, part.manufacturer));
    const mark = brandMark(part.manufacturer);
    if (mark) brand.append(mark);
    text.append(brand);
    head.append(text);
    modal.append(head);

    modal.append(el("div", "part-stock-note",
      entry ? `${entry.onHand} on hand` : "not tracked in stock"));

    if (part.about) {
      modal.append(refSection("Description", "note",
        el("p", "ref-body", part.about)));
    }

    modal.append(refSection("Specification", "layers", infoLines([
      ["Type", part.type],
      ["Rating", part.rating],
      ["Poles / phase", part.poles],
      ["Serial number", part.serialNumber],
      ["Curve / notes", part.curve],
      ["Category", part.groupName],
      ["Part id", part.id],
    ])));

    if (entry) {
      modal.append(modalActions(close, "Go to stock", () => {
        close();
        switchView("stock");
      }));
    } else if (isAdmin()) {
      modal.append(modalActions(close, "Choose variant", () => openStockVariantModal(part)));
    } else {
      // Staff can read the catalog but not decide what the company tracks.
      const actions = el("div", "actions");
      const done = el("button", "btn-primary", "Close");
      done.addEventListener("click", close);
      actions.append(done);
      modal.append(actions);
    }
  });
}

function openNewPartModal() {
  openModal((modal, close) => {
    modal.append(el("h3", null, "New custom part"));
    modal.append(el("div", "modal-sub", "For anything the catalog doesn't carry."));
    const model = field("Model", "e.g. Cable tray 200mm");
    const manufacturer = field("Manufacturer", "optional");
    const type = field("Type", "e.g. Cable Tray");
    const rating = field("Rating", "optional");
    const poles = selectField("Poles / phase", ["", ...POLE_RATINGS], "");
    const curve = field("Curve / trip", "e.g. C Curve or 30mA Type A");
    const serialNumber = field("Serial number", "optional");
    modal.append(model.label, manufacturer.label, type.label, rating.label, poles.label, curve.label, serialNumber.label);
    modal.append(modalActions(close, "Add part", async () => {
      if (!model.input.value.trim() || !type.input.value.trim()) return;
      const { part } = await api("/api/parts", {
        model: model.input.value,
        manufacturer: manufacturer.input.value,
        type: type.input.value,
        rating: rating.input.value,
        poles: poles.select.value,
        curve: curve.input.value,
        serialNumber: serialNumber.input.value,
      });
      await api("/api/part-settings", { partID: part.id, minimumLevel: null, location: "" });
      catalog = null;
      close();
      await refresh();
      switchView("stock");
    }));
  });
}

function memberSelect(selected) {
  const select = el("select");
  select.append(new Option("Unassigned", ""));
  (state.members || [])
    .filter((m) => m.active)
    .forEach((m) => select.append(new Option(`${m.name} (${m.role})`, m.id, false, m.id === selected)));
  return select;
}

const BOARD_CREATION_TYPES = [
  { id: "MDB", name: "Main Distribution", icon: "boltShield", note: "Primary low-voltage distribution board" },
  { id: "SMDB", name: "Sub Distribution", icon: "board", note: "Feeds a floor, zone, or downstream area" },
  { id: "MCC", name: "Motor Control Centre", icon: "motor", note: "Motor starters, drives, and control" },
  { id: "ATS", name: "Automatic Transfer", icon: "toggle", note: "Automatic changeover between supplies" },
  { id: "Lighting", name: "Lighting Board", icon: "bolt", note: "Lighting circuits and control" },
  { id: "Power", name: "Power Board", icon: "plug", note: "Socket and general power circuits" },
  { id: "Generator", name: "Generator Board", icon: "gauge", note: "Generator distribution and protection" },
  { id: "Solar", name: "Solar Board", icon: "pulse", note: "PV generation and AC distribution" },
  { id: "UPS", name: "UPS Board", icon: "shield", note: "Critical backed-up power" },
  { id: "Fire Pump", name: "Fire Pump Panel", icon: "alert", note: "Dedicated fire-pump control and power" },
  { id: "EV Charging", name: "EV Charging", icon: "terminal", note: "Vehicle-charging distribution" },
];

function openNewBoardModal() {
  boardCreationType = null;
  switchView("board-create");
}

function creationSteps(activeStep) {
  const steps = el("div", "creation-steps");
  ["Choose type", "Board details", "Build & track"].forEach((label, index) => {
    const step = el("div", `${index + 1 === activeStep ? "active" : ""}${index + 1 < activeStep ? " done" : ""}`);
    step.append(el("span", null, index + 1 < activeStep ? "✓" : String(index + 1)), el("strong", null, label));
    steps.append(step);
  });
  return steps;
}

function pageField(control) {
  control.label.classList.add("page-field");
  return control;
}

function renderBoardCreate() {
  const view = $("#view-board-create");
  if (!view || !isAdmin()) return;
  view.replaceChildren();

  const back = smallBtn(boardCreationType ? "← Change board type" : "← Boards", "", null, () => {
    if (boardCreationType) {
      boardCreationType = null;
      renderBoardCreate();
    } else switchView("boards");
  });
  view.append(back, creationSteps(boardCreationType ? 2 : 1));

  if (!boardCreationType) {
    const hero = el("div", "creation-hero");
    hero.append(el("span", "eyebrow", "New production board"));
    hero.append(el("h2", null, "What are you building?"));
    hero.append(el("p", null, "Start with the board type. The next page only asks for details that matter to that build."));
    view.append(hero);
    const grid = el("div", "board-type-grid");
    BOARD_CREATION_TYPES.forEach((boardType) => {
      const button = el("button", "board-type-card");
      button.append(chipIcon(boardType.icon, "var(--primary)"));
      const copy = el("div");
      copy.append(el("span", "board-type-code", boardType.id), el("h3", null, boardType.name), el("p", null, boardType.note));
      button.append(copy, icon("chevron", 18));
      button.addEventListener("click", () => {
        boardCreationType = boardType.id;
        renderBoardCreate();
        window.scrollTo({ top: 0, behavior: "smooth" });
      });
      grid.append(button);
    });
    view.append(grid);
    return;
  }

  const selectedType = BOARD_CREATION_TYPES.find((item) => item.id === boardCreationType);
  const detailsHero = el("div", "creation-hero compact");
  const heroType = el("div", "selected-board-type");
  heroType.append(chipIcon(selectedType.icon, "var(--primary)"));
  const heroCopy = el("div");
  heroCopy.append(el("span", "eyebrow", selectedType.id), el("h2", null, selectedType.name), el("p", null, selectedType.note));
  heroType.append(heroCopy);
  detailsHero.append(heroType);
  view.append(detailsHero);

  const form = el("form", "board-create-form");
  const number = pageField(field("Board number", "3918.24-1"));
  const group = pageField(field("Board group", "optional group"));
  const name = pageField(field("Board name", "Main LV Board"));
  const projects = ["No Project", ...state.projects.map((item) => item.name)];
  const project = pageField(selectField("Project", projects, "No Project"));
  const customer = pageField(field("Customer name", "search or type customer"));
  const company = pageField(field("Company you are doing it for", "optional company"));
  const subtype = pageField(field("Subtype", "Standard"));
  subtype.input.value = "Standard";
  const manufacturer = pageField(selectField("Board manufacturer", ["Generic", "ABB", "Schneider", "Siemens", "Eaton", "Rittal", "HAGER"], "Generic"));
  const cabinets = pageField(selectField("Cabinets", Array.from({ length: 12 }, (_, index) => String(index + 1)), "1"));
  const buildFormat = pageField(selectField("Build format", ["Panels", "Plate"], "Panels"));
  const dateOut = pageField(field("Out date", "", "date"));
  dateOut.input.valueAsDate = new Date();
  const dueDate = pageField(field("Due date/time", "optional", "datetime-local"));
  const mainBreakerType = pageField(selectField("Main breaker type", ["Main Breaker", "MCB", "MCCB", "ACB", "Isolator", "Fuse Switch"], "Main Breaker"));
  const mainBreakerModel = pageField(field("Main breaker model", "e.g. Tmax XT7"));
  const mainBreakerAmpere = pageField(field("Main breaker ampere", "630A"));
  mainBreakerAmpere.input.value = "630A";
  const assign = el("label", "page-field", "Give the board to");
  const assignee = memberSelect(null);
  assign.append(assignee);

  project.select.addEventListener("change", () => {
    const selectedProject = state.projects.find((item) => item.name === project.select.value);
    customer.input.value = selectedProject?.customer || "";
    customer.input.disabled = Boolean(selectedProject);
  });

  const section = (title, note, ...controls) => {
    const box = el("section", "creation-section");
    const head = el("div", "creation-section-head");
    head.append(el("h3", null, title), el("p", null, note));
    const grid = el("div", "page-form-grid");
    controls.forEach((control) => grid.append(control.label || control));
    box.append(head, grid);
    return box;
  };
  form.append(
    section("Identity", "Name it and connect it to the right customer and project.", number, group, name, project, customer, company),
    section("Build specification", "These fields appear on the board record and in the app.", subtype, manufacturer, cabinets, buildFormat),
    section("Schedule & ownership", "An unassigned board with 0% progress stays in Design.", dateOut, dueDate, assign),
    section("Main breaker", "Record the protection device at the head of the board.", mainBreakerType, mainBreakerModel, mainBreakerAmpere),
  );
  const error = el("div", "form-error hidden");
  const actions = el("div", "page-form-actions");
  const cancel = el("button", "btn-ghost", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => switchView("boards"));
  const submit = el("button", "btn-primary", "Create board");
  submit.type = "submit";
  actions.append(cancel, submit);
  form.append(error, actions);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.classList.add("hidden");
    if (!number.input.value.trim() || !name.input.value.trim() || !customer.input.value.trim()) {
      error.textContent = "Board number, board name, and customer are required.";
      error.classList.remove("hidden");
      return;
    }
    submit.disabled = true;
    submit.textContent = "Creating…";
    try {
      const { board } = await api("/api/boards", {
        number: number.input.value,
        group: group.input.value,
        name: name.input.value,
        customer: customer.input.value,
        company: company.input.value,
        project: project.select.value,
        type: boardCreationType,
        subtype: subtype.input.value,
        manufacturer: manufacturer.select.value,
        cabinetCount: cabinets.select.value,
        buildFormat: buildFormat.select.value,
        dateOut: dateOut.input.value,
        dueDate: dueDate.input.value || null,
        mainBreakerType: mainBreakerType.select.value,
        mainBreakerModel: mainBreakerModel.input.value,
        mainBreakerAmpere: mainBreakerAmpere.input.value,
        assignedTo: assignee.value || null,
      });
      selectedBoardID = board.id;
      selectedBoardCabinet = 0;
      boardCreationType = null;
      await refresh();
      switchView("board-detail");
    } catch (caught) {
      error.textContent = caught.message || "Could not create this board.";
      error.classList.remove("hidden");
      submit.disabled = false;
      submit.textContent = "Create board";
    }
  });
  view.append(form);
}

function openNewProjectModal() {
  openModal((modal, close) => {
    modal.append(el("h3", null, "New project"));
    modal.append(el("div", "modal-sub", "Create the customer/project container first, then attach boards."));
    const name = field("Project name", "Azrieli Office Tower");
    const customer = field("Customer", "search or type customer");
    const site = field("Site or building", "optional location");
    const dueDate = field("Expected finish", "optional", "datetime-local");
    modal.append(name.label, customer.label, site.label, dueDate.label);
    modal.append(modalActions(close, "Create", async () => {
      if (!name.input.value.trim() || !customer.input.value.trim()) return;
      await api("/api/projects", {
        name: name.input.value,
        customer: customer.input.value,
        site: site.input.value,
        dueDate: dueDate.input.value || null,
      });
      close();
      await refresh();
      switchView("projects");
    }));
  });
}

function openAssignModal(board) {
  const returnView = currentView;
  openModal((modal, close) => {
    modal.append(el("h3", null, "Assign board"));
    modal.append(el("div", "modal-sub", [board.number, board.name].filter(Boolean).join(" — ")));
    const label = el("label", null, "Assigned to");
    const select = memberSelect(board.assignedTo);
    label.append(select);
    modal.append(label);
    modal.append(modalActions(close, "Save", async () => {
      await api("/api/board-update", { boardID: board.id, assignedTo: select.value || null });
      close();
      await refresh();
      switchView(returnView === "board-detail" ? "board-detail" : "boards");
    }));
  });
}

// ---------------------------------------------------------------- start

boot();
