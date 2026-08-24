import { renderMovementChart } from "/chart.js";

// PanelVault Cloud frontend — vanilla JS, no build step.

let state = null; // last /api/state payload
let catalog = null; // lazy-loaded parts list
let currentView = "dashboard";
let selectedBoardID = null;
let selectedBoardCabinet = 0;
let selectedBoardTab = "overview";
let boardCreationMode = null;
let boardCreationType = null;
let boardSchemeReading = null;
let boardSchemeUpload = null;
let projectCreationMode = null;
let projectSchemeReading = null;
let boardChecklistSyncing = false;
let boardChecklistRevision = 0;
let boardChecklistQueue = Promise.resolve();
let boardChecklistAnimation = null;
const boardArchiveFilters = { query: "", type: "All", status: "All" };

// Kept in the same order as AmpereRating and PoleRating in the iPhone app.
const AMPERE_RATINGS = [
  "0.5A", "1A", "2A", "3A", "4A", "6A", "10A", "13A", "16A", "20A", "25A", "32A",
  "40A", "50A", "63A", "80A", "100A", "125A", "160A", "200A", "225A", "250A",
  "315A", "400A", "500A", "630A", "800A", "1000A", "1250A", "1600A", "2000A",
  "2500A", "3200A", "4000A", "5000A", "6300A",
];
const POLE_RATINGS = ["1P", "1P+N", "2P", "3P", "3P+N", "4P", "3PH", "1PH", "DIN"];
// Kept in step with ManufacturerItem.defaults in the phone app. The website
// used to expose only a short subset, which made an AI-read Tamhash board fall
// back to Generic even though its manufacturer and logo already existed.
const BOARD_MANUFACTURERS = [
  "Generic", "Rittal", "ABB", "Yakir", "Tamhash", "HAGER", "Delta",
  "Schneider", "Siemens", "Eaton", "Legrand", "Mean Well", "Phoenix",
  "Danfoss", "Socomec",
];

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
  building: '<path d="M4 21V5l8-3 8 3v16"/><path d="M2 21h20"/><path d="M8 7h1"/><path d="M15 7h1"/><path d="M8 11h1"/><path d="M15 11h1"/><path d="M8 15h1"/><path d="M15 15h1"/><path d="M10 21v-3h4v3"/>',
  alert: '<path d="M12 3l10 17H2z"/><path d="M12 10v4"/><path d="M12 17.5v.5"/>',
  pulse: '<path d="M3 12h4l2.5-6 4 12L16 12h5"/>',
  hash: '<path d="M5 9h14"/><path d="M5 15h14"/><path d="M10 4L8 20"/><path d="M16 4l-2 16"/>',
  plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  arrowIn: '<path d="M12 4v12"/><path d="M7 11l5 5 5-5"/><path d="M5 20h14"/>',
  arrowOut: '<path d="M12 20V8"/><path d="M7 13l5-5 5 5"/><path d="M5 4h14"/>',
  sliders: '<path d="M4 7h10"/><circle cx="17" cy="7" r="2.5"/><path d="M20 16H10"/><circle cx="7" cy="16" r="2.5"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a1 1 0 0 1 1-1h9"/>',
  check: '<circle cx="12" cy="12" r="9"/><path d="M8 12l2.5 2.5L16.5 9"/>',
  x: '<path d="M6 6l12 12"/><path d="M18 6L6 18"/>',
  chevron: '<path d="M9 6l6 6-6 6"/>',
  link: '<path d="M10 14a4 4 0 0 0 6 .5l3-3a4 4 0 0 0-5.5-5.5l-1.5 1.5"/><path d="M14 10a4 4 0 0 0-6-.5l-3 3a4 4 0 0 0 5.5 5.5l1.5-1.5"/>',
  note: '<path d="M6 2h8l4 4v16H6z"/><path d="M14 2v5h4"/><path d="M9 12h6"/><path d="M9 16h6"/>',
  scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M3 12h18"/>',

  // Catalog categories. These mirror the SF Symbols the iPhone apps use for
  // the same eighteen groups, so a category is recognisable on either screen.
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
  // Three power poles breaking together over the coil block that pulls them.
  contactor: '<path d="M5 3v4"/><path d="M12 3v4"/><path d="M19 3v4"/><path d="M4 7l3 4"/><path d="M11 7l3 4"/><path d="M18 7l3 4"/><rect x="4" y="14" width="16" height="6" rx="1.5"/>',
  // The same drawing reduced to one pole, which is what a relay is. The pair
  // reads as a family, told apart by how many poles the coil pulls.
  relay: '<path d="M12 3v3"/><path d="M11 6l4 4"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 16.5h8"/>',
  // A cartridge fuse: body, end caps, and the element bridging them.
  fuse: '<rect x="5" y="8" width="14" height="8" rx="1.5"/><path d="M2 12h3"/><path d="M19 12h3"/><path d="M8.5 12h7"/>',
};

/** Category id -> icon, matching warehouse/Sources/Catalog.swift's group ids. */
const CATEGORY_ICONS = {
  mcbs: "bolt",
  rcbo: "shield",
  mccbs: "boltShield",
  "surge-arc": "alert",
  switching: "toggle",
  contactors: "contactor",
  fuses: "fuse",
  drives: "gauge",
  "motor-protection": "motor",
  "control-power": "plug",
  "control-automation": "cpu",
  relays: "relay",
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
let catalogImages = { components: {}, manufacturers: {}, versions: {} };

async function loadCatalogImages() {
  try {
    const res = await fetch("/catalog-images/index.json");
    if (!res.ok) return;
    const index = await res.json();
    catalogImages = {
      components: index.components || {},
      manufacturers: index.manufacturers || {},
      // Content stamps written alongside the paths — see imageURL.
      versions: index.versions || {},
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

/* A photo is replaced under the name it already had, so the path alone cannot
   tell a browser the bytes changed — and one that cached the old file under a
   long max-age will not even ask. The manifest itself is served `no-cache`, so
   the stamp it carries is always current: hanging it on the URL turns a
   replaced photo into a different URL, which no cache can answer from a stale
   entry. Absent stamp (a manifest written before this existed) just yields the
   bare path, exactly as before. */
function imageURL(file) {
  if (!file) return null;
  const path = file.split("/").map(encodeURIComponent).join("/");
  const version = catalogImages.versions && catalogImages.versions[file];
  return `/catalog-images/${path}${version ? `?v=${encodeURIComponent(version)}` : ""}`;
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
  { view: "dashboard", label: "Dashboard", icon: "grid", group: "overview" },
  { view: "projects", label: "Open Projects", icon: "folder", group: "primary", count: () => state.projects.filter((project) => project.status !== "Completed").length },
  { view: "boards", label: "Open Boards", icon: "board", group: "primary", count: () => state.boards.filter((board) => board.status !== "Completed").length },
  { view: "stock", label: "Stock", icon: "box", group: "operations", count: () => state.stock.length },
  { view: "catalog", label: "Catalog", icon: "catalog", group: "operations" },
  { view: "deliveries", label: "Deliveries", icon: "note", group: "operations", count: () => state.deliveries.length },
  { view: "team", label: "Team", icon: "team", group: "operations", adminOnly: true, count: () => (state.members || []).length },
  { view: "contacts", label: "Companies & Customers", icon: "building", group: "reference", count: () => new Set(state.projects.map((project) => project.customer).filter(Boolean)).size },
  { view: "manufacturers", label: "Manufacturers", icon: "tag", group: "reference" },
];

function renderNav() {
  const nav = $("#nav");
  nav.replaceChildren();
  let currentGroup = null;
  NAV_ITEMS.forEach((item) => {
    if (item.adminOnly && !isAdmin()) return;
    if (item.group !== currentGroup) {
      currentGroup = item.group;
      if (currentGroup === "primary") nav.append(el("span", "nav-section-label", "Work"));
      if (currentGroup === "operations") nav.append(el("span", "nav-section-label", "Operations"));
      if (currentGroup === "reference") nav.append(el("span", "nav-section-label", "Reference"));
    }
    const btn = el("button");
    btn.classList.add(`nav-${item.group}`);
    // Explicit label: the text span is hidden on mobile, so without this the
    // button would be an unnamed icon to a screen reader.
    btn.setAttribute("aria-label", item.label);
    btn.append(icon(item.icon));
    const label = el("span", "nav-label", item.label);
    btn.append(label);
    if (item.count) btn.append(el("span", "count", String(item.count())));
    const activeView = ["board-create", "board-detail"].includes(currentView)
      ? "boards"
      : currentView === "project-create" ? "projects" : currentView;
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
  if (view === "contacts") renderContacts();
  if (view === "manufacturers") renderManufacturers();
  if (view === "board-create") renderBoardCreate();
  if (view === "project-create") renderProjectCreate();
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
  renderContacts();
  if (catalog) renderManufacturers();
  renderProjects();
  renderBoards();
  if (currentView === "board-create") renderBoardCreate();
  if (currentView === "project-create") renderProjectCreate();
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
  "QA Ready": { cls: "s-qa" },
  "QA Changes": { cls: "s-attention" },
  "Completed": { cls: "s-done" },
};

const BOARD_STAGES = [
  ["design", "Design"],
  ["mechanical", "Mechanical Build"],
  ["components", "Components"],
  ["wiring", "Wiring"],
  ["finishing", "Finishing"],
  ["qa", "QA"],
  ["complete", "Complete"],
];

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

/** How many alerts the dashboard panel shows before it outgrows the panels
 * beside it. Measured, not guessed: five alert rows come to 357px against the
 * 350px of a full "Open projects" panel, so the row keeps its height; a sixth
 * adds 57px and stretches every panel in the row. The rest are one click away
 * behind "View all". */
const DASHBOARD_ALERT_LIMIT = 5;

/** One row in the urgent-alerts list. `close` is passed when the row is inside
    the all-alerts modal, so acting on it dismisses the modal first. */
function attentionItem(entry, close) {
  const item = el("button", "attention-item");
  item.type = "button";
  item.append(chipIcon(entry.icon, entry.color));
  const copy = el("span", "attention-copy");
  copy.append(el("strong", null, entry.title), el("small", null, entry.detail));
  item.append(copy, el("span", "attention-action", entry.actionLabel), icon("chevron", 15));
  item.addEventListener("click", () => {
    if (close) close();
    entry.action();
  });
  return item;
}

/** Everything that wants a manager's attention, as one ranked list.
 *
 * Low stock used to sit in its own panel down the side of the dashboard, which
 * said it was a different sort of problem from an overdue project. It is not —
 * both mean work stops — so the parts are alerts like any other now.
 *
 * The groups are interleaved rather than concatenated: a dozen low-stock parts
 * ahead of the boards would push every unassigned board off the panel, which is
 * the crowding that gave stock its own panel in the first place. Each group is
 * sorted worst-first, so the top of the list is still the worst of each kind.
 */
function dashboardAlerts(overdueProjects, lowStock, unassignedBoards) {
  const groups = [
    [...overdueProjects]
      .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate))
      .map((project) => ({
        kind: "project",
        icon: "folder",
        color: "var(--warning)",
        title: `${project.name} is overdue`,
        detail: `${project.customer} · due ${new Date(project.dueDate).toLocaleDateString()}`,
        actionLabel: "Open projects",
        action: () => switchView("projects"),
      })),
    lowStock.map((item) => {
      const out = item.onHand <= 0;
      return {
        kind: "stock",
        icon: out ? "box" : "alert",
        color: out ? "var(--negative)" : "var(--warning)",
        title: partTitle(item.part),
        detail: [
          out ? "Out of stock" : `${item.onHand} on hand`,
          `minimum ${item.minimumLevel}`,
          item.location,
        ].filter(Boolean).join(" · "),
        actionLabel: "Review stock",
        action: () => switchView("stock"),
      };
    }),
    unassignedBoards.map((board) => ({
      kind: "board",
      icon: "board",
      color: "var(--secondary)",
      title: `${board.number} needs an owner`,
      detail: [board.name, board.project !== "No Project" ? board.project : board.customer].filter(Boolean).join(" · "),
      actionLabel: "Assign",
      action: () => openAssignModal(board),
    })),
  ];
  const ordered = [];
  for (let depth = 0; groups.some((group) => depth < group.length); depth += 1) {
    groups.forEach((group) => {
      if (depth < group.length) ordered.push(group[depth]);
    });
  }
  return ordered;
}

/** The full alert list, grouped by what kind of problem each one is. */
function openAlertsModal(alerts) {
  openModal((modal, close) => {
    modal.classList.add("wide");
    modal.append(el("span", "eyebrow", "Needs attention"), el("h3", null, "Urgent alerts"));
    modal.append(el("p", "modal-sub", `${alerts.length} item${alerts.length === 1 ? "" : "s"} across projects, stock and boards.`));
    const list = el("div", "manager-attention-list alert-modal-list");
    [
      ["Overdue projects", "project"],
      ["Low stock", "stock"],
      ["Unassigned boards", "board"],
    ].forEach(([label, kind]) => {
      const items = alerts.filter((entry) => entry.kind === kind);
      if (!items.length) return;
      list.append(el("div", "section-label", `${label} · ${items.length}`));
      items.forEach((entry) => list.append(attentionItem(entry, close)));
    });
    modal.append(list);
    const actions = el("div", "actions");
    const done = el("button", "btn-ghost", "Close");
    done.addEventListener("click", close);
    actions.append(done);
    modal.append(actions);
  });
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
  const qaBoards = openBoards.filter((board) => board.currentStage?.id === "qa" || board.status === "QA Ready");

  const dashboardHead = el("header", "manager-dashboard-head");
  const headCopy = el("div", "manager-dashboard-title");
  headCopy.append(
    el("h2", null, "Manager Dashboard"),
    el("p", null, "Overview of projects, board production and stock."),
  );
  dashboardHead.append(headCopy);
  const headActions = el("div", "manager-head-actions");
  headActions.append(el("span", "manager-year", String(today.getFullYear())));
  if (isAdmin()) {
    headActions.append(
      smallBtn("New project", "accent", "plus", openNewProjectModal),
      smallBtn("New board", "", "plus", openNewBoardModal),
    );
  }
  dashboardHead.append(headActions);
  view.append(dashboardHead);

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
    managerKpi("board", "var(--primary)", "Active boards", openBoards.length, `${state.boards.length} total boards`, "boards"),
    managerKpi("folder", "var(--secondary)", "Open projects", activeProjects.length, `${overdueProjects.length} overdue`, "projects"),
    managerKpi("alert", qaBoards.length ? "var(--warning)" : "var(--positive)", "Awaiting QA", qaBoards.length, qaBoards.length ? "ready for inspection" : "QA queue is clear", "boards"),
    managerKpi("box", low.length ? "var(--negative)" : "var(--positive)", "Low stock", low.length, low.length ? "needs attention" : `${units.toLocaleString()} parts on hand`, "stock"),
  );
  view.append(kpis);

  const inProgressBoards = state.boards
    .filter((board) => board.status !== "Completed")
    .sort((a, b) => (b.completion || 0) - (a.completion || 0));
  const productionPanel = panel(
    "Board progress",
    `${inProgressBoards.length} active`,
    smallBtn("View all", "", null, () => switchView("boards")),
  );
  productionPanel.classList.add("production-board-panel");
  productionPanel.body.classList.add("production-board-wrap");
  if (!inProgressBoards.length) {
    productionPanel.body.append(el("div", "manager-clear compact", "No boards are currently in production."));
  } else {
    const table = el("div", "production-board-table");
    const tableHead = el("div", "production-board-head");
    ["Board", "Project", "Assigned to", "Stage", "Completion"].forEach((label) => tableHead.append(el("span", null, label)));
    table.append(tableHead);
    inProgressBoards.slice(0, 8).forEach((board) => {
      const row = el("button", "production-board-row");
      row.type = "button";

      const identity = el("span", "production-board-identity");
      const identityCopy = el("span");
      identityCopy.append(
        el("strong", null, board.number || "Untitled board"),
        el("small", null, board.name || board.type || "Board"),
      );
      identity.append(
        chipIcon("board", "var(--secondary)"),
        identityCopy,
      );

      const project = el("span", "production-board-cell");
      project.append(
        el("strong", null, board.project && board.project !== "No Project" ? board.project : "No project"),
        el("small", null, board.customer || board.type || "—"),
      );

      const owner = el("span", "production-board-owner");
      const ownerInitials = (board.assignedName || "?")
        .split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
      owner.append(el("i", null, ownerInitials || "?"), el("span", null, board.assignedName || "Unassigned"));

      const stage = el("span", "production-board-stage");
      stage.append(el("i"), el("span", null, board.currentStage?.label || board.status || "Design"));
      const completion = el("strong", "production-board-percent", `${board.completion || 0}%`);

      row.append(identity, project, owner, stage, completion, icon("chevron", 15));
      row.addEventListener("click", () => openBoardDetail(board.id));
      table.append(row);
    });
    productionPanel.body.append(table);
  }
  const dashboardTopGrid = el("div", "dashboard-top-grid");
  const dashboardWorkGrid = el("div", "dashboard-work-grid");
  const dashboardSideStack = el("div", "dashboard-side-stack");
  view.append(dashboardTopGrid, dashboardWorkGrid);

  const alerts = dashboardAlerts(overdueProjects, low, unassignedBoards);
  const shownAlerts = alerts.slice(0, DASHBOARD_ALERT_LIMIT);
  const hiddenAlerts = alerts.length - shownAlerts.length;
  const attentionMeta = alerts.length
    ? (hiddenAlerts ? `${shownAlerts.length} of ${alerts.length}` : `${alerts.length} item${alerts.length === 1 ? "" : "s"}`)
    : "All clear";
  const attentionPanel = hiddenAlerts
    ? panel("Urgent alerts", attentionMeta, smallBtn("View all", "", null, () => openAlertsModal(alerts)))
    : panel("Urgent alerts", attentionMeta);
  attentionPanel.classList.add("attention-panel");
  attentionPanel.body.classList.add("manager-attention-list");
  shownAlerts.forEach((entry) => attentionPanel.body.append(attentionItem(entry)));
  if (!alerts.length) {
    attentionPanel.body.append(el("div", "manager-clear", "No overdue projects, unassigned boards or low-stock parts."));
  }
  const projectsPanel = panel("Open projects", `${activeProjects.length} active`, smallBtn("View all", "", null, () => switchView("projects")));
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
  const boardCounts = BOARD_STAGES.map(([id, label]) => ({
    id,
    label,
    count: state.boards.filter((board) => board.currentStage?.id === id).length,
  }));
  const boardsPanel = panel("Production stages", `${state.boards.length} total`, smallBtn("Open boards", "", null, () => switchView("boards")));
  const stageChart = el("div", "stage-chart");
  const donut = el("div", "stage-donut");
  const donutTotal = el("div", "stage-donut-total");
  donutTotal.append(el("strong", null, String(state.boards.length)), el("span", null, "Total"));
  donut.append(donutTotal);
  const stageColors = ["var(--primary)", "var(--secondary)", "var(--positive)", "var(--warning)", "var(--negative)", "#8b78d7", "var(--ink-3)"];
  const countedBoards = boardCounts.reduce((sum, stage) => sum + stage.count, 0);
  let stageOffset = 0;
  const segments = [];
  boardCounts.forEach(({ count }, index) => {
    if (!countedBoards || !count) return;
    const start = stageOffset;
    stageOffset += (count / countedBoards) * 100;
    segments.push(`${stageColors[index]} ${start.toFixed(2)}% ${stageOffset.toFixed(2)}%`);
  });
  donut.style.background = segments.length ? `conic-gradient(${segments.join(", ")})` : "var(--wash-3)";

  const legend = el("div", "stage-legend");
  boardCounts.forEach(({ label, count }, index) => {
    const row = el("div", "stage-legend-row");
    const dot = el("i");
    dot.style.background = stageColors[index];
    const copy = el("span");
    const percentage = countedBoards ? Math.round((count / countedBoards) * 100) : 0;
    copy.append(el("strong", null, label), el("small", null, `${count} (${percentage}%)`));
    row.append(dot, copy);
    legend.append(row);
  });
  stageChart.append(donut, legend);
  boardsPanel.body.append(stageChart);
  dashboardTopGrid.append(projectsPanel, boardsPanel, attentionPanel);
  dashboardWorkGrid.append(productionPanel, dashboardSideStack);

  if (canSeeCosts() && state.costSummary) {
    const costs = panel("Financial snapshot", "Private to managers");
    const financials = el("div", "financial-summary");
    financials.append(
      statTile("var(--primary)", "Stock value", money(state.costSummary.stockValueMinor), "current shelf value"),
      statTile("var(--secondary)", "Board parts", money(state.costSummary.boardCostMinor), "consumed on boards"),
    );
    costs.body.append(financials);
    dashboardSideStack.append(costs);
  }

  const activity = panel("Recent activity", state.movements.length ? `${state.movements.length} recent events` : "");
  activity.body.classList.add("flush");
  if (!state.movements.length) {
    activity.body.append(el("div", "manager-clear compact", "No warehouse activity yet."));
  } else {
    const feed = el("div", "rows");
    state.movements.slice(0, 5).forEach((movement) => feed.append(movementRow(movement)));
    activity.body.append(feed);
  }
  dashboardSideStack.append(activity);
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
      main.append(el("div", "row-title", partTitle(s.part)));
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
    const row = el("button", "row click project-row");
    row.type = "button";
    row.append(chipIcon("folder", project.colorHex || "var(--primary)"));
    const main = el("div", "row-main");
    main.append(el("div", "row-title", project.name));
    main.append(el("div", "row-sub", [project.customer, project.site, `${linked.length} board${linked.length === 1 ? "" : "s"}`].filter(Boolean).join(" · ")));
    row.append(main);
    if (project.dueDate) row.append(el("div", "row-sub", `Due ${new Date(project.dueDate).toLocaleString()}`));
    row.append(statusBadge(linked.length && completed === linked.length ? "Completed" : project.status));
    row.addEventListener("click", () => openProjectOverview(project.name));
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

  const isFinished = (board) => board.status === "Completed";
  const boardTypes = [...new Set(state.boards.map((board) => board.type).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (boardArchiveFilters.type !== "All" && !boardTypes.includes(boardArchiveFilters.type)) {
    boardArchiveFilters.type = "All";
  }

  const typeFiltered = state.boards.filter((board) =>
    boardArchiveFilters.type === "All" || board.type === boardArchiveFilters.type);
  const searchableText = (board) => [
    board.number, board.group, board.name, board.project, board.customer,
    board.type, board.subtype, board.assignedName, board.mainBreakerType,
    board.mainBreakerModel, board.mainBreakerAmpere, ...(board.componentTypes || []),
  ].filter(Boolean).join(" ").toLocaleLowerCase();
  const query = boardArchiveFilters.query.trim().toLocaleLowerCase();
  const visibleBoards = typeFiltered.filter((board) => {
    const statusMatches = boardArchiveFilters.status === "All"
      || (boardArchiveFilters.status === "Finished" ? isFinished(board) : !isFinished(board));
    return statusMatches && (!query || searchableText(board).includes(query));
  });

  const controls = el("section", "board-archive-controls");
  const searchWrap = el("label", "board-archive-search");
  searchWrap.append(icon("search", 17));
  const search = el("input");
  search.type = "search";
  search.placeholder = "Search boards, type, ampere, project…";
  search.value = boardArchiveFilters.query;
  search.setAttribute("aria-label", "Search boards");
  search.addEventListener("input", () => {
    boardArchiveFilters.query = search.value;
    renderBoards();
    const nextSearch = $("#view-boards .board-archive-search input");
    if (nextSearch) {
      nextSearch.focus();
      nextSearch.setSelectionRange(boardArchiveFilters.query.length, boardArchiveFilters.query.length);
    }
  });
  searchWrap.append(search);

  const typeWrap = el("label", "board-type-filter");
  typeWrap.append(icon("sliders", 16));
  const typeSelect = el("select");
  typeSelect.setAttribute("aria-label", "Board type");
  ["All", ...boardTypes].forEach((type) => {
    const option = el("option", null, type === "All" ? "All board types" : type);
    option.value = type;
    option.selected = type === boardArchiveFilters.type;
    typeSelect.append(option);
  });
  typeSelect.addEventListener("change", () => {
    boardArchiveFilters.type = typeSelect.value;
    renderBoards();
  });
  typeWrap.append(typeSelect);
  controls.append(searchWrap, typeWrap);

  if (boardArchiveFilters.query || boardArchiveFilters.type !== "All" || boardArchiveFilters.status !== "All") {
    controls.append(smallBtn("Clear filters", "", "x", () => {
      boardArchiveFilters.query = "";
      boardArchiveFilters.type = "All";
      boardArchiveFilters.status = "All";
      renderBoards();
    }));
  }
  view.append(controls);

  const activeCount = typeFiltered.filter((board) => !isFinished(board)).length;
  const finishedCount = typeFiltered.filter(isFinished).length;
  const metrics = el("div", "board-archive-metrics");
  [
    ["In Progress", activeCount, "pulse"],
    ["Finished", finishedCount, "check"],
    ["All", typeFiltered.length, "board"],
  ].forEach(([label, count, iconName]) => {
    const metric = el("button", `board-archive-metric${boardArchiveFilters.status === label ? " active" : ""}`);
    metric.type = "button";
    metric.append(chipIcon(iconName, label === "Finished" ? "var(--positive)" : "var(--secondary)"));
    const copy = el("span");
    copy.append(el("small", null, label === "All" ? "Boards" : label), el("strong", null, String(count)));
    metric.append(copy);
    metric.addEventListener("click", () => {
      boardArchiveFilters.status = label;
      renderBoards();
    });
    metrics.append(metric);
  });
  view.append(metrics);

  const statusFilters = el("div", "board-status-filters");
  statusFilters.append(el("span", null, "Status"));
  ["All", "In Progress", "Finished"].forEach((status) => {
    const count = status === "All" ? typeFiltered.length
      : status === "Finished" ? finishedCount : activeCount;
    const button = el("button", boardArchiveFilters.status === status ? "active" : "");
    button.type = "button";
    button.append(document.createTextNode(status), el("span", null, String(count)));
    button.addEventListener("click", () => {
      boardArchiveFilters.status = status;
      renderBoards();
    });
    statusFilters.append(button);
  });
  view.append(statusFilters);

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
    progress.append(track, el("strong", null, `${b.completion || 0}% · ${b.currentStage?.label || "Design"}`));
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

  if (!visibleBoards.length) {
    view.append(emptyState("board", !state.boards.length
      ? (isAdmin() ? "No boards yet. Create one and assign it to whoever builds it." : "No boards yet.")
      : query || boardArchiveFilters.type !== "All"
        ? "No boards match this search and filter combination."
        : "No boards are in this production stage."));
    return;
  }

  const dueTime = (board) => board.dueDate ? new Date(board.dueDate).getTime() : Number.POSITIVE_INFINITY;
  const activeSort = (left, right) => dueTime(left) - dueTime(right)
    || (right.completion || 0) - (left.completion || 0)
    || (left.name || "").localeCompare(right.name || "", undefined, { numeric: true });
  const finishedSort = (left, right) => (right.number || "").localeCompare(left.number || "", undefined, { numeric: true })
    || (left.name || "").localeCompare(right.name || "", undefined, { numeric: true });
  /* Boards are numbered per job — 3918.26-1, 3918.26-2 and so on — so the
     number up to its last dash is the job the board belongs to. Sectioning on
     that puts one job's boards together under their own gray rule instead of
     scattering them through whatever `group` happened to be typed. A board
     with no number falls back to its group rather than being stranded. */
  const groupFor = (board) => {
    const number = String(board.number || "").trim();
    if (!number) return board.group || "Ungrouped";
    const cut = number.lastIndexOf("-");
    return cut > 0 ? number.slice(0, cut) : number;
  };
  const grouped = (boards) => {
    const groups = new Map();
    boards.forEach((board) => {
      const group = groupFor(board);
      if (!groups.has(group)) groups.set(group, []);
      groups.get(group).push(board);
    });
    return [...groups.entries()].sort(([left], [right]) => {
      if (left === "Ungrouped") return 1;
      if (right === "Ungrouped") return -1;
      return right.localeCompare(left, undefined, { numeric: true });
    });
  };
  const appendStage = (title, boards, finished) => {
    if (!boards.length) return;
    const stage = el("section", "board-archive-stage");
    const stageHead = el("div", `board-stage-divider ${finished ? "finished" : "active"}`);
    stageHead.append(el("i"), el("h3", null, title), el("span", null, String(boards.length)));
    stage.append(stageHead);
    grouped(boards).forEach(([group, groupBoards]) => {
      const section = el("div", "board-number-section");
      const heading = el("div", "board-number-heading");
      heading.append(el("span"), el("h4", null, group), el("small", null, `${groupBoards.length} board${groupBoards.length === 1 ? "" : "s"}`), el("span"));
      const list = el("div", "list board-archive-list");
      groupBoards.sort(finished ? finishedSort : activeSort)
        .forEach((board) => list.append(boardRow(board, board.assignedTo === state.me.id)));
      section.append(heading, list);
      stage.append(section);
    });
    view.append(stage);
  };

  appendStage("In Progress", visibleBoards.filter((board) => !isFinished(board)), false);
  appendStage("Finished", visibleBoards.filter(isFinished), true);
}

/* Deleting a board cannot be undone from the interface, so the confirmation
   names what goes and makes the reader type the board number to arm it. A
   plain OK button is too easy to hit from the same place Assign and Reassign
   sit, and those are recoverable. */
function openDeleteBoardModal(board) {
  openModal((modal, close) => {
    modal.append(el("h3", null, "Delete this board"));
    modal.append(el("div", "modal-sub", `${board.name} · ${board.number}`));

    const counts = [
      (board.components || []).length && `${(board.components || []).length} component line(s)`,
      (board.attachments || []).length && `${(board.attachments || []).length} file(s)`,
    ].filter(Boolean);
    modal.append(el("p", "hint",
      counts.length
        ? `This removes the board and its ${counts.join(" and ")}. Stock already booked out against it stays as it is — those movements happened.`
        : "This removes the board. Stock already booked out against it stays as it is — those movements happened."));

    const confirm = field("Type the board number to confirm", board.number || "board number");
    modal.append(confirm.label);
    const error = el("div", "form-error hidden");
    error.setAttribute("role", "alert");
    modal.append(error);

    modal.append(modalActions(close, "Delete board", async () => {
      if (confirm.input.value.trim() !== String(board.number || "").trim()) {
        error.textContent = "The board number does not match.";
        error.classList.remove("hidden");
        return;
      }
      try {
        await api("/api/board-delete", { boardID: board.id });
        state.boards = state.boards.filter((item) => item.id !== board.id);
        selectedBoardID = null;
        close();
        switchView("boards");
        await refresh();
      } catch (caught) {
        error.textContent = caught.message || "Could not delete this board.";
        error.classList.remove("hidden");
      }
    }));
  });
}

function openBoardDetail(boardID) {
  selectedBoardID = boardID;
  selectedBoardCabinet = 0;
  selectedBoardTab = "overview";
  switchView("board-detail");
}

function boardStatusNote(board) {
  if (board.status === "Completed") return "QA approved this board. Production is complete.";
  if (board.status === "QA Ready") return board.qaAssignedName
    ? `Production is finished and ${board.qaAssignedName} can now perform QA.`
    : "Production is finished. Assign a QA reviewer before sign-off.";
  if (board.status === "QA Changes") return board.qaNote
    ? `QA returned this board to Finishing: ${board.qaNote}`
    : "QA returned this board to Finishing for corrections.";
  if (board.currentStage?.id !== "design") return board.assignedName
    ? `Work is underway with ${board.assignedName}. Click a stage to keep the team in sync.`
    : "Production has started; assign a builder so ownership is clear.";
  if (board.assignedName) return `Assigned to ${board.assignedName}. Click Mechanical Build when work begins.`;
  return "This board remains in Design until a manager or assigned builder moves it forward.";
}

function renderStageTracker(board) {
  const tracker = el("div", "board-stage-tracker");
  tracker.setAttribute("role", "list");
  tracker.setAttribute("aria-label", `Current stage: ${board.currentStage?.label || "Design"}`);
  const canChange = isAdmin() || board.assignedTo === state.me.id;
  (board.stages || []).forEach((stage, index) => {
    const item = el("button", `board-stage stage-${stage.state}`);
    item.type = "button";
    item.setAttribute("role", "listitem");
    if (["current", "ready", "attention"].includes(stage.state)) item.setAttribute("aria-current", "step");
    item.disabled = !canChange || stage.id === "complete" || boardChecklistSyncing;
    item.title = stage.id === "complete"
      ? "Complete is unlocked by QA approval"
      : canChange ? `Move board to ${stage.label}` : "Assign this board to yourself to change its stage";
    const marker = el("span", "stage-marker", stage.state === "done" ? "✓" : String(index + 1));
    const copy = el("span", "stage-copy");
    copy.append(el("strong", null, stage.label));
    if (stage.id === "complete") copy.append(el("small", null, "QA approval"));
    else if (stage.id !== board.currentStage?.id) copy.append(el("small", null, "Set stage"));
    item.append(marker, copy);
    if (!item.disabled && stage.id !== board.currentStage?.id) {
      item.addEventListener("click", () => updateBoardStage(board, stage.id));
    }
    tracker.append(item);
  });
  return tracker;
}

/* Moving a board along a stage.

   Three things were wrong here. The stage being moved to was never sent, so
   the server saw `stageID` undefined, failed its own validation and returned
   "Unknown board stage" on every click. The syncing flag was raised before the
   request, which disabled every stage button and swapped the header for a
   spinner. And the finally block called refresh(), which refetches all state
   and re-renders the nav, dashboard, stock and every other view to reflect one
   changed field on one board.

   The click is now optimistic: the board moves at once, the request follows,
   and only the board detail redraws. The previous stage is kept so a failed
   request can put it back rather than leaving the screen lying. */
async function updateBoardStage(board, stageID) {
  const previous = { productionStage: board.productionStage, status: board.status,
                     stages: board.stages, currentStage: board.currentStage,
                     completion: board.completion };
  board.productionStage = stageID;
  boardChecklistAnimation = { boardID: board.id };
  renderBoardDetail();
  try {
    const result = await api("/api/board-stage", { boardID: board.id, stageID });
    Object.assign(board, result.board);
    // Keep the shared copy in step so the dashboard and the boards list agree
    // without paying for a full state reload.
    const shared = state.boards.find((item) => item.id === board.id);
    if (shared && shared !== board) Object.assign(shared, result.board);
    renderBoardDetail();
    renderBoards();
    renderDashboard();
  } catch (error) {
    Object.assign(board, previous);
    renderBoardDetail();
    window.alert(error.message);
  }
}

function boardProperty(iconName, label, value, onClick) {
  const card = el(onClick ? "button" : "div", `board-property${onClick ? " clickable" : ""}`);
  if (onClick) {
    card.type = "button";
    card.setAttribute("aria-label", `${label}: ${value || "Not set"}. Open details`);
    card.addEventListener("click", onClick);
  }
  card.append(chipIcon(iconName, "var(--primary)"));
  const copy = el("div");
  copy.append(el("span", null, label), el("strong", null, value || "Not set"));
  card.append(copy);
  if (onClick) card.append(icon("chevron", 15));
  return card;
}

function openComponentSourceCard(board, component, isDraft = false) {
  openModal((modal, close) => {
    modal.classList.add("wide", "component-source-modal");
    const displayName = isDraft
      ? component.description || [component.manufacturer, component.model].filter(Boolean).join(" ") || "Extracted component"
      : [component.manufacturer, component.model].filter(Boolean).join(" ") || "Board component";
    const sourceLabel = component.source === "ai" ? "Electrical scheme · AI extraction" : "Added manually";
    const member = (state.members || []).find((person) => person.id === component.addedBy);

    const hero = el("div", "component-source-hero");
    hero.append(partChip({ ...component, id: component.partID }));
    const heroCopy = el("div");
    heroCopy.append(el("span", "eyebrow", isDraft ? "Needs catalog match" : "Board component"), el("h3", null, displayName));
    heroCopy.append(el("p", null, [component.type, component.rating, component.poles, component.curve, component.sensitivity].filter(Boolean).join(" · ") || "No additional specification"));
    hero.append(heroCopy, el("strong", "component-source-qty", `× ${component.quantity || 1}`));
    modal.append(hero);

    const facts = el("div", "component-source-facts");
    [
      ["Source", sourceLabel],
      ["Drawing page", component.sourcePage ? `Page ${component.sourcePage}` : "Not recorded"],
      ["Board reference", component.reference || board.number || "Not recorded"],
      ["Board", [board.number, board.name].filter(Boolean).join(" · ") || "Current board"],
      ["Catalog name", [component.manufacturer, component.model].filter(Boolean).join(" ") || "Not matched"],
      ["Added by", member?.name || (component.source === "ai" ? "Scheme import" : "Not recorded")],
    ].forEach(([label, value]) => {
      const fact = el("div");
      fact.append(el("span", null, label), el("strong", null, value));
      facts.append(fact);
    });
    modal.append(facts);

    const sourceCard = el("section", "component-origin-card");
    sourceCard.append(chipIcon(component.source === "ai" ? "scan" : "note", component.source === "ai" ? "var(--primary)" : "var(--secondary)"));
    const sourceCopy = el("div");
    sourceCopy.append(el("span", "eyebrow", "Original source"), el("h4", null, component.source === "ai" ? "Text read from the drawing" : "Manual board entry"));
    sourceCopy.append(el("p", null, component.rawText || (component.source === "ai"
      ? "The scheme import did not preserve the original line text."
      : "This component was selected directly from the catalog.")));
    sourceCard.append(sourceCopy);
    modal.append(sourceCard);

    if (component.sourcePage && (board.attachments || []).some((file) => file.kind === "scheme")) {
      modal.append(el("p", "component-source-note", `Open the board’s Schemes & photos tab and check page ${component.sourcePage} of the attached drawing.`));
    }
    const actions = el("div", "actions");
    const done = el("button", "btn-primary", "Done");
    done.type = "button";
    done.addEventListener("click", close);
    actions.append(done);
    modal.append(actions);
  });
}

async function openAddBoardComponentModal(board, draft = null) {
  if (!catalog) catalog = (await api("/api/catalog")).parts;
  openModal((modal, close) => {
    modal.classList.add("wide");
    modal.append(el("h3", null, draft ? "Match extracted component" : "Add board component"));
    modal.append(el("p", "modal-sub", draft
      ? "Choose the catalog item that matches the line read from the electrical scheme."
      : "Choose the exact model, amp rating, poles, and curve used on this board."));
    const search = field("Find component", "Search model, manufacturer, amp, curve…");
    const choiceLabel = el("label", null, "Component");
    const choice = el("select");
    choiceLabel.append(choice);
    const quantity = field("Quantity", "1", "number");
    quantity.input.min = "1";
    quantity.input.max = "9999";
    quantity.input.value = String(draft?.quantity || 1);
    const reference = field("Board reference", "e.g. QF1 or incoming breaker");
    reference.input.value = draft?.reference || "";
    search.input.value = draft
      ? [draft.manufacturer, draft.model, draft.description, draft.type].filter(Boolean).join(" ")
      : "";
    const drawChoices = () => {
      const query = search.input.value.trim().toLowerCase();
      const matches = catalog.filter((part) => !query || [part.manufacturer, part.model, part.type,
        part.rating, part.poles, part.curve].filter(Boolean).join(" ").toLowerCase().includes(query)).slice(0, 200);
      choice.replaceChildren(new Option(matches.length ? "Select a component" : "No matching components", ""));
      matches.forEach((part) => {
        const details = [part.type, part.rating, part.poles, part.curve].filter(Boolean).join(" · ");
        choice.append(new Option(`${part.manufacturer} ${part.model} — ${details}`, part.id));
      });
    };
    drawChoices();
    search.input.addEventListener("input", drawChoices);
    const grid = el("div", "creation-grid");
    grid.append(search.label, choiceLabel, quantity.label, reference.label);
    modal.append(grid);
    const error = el("div", "form-error hidden");
    modal.append(error);
    modal.append(modalActions(close, "Add component", async () => {
      try {
        if (!choice.value) throw new Error("Choose a component first.");
        await api("/api/board-components", {
          boardID: board.id,
          action: "add",
          partID: choice.value,
          quantity: quantity.input.value,
          reference: reference.input.value,
          draftID: draft?.id,
        });
        close();
        await refresh();
      } catch (caught) {
        error.textContent = caught.message;
        error.classList.remove("hidden");
      }
    }));
  });
}

async function removeBoardComponent(board, componentID) {
  if (!window.confirm("Remove this component from the board?")) return;
  await api("/api/board-components", { boardID: board.id, action: "remove", componentID });
  await refresh();
}

async function removeBoardComponentDraft(board, draftID) {
  if (!window.confirm("Remove this extracted line from the board?")) return;
  await api("/api/board-components", { boardID: board.id, action: "removeDraft", draftID });
  await refresh();
}

async function issueBoardStock(board) {
  await api("/api/board-components", { boardID: board.id, action: "issueStock" });
  await refresh();
}

function componentStockBadge(stock) {
  const status = stock?.status || "unavailable";
  const badge = el("div", `component-stock-status ${status}`);
  const labels = {
    issued: `Issued ${stock?.issued || 0}/${stock?.required || 0}`,
    available: `${stock?.available || 0} available`,
    short: `${stock?.issued || 0}/${stock?.required || 0} issued · ${stock?.remaining || 0} short`,
    unavailable: `${stock?.remaining || stock?.required || 0} unavailable`,
  };
  badge.append(icon(status === "issued" || status === "available" ? "check" : status === "short" ? "alert" : "x", 14));
  badge.append(el("span", null, labels[status] || labels.unavailable));
  return badge;
}

function uploadBoardAttachment(board, kind) {
  const input = el("input");
  input.type = "file";
  input.accept = kind === "scheme" ? "application/pdf,image/jpeg,image/png,image/webp,image/heic" : "image/*";
  input.addEventListener("change", () => {
    const file = input.files?.[0];
    if (!file) return;
    if (file.size > 6_000_000) {
      window.alert("Files must be 6 MB or smaller.");
      return;
    }
    const reader = new FileReader();
    reader.addEventListener("load", async () => {
      boardChecklistSyncing = true;
      renderBoardDetail();
      try {
        const encoded = String(reader.result).split(",")[1] || "";
        await api("/api/board-attachment", {
          boardID: board.id,
          kind,
          fileName: file.name,
          mimeType: file.type || (kind === "scheme" ? "application/pdf" : "image/jpeg"),
          data: encoded,
        });
      } catch (error) {
        window.alert(error.message);
      } finally {
        boardChecklistSyncing = false;
        await refresh();
      }
    });
    reader.readAsDataURL(file);
  });
  input.click();
}

async function removeBoardAttachment(board, attachmentID) {
  if (!window.confirm("Remove this file from the board?")) return;
  await api("/api/board-attachment-delete", { boardID: board.id, attachmentID });
  await refresh();
}

function boardAttachmentSection(board, kind, title, description) {
  const section = el("section", "panel board-files-panel");
  const head = el("div", "panel-head");
  const copy = el("div");
  copy.append(el("span", "eyebrow", kind === "scheme" ? "Technical file" : "Build record"),
    el("h3", null, title), el("p", null, description));
  const canEdit = isAdmin() || board.assignedTo === state.me.id;
  head.append(copy);
  if (canEdit) head.append(smallBtn(kind === "scheme" ? "Add scheme" : "Add photos", "accent", "plus",
    () => uploadBoardAttachment(board, kind)));
  section.append(head);
  const files = (board.attachments || []).filter((file) => file.kind === kind);
  if (!files.length) {
    const empty = el("button", "board-file-drop");
    empty.type = "button";
    empty.disabled = !canEdit;
    empty.append(chipIcon(kind === "scheme" ? "note" : "board", "var(--primary)"),
      el("strong", null, kind === "scheme" ? "Upload the electrical scheme" : "Add board photos"),
      el("span", null, kind === "scheme" ? "PDF or image · up to 6 MB" : "JPG, PNG, WebP or HEIC · up to 6 MB"));
    if (canEdit) empty.addEventListener("click", () => uploadBoardAttachment(board, kind));
    section.append(empty);
    return section;
  }
  const grid = el("div", "board-file-grid");
  files.forEach((file) => {
    const card = el("article", "board-file-card");
    const link = el("a", "board-file-preview");
    link.href = `/api/board-attachment?id=${encodeURIComponent(file.id)}`;
    link.target = "_blank";
    link.rel = "noopener";
    if (file.mimeType.startsWith("image/")) {
      const img = el("img");
      img.src = link.href;
      img.alt = file.name;
      img.loading = "lazy";
      link.append(img);
    } else {
      link.append(chipIcon("note", "var(--primary)"), el("span", null, "PDF scheme"));
    }
    const meta = el("div", "board-file-meta");
    meta.append(el("strong", null, file.name), el("span", null, `${Math.max(1, Math.round(file.size / 1024))} KB`));
    card.append(link, meta);
    if (canEdit) card.append(smallBtn("Remove", "ghost", "x", () => removeBoardAttachment(board, file.id)));
    grid.append(card);
  });
  section.append(grid);
  return section;
}

function boardDrilldownRow(board, close) {
  const row = el("button", "board-drilldown-row");
  row.type = "button";
  row.append(chipIcon("board", board.status === "Completed" ? "var(--positive)" : "var(--secondary)"));
  const copy = el("span");
  copy.append(
    el("strong", null, [board.number, board.name].filter(Boolean).join(" — ")),
    el("small", null, [board.project !== "No Project" ? board.project : null, board.currentStage?.label || board.status, `${board.completion || 0}%`].filter(Boolean).join(" · ")),
  );
  row.append(copy, statusBadge(board.status), icon("chevron", 15));
  row.addEventListener("click", () => {
    close();
    openBoardDetail(board.id);
  });
  return row;
}

function drilldownMetric(label, value, color = "var(--primary)") {
  const metric = el("div", "drilldown-metric");
  metric.style.setProperty("--metric-color", color);
  metric.append(el("strong", null, String(value)), el("span", null, label));
  return metric;
}

function openCustomerOverview(customer) {
  const boards = state.boards.filter((board) => board.customer === customer);
  const projects = state.projects.filter((project) => project.customer === customer);
  const completed = boards.filter((board) => board.status === "Completed").length;
  openModal((modal, close) => {
    modal.classList.add("wide", "board-drilldown-modal");
    modal.append(el("span", "eyebrow", "Customer overview"), el("h3", null, customer || "No customer"));
    modal.append(el("p", "modal-sub", `${projects.length} project${projects.length === 1 ? "" : "s"} · ${boards.length} board${boards.length === 1 ? "" : "s"}`));
    const metrics = el("div", "drilldown-metrics");
    metrics.append(
      drilldownMetric("Projects", projects.length),
      drilldownMetric("Active boards", boards.length - completed, "var(--secondary)"),
      drilldownMetric("Finished", completed, "var(--positive)"),
    );
    modal.append(metrics);
    if (projects.length) {
      modal.append(el("div", "section-label", "Projects"));
      const projectList = el("div", "drilldown-tags");
      projects.forEach((project) => projectList.append(el("span", null, project.name)));
      modal.append(projectList);
    }
    modal.append(el("div", "section-label", "Boards"));
    const list = el("div", "board-drilldown-list");
    boards.sort((a, b) => (b.number || "").localeCompare(a.number || "", undefined, { numeric: true }))
      .forEach((board) => list.append(boardDrilldownRow(board, close)));
    modal.append(boards.length ? list : emptyState("board", "No boards are linked to this customer."));
  });
}

function openProjectOverview(projectName) {
  const project = state.projects.find((item) => item.name === projectName);
  const boards = state.boards.filter((board) => board.project === projectName);
  const completed = boards.filter((board) => board.status === "Completed").length;
  const average = boards.length
    ? Math.round(boards.reduce((sum, board) => sum + (board.completion || 0), 0) / boards.length)
    : 0;
  openModal((modal, close) => {
    modal.classList.add("wide", "board-drilldown-modal");
    modal.append(el("span", "eyebrow", "Project overview"), el("h3", null, projectName || "No project"));
    modal.append(el("p", "modal-sub", [
      project?.customer,
      project?.site,
      project?.dueDate ? `Due ${new Date(project.dueDate).toLocaleString()}` : null,
    ].filter(Boolean).join(" · ") || "Boards connected to this project."));
    const metrics = el("div", "drilldown-metrics four");
    metrics.append(
      drilldownMetric("Boards", boards.length),
      drilldownMetric("In progress", boards.length - completed, "var(--secondary)"),
      drilldownMetric("Finished", completed, "var(--positive)"),
      drilldownMetric("Avg. completion", `${average}%`, "var(--warning)"),
    );
    modal.append(metrics, el("div", "section-label", "Project boards"));
    const list = el("div", "board-drilldown-list");
    boards.sort((a, b) => (b.number || "").localeCompare(a.number || "", undefined, { numeric: true }))
      .forEach((board) => list.append(boardDrilldownRow(board, close)));
    modal.append(boards.length ? list : emptyState("board", "No boards are linked to this project yet."));
  });
}

function openBreakerOverview(sourceBoard) {
  const breakerLabel = [sourceBoard.mainBreakerType, sourceBoard.mainBreakerModel, sourceBoard.mainBreakerAmpere].filter(Boolean).join(" · ");
  const matching = state.boards.filter((board) =>
    board.mainBreakerType === sourceBoard.mainBreakerType
      && board.mainBreakerModel === sourceBoard.mainBreakerModel
      && board.mainBreakerAmpere === sourceBoard.mainBreakerAmpere);
  openModal((modal, close) => {
    modal.classList.add("wide", "board-drilldown-modal");
    modal.append(el("span", "eyebrow", "Main breaker"), el("h3", null, sourceBoard.mainBreakerModel || sourceBoard.mainBreakerType || "Not specified"));
    modal.append(el("p", "modal-sub", breakerLabel || "No main-breaker details recorded."));
    const specs = el("dl", "spec drilldown-spec");
    [["Type", sourceBoard.mainBreakerType], ["Model", sourceBoard.mainBreakerModel], ["Ampere", sourceBoard.mainBreakerAmpere]]
      .forEach(([label, value]) => specs.append(el("dt", null, label), el("dd", null, value || "Not set")));
    modal.append(specs, el("div", "section-label", `Used on ${matching.length} board${matching.length === 1 ? "" : "s"}`));
    const list = el("div", "board-drilldown-list");
    matching.forEach((board) => list.append(boardDrilldownRow(board, close)));
    modal.append(list);
  });
}

function openWorkerOverview(workerID, workerName) {
  const member = (state.members || []).find((item) => item.id === workerID)
    || (state.members || []).find((item) => item.name === workerName);
  const boards = state.boards.filter((board) => workerID ? board.assignedTo === workerID : board.assignedName === workerName);
  const completed = boards.filter((board) => board.status === "Completed").length;
  const active = boards.length - completed;
  const average = boards.length
    ? Math.round(boards.reduce((sum, board) => sum + (board.completion || 0), 0) / boards.length)
    : 0;
  openModal((modal, close) => {
    modal.classList.add("wide", "board-drilldown-modal");
    const identity = el("div", "worker-drilldown-identity");
    const initials = (workerName || "?").split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
    identity.append(el("div", "worker-drilldown-avatar", initials || "?"));
    const copy = el("div");
    copy.append(el("span", "eyebrow", "Worker lifetime"), el("h3", null, workerName || "Unassigned"));
    const joined = member?.createdAt ? `Joined ${new Date(member.createdAt).toLocaleDateString()}` : "Board production history";
    copy.append(el("p", null, [member ? roleLabel(member.role) : null, joined].filter(Boolean).join(" · ")));
    identity.append(copy);
    modal.append(identity);
    const metrics = el("div", "drilldown-metrics four");
    metrics.append(
      drilldownMetric("Boards made", completed, "var(--positive)"),
      drilldownMetric("Active", active, "var(--secondary)"),
      drilldownMetric("Lifetime boards", boards.length),
      drilldownMetric("Avg. completion", `${average}%`, "var(--warning)"),
    );
    modal.append(metrics, el("div", "section-label", "Board history"));
    const list = el("div", "board-drilldown-list");
    boards.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0))
      .forEach((board) => list.append(boardDrilldownRow(board, close)));
    modal.append(boards.length ? list : emptyState("board", "No boards are assigned to this worker yet."));
  });
}

function compareBoardComponents(left, right) {
  const manufacturerOrder = String(left?.manufacturer || "").localeCompare(
    String(right?.manufacturer || ""), undefined, { sensitivity: "base", numeric: true },
  );
  if (manufacturerOrder) return manufacturerOrder;

  const leftModel = String(left?.model || left?.description || "");
  const rightModel = String(right?.model || right?.description || "");
  const modelOrder = leftModel.localeCompare(rightModel, undefined, { sensitivity: "base", numeric: true });
  if (modelOrder) return modelOrder;

  const leftAmpere = ampereValue(left?.rating) ?? -1;
  const rightAmpere = ampereValue(right?.rating) ?? -1;
  if (leftAmpere !== rightAmpere) return rightAmpere - leftAmpere;

  return [left?.poles, left?.curve, left?.reference].filter(Boolean).join("|").localeCompare(
    [right?.poles, right?.curve, right?.reference].filter(Boolean).join("|"),
    undefined, { sensitivity: "base", numeric: true },
  );
}

const COMPONENT_SECTION_ORDER = [
  "MCBs", "RCBOs & RCDs", "MCCBs & ACBs", "Surge & Arc Protection",
  "Switching & Isolation", "Fuses & Fusegear", "Contactors", "Drives & Soft Starters",
  "Motor Protection & Starters", "Control Power & UPS", "Control & Automation", "Relays",
  "Metering & Monitoring", "Power Factor & Quality", "Terminals & Wiring", "Busbars & Earthing",
  "Door & Operator Devices", "Enclosure & Climate", "Spacers & Supports",
];

function componentSectionName(component) {
  if (component?.groupName) return component.groupName;
  const type = String(component?.type || component?.description || "").trim();
  if (/spacer|standoff|stand[ -]?off|mounting support/i.test(type)) return "Spacers & Supports";
  if (/\bMCCB\b|\bACB\b/i.test(type)) return "MCCBs & ACBs";
  if (/\bMCB\b/i.test(type)) return "MCBs";
  if (/RCBO|RCCB|\bRCD\b/i.test(type)) return "RCBOs & RCDs";
  if (/contactor/i.test(type)) return "Contactors";
  if (/terminal|ferrule|wire|cable|DIN rail|trunking/i.test(type)) return "Terminals & Wiring";
  if (/busbar|copper bar|earth|neutral bar/i.test(type)) return "Busbars & Earthing";
  if (/relay/i.test(type)) return "Relays";
  if (/fuse/i.test(type)) return "Fuses & Fusegear";
  if (/switch|isolator/i.test(type)) return "Switching & Isolation";
  return type || "Other components";
}

function groupedBoardComponents(components) {
  const groups = new Map();
  [...(components || [])].sort(compareBoardComponents).forEach((component) => {
    const section = componentSectionName(component);
    if (!groups.has(section)) groups.set(section, []);
    groups.get(section).push(component);
  });
  const order = (name) => {
    const index = COMPONENT_SECTION_ORDER.indexOf(name);
    return index < 0 ? COMPONENT_SECTION_ORDER.length : index;
  };
  return [...groups.entries()].sort(([left], [right]) =>
    order(left) - order(right) || left.localeCompare(right, undefined, { sensitivity: "base", numeric: true }));
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
  const progressAnimation = boardChecklistAnimation?.boardID === board.id ? boardChecklistAnimation : null;

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
  if (state.me.can?.signOffQA && board.completion >= 100 && board.qaStatus !== "approved") {
    actions.append(smallBtn("Review QA", "accent", null, () => openQAModal(board)));
  }
  if (isAdmin()) actions.append(smallBtn(board.assignedTo ? "Reassign" : "Assign board", "accent", null, () => openAssignModal(board)));
  if (isAdmin()) actions.append(smallBtn("Delete board", "danger", null, () => openDeleteBoardModal(board)));
  top.append(identity, actions);
  view.append(top);

  if (!["overview", "components", "files"].includes(selectedBoardTab)) selectedBoardTab = "overview";
  const componentCount = (board.components || []).length + (board.componentDrafts || []).length;
  const fileCount = (board.attachments || []).length;
  const tabs = el("div", "board-detail-tabs");
  tabs.setAttribute("role", "tablist");
  tabs.setAttribute("aria-label", "Board details");
  const addTab = (tabID, label, count) => {
    const button = el("button", selectedBoardTab === tabID ? "active" : "");
    button.type = "button";
    button.setAttribute("role", "tab");
    button.setAttribute("aria-selected", String(selectedBoardTab === tabID));
    button.append(document.createTextNode(label));
    if (count != null) button.append(el("span", null, String(count)));
    button.addEventListener("click", () => {
      selectedBoardTab = tabID;
      renderBoardDetail();
    });
    tabs.append(button);
  };
  addTab("overview", "Overview");
  addTab("components", "Components", componentCount);
  addTab("files", "Schemes & photos", fileCount);
  view.append(tabs);

  const progressCard = el("section", "board-progress-card");
  const progressHead = el("div", "board-progress-head");
  const progressTitle = el("div");
  progressTitle.append(el("span", "eyebrow", "Production workflow"), el("h3", null, board.currentStage?.label || board.status));
  progressHead.append(progressTitle, el("p", null, boardStatusNote(board)));
  const tracker = renderStageTracker(board);
  if (progressAnimation) tracker.classList.add("changing");
  progressCard.append(progressHead, tracker);
  if (selectedBoardTab === "overview") view.append(progressCard);

  const properties = el("div", "board-property-grid");
  const outDate = board.dateOut ? new Date(board.dateOut).toLocaleDateString() : "Not set";
  const dueDate = board.dueDate ? new Date(board.dueDate).toLocaleDateString() : "No due date";
  properties.append(
    boardProperty("folder", "Project", board.project === "No Project" ? "No project" : board.project,
      board.project && board.project !== "No Project" ? () => openProjectOverview(board.project) : null),
    boardProperty("team", "Builder", board.assignedName || "Unassigned", board.assignedName
      ? () => openWorkerOverview(board.assignedTo, board.assignedName) : null),
    boardProperty("shield", "QA reviewer", board.qaAssignedName || "Unassigned", board.qaAssignedName
      ? () => openWorkerOverview(board.qaAssignedTo, board.qaAssignedName) : null),
    boardProperty("cabinet", "Build", `${board.cabinetCount} cabinet${String(board.cabinetCount) === "1" ? "" : "s"} · ${board.buildFormat}`),
    boardProperty("boltShield", "Main breaker", [board.mainBreakerType, board.mainBreakerModel, board.mainBreakerAmpere].filter(Boolean).join(" · "),
      () => openBreakerOverview(board)),
    boardProperty("hash", "Customer", board.customer, () => openCustomerOverview(board.customer)),
    boardProperty("note", "Schedule", `Out ${outDate} · Due ${dueDate}`),
  );
  if (selectedBoardTab === "overview") view.append(properties);

  const work = el("div", "board-detail-grid");
  const componentsPanel = el("section", "panel board-components-panel");
  const componentHead = el("div", "panel-head");
  const componentCopy = el("div");
  componentCopy.append(el("span", "eyebrow", "Board specification"), el("h3", null, "Components"),
    el("p", null, "The exact parts fitted to this board, shared with the phone app."));
  componentHead.append(componentCopy);
  const canEditBoard = isAdmin() || board.assignedTo === state.me.id;
  if (canEditBoard) componentHead.append(smallBtn("Add component", "accent", "plus", () => openAddBoardComponentModal(board)));
  if (isAdmin() && (board.components || []).some((component) => (component.stock?.available || 0) > 0)) {
    componentHead.append(smallBtn("Issue available stock", "", "arrowOut", () => issueBoardStock(board)));
  }
  componentsPanel.append(componentHead);
  const componentList = el("div", "board-component-groups");
  groupedBoardComponents(board.components).forEach(([sectionName, sectionComponents]) => {
    const section = el("section", "component-type-section");
    const sectionHead = el("div", "component-type-head");
    const totalQuantity = sectionComponents.reduce((sum, component) => sum + (Number(component.quantity) || 0), 0);
    sectionHead.append(el("h4", null, sectionName), el("span", null, `${sectionComponents.length} line${sectionComponents.length === 1 ? "" : "s"} · ${totalQuantity} item${totalQuantity === 1 ? "" : "s"}`));
    const rows = el("div", "board-component-list");
    sectionComponents.forEach((component) => {
      const row = el("div", "board-component-row clickable");
      row.tabIndex = 0;
      row.setAttribute("role", "button");
      row.setAttribute("aria-label", `View source details for ${component.manufacturer} ${component.model}`);
      const identity = el("div", "board-component-identity");
      identity.append(partChip({ ...component, id: component.partID }), el("div"));
      const text = identity.lastElementChild;
      text.append(el("strong", null, `${component.manufacturer} ${component.model}`),
        el("span", null, [component.type, component.rating, component.poles, component.curve, component.reference,
          component.source === "ai" ? "AI scan" : null,
          component.sourcePage ? `Page ${component.sourcePage}` : null]
          .filter(Boolean).join(" · ")));
      row.append(identity, componentStockBadge(component.stock), el("strong", "component-quantity", `× ${component.quantity}`));
      row.append(icon("chevron", 15));
      row.addEventListener("click", () => openComponentSourceCard(board, component));
      row.addEventListener("keydown", (event) => {
        if (event.target === row && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); openComponentSourceCard(board, component); }
      });
      if (canEditBoard) row.append(smallBtn("Remove", "ghost", "x", (event) => {
        event.stopPropagation();
        removeBoardComponent(board, component.id);
      }));
      rows.append(row);
    });
    section.append(sectionHead, rows);
    componentList.append(section);
  });
  if (!(board.components || []).length) {
    const legacy = (board.componentTypes || []).filter(Boolean);
    if (legacy.length) {
      const chips = el("div", "board-component-chips");
      legacy.forEach((type) => chips.append(el("span", null, type)));
      componentList.append(chips, el("p", "board-permission-note", "Add exact models and quantities as the specification is confirmed."));
    } else {
      componentList.append(emptyState("box", (board.componentDrafts || []).length
        ? "No catalog-matched components yet. Review the extracted lines below."
        : "No components have been added to this board yet."));
    }
  }
  componentsPanel.append(componentList);
  if ((board.componentDrafts || []).length) {
    const reviewHead = el("div", "component-review-head");
    const reviewCopy = el("div");
    reviewCopy.append(el("span", "eyebrow", "AI extraction"), el("h4", null, "Needs review"),
      el("p", null, "These scheme lines were saved, but did not match the catalog exactly."));
    reviewHead.append(reviewCopy, el("span", "component-review-count", String(board.componentDrafts.length)));
    const reviewList = el("div", "board-component-list component-review-list");
    [...board.componentDrafts].sort(compareBoardComponents).forEach((draft) => {
      const row = el("div", "board-component-row component-draft-row clickable");
      row.tabIndex = 0;
      row.setAttribute("role", "button");
      const draftIdentity = el("div", "board-component-identity");
      draftIdentity.append(chipIcon("scan", "var(--warning)"), el("div"));
      const text = draftIdentity.lastElementChild;
      text.append(el("strong", null, draft.description || [draft.manufacturer, draft.model].filter(Boolean).join(" ") || "Extracted component"),
        el("span", null, [draft.type, draft.rating, draft.poles, draft.curve, draft.reference,
          draft.sourcePage ? `Page ${draft.sourcePage}` : null].filter(Boolean).join(" · ")));
      row.append(draftIdentity, el("strong", "component-quantity", `× ${draft.quantity || 1}`));
      row.append(icon("chevron", 15));
      row.addEventListener("click", () => openComponentSourceCard(board, draft, true));
      row.addEventListener("keydown", (event) => {
        if (event.target === row && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); openComponentSourceCard(board, draft, true); }
      });
      if (canEditBoard) {
        const rowActions = el("div", "component-draft-actions");
        rowActions.append(
          smallBtn("Match", "accent", null, (event) => { event.stopPropagation(); openAddBoardComponentModal(board, draft); }),
          smallBtn("Remove", "ghost", "x", (event) => { event.stopPropagation(); removeBoardComponentDraft(board, draft.id); }),
        );
        row.append(rowActions);
      }
      reviewList.append(row);
    });
    componentsPanel.append(reviewHead, reviewList);
  }
  if (selectedBoardTab === "components") work.append(componentsPanel);

  const linkedPanel = el("section", "panel board-linked-panel");
  const linkedHead = el("div", "panel-head");
  linkedHead.append(el("h3", null, "Linked production data"));
  linkedPanel.append(linkedHead);
  const linkedList = el("div", "board-linked-list");
  linkedList.append(boardProperty("box", "Stock issues", (board.costItems || []).length
    ? `${(board.costItems || []).length} part type${(board.costItems || []).length === 1 ? "" : "s"}`
    : "No stock issued yet"));
  if (canSeeCosts()) linkedList.append(boardProperty("pulse", "Parts cost", money(board.costMinor || 0)));
  linkedList.append(boardProperty("folder", "Customer / project", [board.customer, board.project !== "No Project" ? board.project : null].filter(Boolean).join(" · "),
    board.project && board.project !== "No Project"
      ? () => openProjectOverview(board.project)
      : board.customer ? () => openCustomerOverview(board.customer) : null));
  linkedPanel.append(linkedList);
  if ((board.costItems || []).length) {
    const parts = el("div", "linked-parts");
    (board.costItems || []).slice(0, 8).forEach((item) => {
      parts.append(el("div", null, `${item.partName} × ${item.quantity}`));
    });
    linkedPanel.append(parts);
  }
  if (selectedBoardTab === "overview") work.append(linkedPanel);
  if (work.childElementCount === 1) work.classList.add("single");
  if (work.childElementCount) view.append(work);

  const files = el("div", "board-file-sections");
  files.append(
    boardAttachmentSection(board, "scheme", "Schemes", "Keep the latest electrical drawing with the board."),
    boardAttachmentSection(board, "photo", "Photos", "Document the build, wiring, labels, and finished board."),
  );
  if (selectedBoardTab === "files") view.append(files);

  if (progressAnimation) boardChecklistAnimation = null;
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
  text.append(el("div", "part-head-title", partTitle(part)));
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

/* ---- how far up the ampere list a part can actually go ----

   AMPERE_RATINGS runs to 6300A because a busbar or an ACB can. An S201 stops
   at 63A, and offering 6300A on it invites a stock line that no such device
   exists for. The ceiling comes from the part's own rating, which already
   states a range or a top figure for most of the catalog: "0.5-63A" gives 63,
   "16-3150A" gives 3150, "IEC 250A frame" gives 250. A part still carrying the
   "Set A" placeholder has nothing to read, so it keeps the full list rather
   than being capped at a guess. */
function ampereValue(text) {
  const match = String(text || "").match(/([\d.]+)\s*A\b/gi);
  if (!match) return null;
  const numbers = match.map((piece) => parseFloat(piece));
  return numbers.length ? Math.max(...numbers) : null;
}

/** The ampere options worth offering for a part, largest allowed value last. */
function ampereOptionsFor(part) {
  const ceiling = ampereValue(part && part.rating);
  if (!ceiling) return [...AMPERE_RATINGS];
  const allowed = AMPERE_RATINGS.filter((value) => ampereValue(value) <= ceiling);
  // The ceiling itself is rarely one of the standard steps — an AF09 tops out
  // at 9A and an OT at 3150A, neither of which the list carries. Truncating to
  // the step below would refuse the very rating the part is sold at, so the
  // ceiling is offered in its own right when the list has no room for it.
  if (!allowed.some((value) => ampereValue(value) === ceiling)) {
    allowed.push(`${ceiling}A`);
  }
  return allowed.length ? allowed : [...AMPERE_RATINGS];
}

/* A stocked S201 at 6A and one at 16A are different things on the shelf and
   the same words on screen, because the title is only ever the brand and the
   model. Where a part carries one exact ampere figure — which is what choosing
   a stock variant produces — it belongs in the title next to the model. A
   catalog family whose rating is a range or a placeholder is left alone: a
   heading of "S201 0.5-63A" tells a reader nothing they want. */
function partTitle(part) {
  if (!part) return "";
  const name = `${part.manufacturer} ${part.model}`.trim();
  const rating = String(part.rating || "").trim();
  const exact = /^[\d.]+\s*A$/i.test(rating);
  return exact ? `${name} · ${rating}` : name;
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
    const ratingValues = ampereOptionsFor(template);
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
          main.append(el("div", "row-title", partTitle(p)));
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

/* The same catalog the iPhone apps browse: the eighteen categories come from
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

// ------------------------------------------------ companies, customers & manufacturers

function archiveSearch(placeholder, onInput) {
  const wrap = el("label", "archive-search");
  wrap.append(icon("search", 17));
  const input = el("input");
  input.type = "search";
  input.placeholder = placeholder;
  input.addEventListener("input", () => onInput(input.value));
  wrap.append(input);
  return wrap;
}

function renderContacts() {
  const view = $("#view-contacts");
  view.replaceChildren();
  view.append(viewHead("Companies & Customers"));

  const customers = [...new Set(state.projects.map((project) => project.customer?.trim()).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
  const intro = el("div", "archive-intro");
  intro.append(
    chipIcon("building", "var(--primary)"),
    el("div", null),
    el("span", "archive-total", String(customers.length)),
  );
  intro.children[1].append(
    el("h3", null, "Customer archive"),
    el("p", null, "Companies and customers connected to your projects and boards."),
  );
  view.append(intro);

  const grid = el("div", "archive-card-grid");
  const draw = (value = "") => {
    grid.replaceChildren();
    const query = value.trim().toLowerCase();
    const visible = customers.filter((name) => !query || name.toLowerCase().includes(query));
    visible.forEach((name) => {
      const projects = state.projects.filter((project) => project.customer?.localeCompare(name, undefined, { sensitivity: "accent" }) === 0);
      const boards = state.boards.filter((board) => board.customer?.localeCompare(name, undefined, { sensitivity: "accent" }) === 0);
      const sites = new Set(projects.map((project) => project.site).filter(Boolean));
      const card = el("button", "archive-card");
      card.type = "button";
      card.append(chipIcon("building", projects[0]?.colorHex || "var(--primary)"));
      const copy = el("span", "archive-card-copy");
      copy.append(
        el("strong", null, name),
        el("small", null, `${projects.length} project${projects.length === 1 ? "" : "s"} · ${boards.length} board${boards.length === 1 ? "" : "s"}${sites.size ? ` · ${sites.size} site${sites.size === 1 ? "" : "s"}` : ""}`),
      );
      card.append(copy, icon("chevron", 16));
      card.addEventListener("click", () => switchView("projects"));
      grid.append(card);
    });
    if (!visible.length) grid.append(emptyState("search", customers.length ? "No companies or customers match that search." : "Customers appear here when projects are created."));
  };
  view.append(archiveSearch("Search companies and customers", draw), grid);
  draw();
}

async function renderManufacturers() {
  const view = $("#view-manufacturers");
  if (!catalog) {
    view.replaceChildren(viewHead("Manufacturers"), emptyState("tag", "Loading manufacturers…"));
    catalog = (await api("/api/catalog")).parts;
  }
  view.replaceChildren();
  view.append(viewHead("Manufacturers"));

  const names = [...new Set([
    ...BOARD_MANUFACTURERS,
    ...(catalog || []).map((part) => part.manufacturer).filter(Boolean),
  ])].sort((a, b) => (a === "Generic" ? -1 : b === "Generic" ? 1 : a.localeCompare(b)));
  const intro = el("div", "archive-intro");
  intro.append(chipIcon("tag", "var(--secondary)"), el("div", null), el("span", "archive-total", String(names.length)));
  intro.children[1].append(
    el("h3", null, "Manufacturer library"),
    el("p", null, "Brands used by boards and components, following the phone app archive."),
  );
  view.append(intro);

  const grid = el("div", "manufacturer-grid");
  const draw = (value = "") => {
    grid.replaceChildren();
    const query = value.trim().toLowerCase();
    const visible = names.filter((name) => !query || name.toLowerCase().includes(query));
    visible.forEach((name) => {
      const parts = (catalog || []).filter((part) => part.manufacturer?.localeCompare(name, undefined, { sensitivity: "accent" }) === 0);
      const boards = state.boards.filter((board) => board.manufacturer?.localeCompare(name, undefined, { sensitivity: "accent" }) === 0);
      const card = el("article", "manufacturer-card");
      const logoURL = manufacturerImage(name);
      const logo = el("div", "manufacturer-logo");
      if (logoURL) {
        const image = el("img");
        image.src = logoURL;
        image.alt = "";
        logo.append(image);
      } else {
        logo.append(el("strong", null, name.slice(0, 2).toUpperCase()));
      }
      const copy = el("div", "manufacturer-copy");
      copy.append(el("h3", null, name), el("p", null, `${parts.length} catalog item${parts.length === 1 ? "" : "s"} · ${boards.length} board${boards.length === 1 ? "" : "s"}`));
      card.append(logo, copy, el("span", "manufacturer-status", parts.length || boards.length ? "In use" : "Available"));
      grid.append(card);
    });
    if (!visible.length) grid.append(emptyState("search", "No manufacturers match that search."));
  };
  view.append(archiveSearch("Search manufacturers", draw), grid);
  draw();
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

    // The brand's own mark leads when there is one — a reader recognises the
    // logo faster than the category glyph, and the type is spelled out in the
    // line below and again in the specification. The type icon stays as the
    // fallback for the brands with no logo yet.
    const head = el("div", "part-title-row");
    const logoURL = brandLogoURL(part.manufacturer);
    if (logoURL) {
      const tile = el("div", "brand-tile");
      tile.style.setProperty("--glow", brandLogoGlow(part.manufacturer));
      const img = el("img");
      img.src = logoURL;
      img.alt = part.manufacturer;
      // A manifest entry with no file behind it must not leave a gap where the
      // mark should be: fall back to the glyph the app would have shown.
      img.addEventListener("error", () => {
        const fallback = el("div", "type-tile");
        fallback.append(icon(iconForType(part.type), 28));
        tile.replaceWith(fallback);
      });
      tile.append(img);
      head.append(tile);
    } else {
      const tile = el("div", "type-tile");
      tile.append(icon(iconForType(part.type), 28));
      head.append(tile);
    }
    const text = el("div", "part-title-text");
    text.append(el("div", "part-title", part.model));
    const brand = el("div", "part-brand");
    brand.append(icon("tag", 13), el("span", null, part.manufacturer));
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

function memberSelect(selected, predicate = () => true, emptyLabel = "Unassigned") {
  const select = el("select");
  select.append(new Option(emptyLabel, ""));
  (state.members || [])
    .filter((m) => m.active && predicate(m))
    .forEach((m) => select.append(new Option(`${m.name} (${m.role})`, m.id, false, m.id === selected)));
  return select;
}

const BOARD_CREATION_TYPES = [
  { id: "main-lv", name: "Main LV Board", icon: "boltShield", note: "Main low-voltage intake" },
  { id: "mdb", name: "MDB", icon: "boltShield", note: "Main Distribution" },
  { id: "sub-distribution", name: "Sub Distribution", icon: "board", note: "Sub boards" },
  { id: "mcc", name: "MCC", icon: "motor", note: "Motor Control Center" },
  { id: "cabinet-collection", name: "Cabinet Collection", icon: "board", note: "Multi-cabinet assembly" },
  { id: "ats", name: "ATS", icon: "toggle", note: "Automatic Transfer Switch" },
  { id: "metering", name: "Metering Board", icon: "gauge", note: "Meters and CTs" },
  { id: "capacitor", name: "Capacitor Bank", icon: "pulse", note: "Power factor correction" },
  { id: "control", name: "Control Board", icon: "toggle", note: "Controls and automation" },
  { id: "lighting", name: "Lighting", icon: "bolt", note: "Lighting boards" },
  { id: "power", name: "Power", icon: "plug", note: "Power boards" },
  { id: "apartment", name: "Apartment", icon: "board", note: "Residential boards" },
  { id: "generator", name: "Generator Board", icon: "gauge", note: "Generator distribution" },
  { id: "ups", name: "UPS Board", icon: "shield", note: "Critical power" },
  { id: "pv", name: "PV Solar", icon: "pulse", note: "Solar AC/DC board" },
  { id: "ev", name: "EV Charging", icon: "terminal", note: "Charging infrastructure" },
  { id: "temporary-site", name: "Site Temporary", icon: "alert", note: "Construction site power" },
  { id: "fire-pump", name: "Fire Pump", icon: "alert", note: "Life-safety motor board" },
  { id: "hvac", name: "HVAC", icon: "motor", note: "Mechanical services" },
  { id: "elv-bms", name: "ELV / BMS", icon: "terminal", note: "Low-current systems" },
  { id: "pcc", name: "PCC", icon: "boltShield", note: "Power control center" },
  { id: "synchronizing", name: "Synchronizing", icon: "toggle", note: "Generator sync board" },
  { id: "bypass", name: "Bypass Board", icon: "toggle", note: "Maintenance bypass" },
  { id: "transformer", name: "Transformer Board", icon: "boltShield", note: "Transformer feeder" },
  { id: "pump", name: "Pump Board", icon: "motor", note: "Water and process pumps" },
  { id: "elevator", name: "Elevator", icon: "motor", note: "Lift supply board" },
  { id: "outdoor-lighting", name: "Outdoor Lighting", icon: "bolt", note: "Street and facade lighting" },
  { id: "pdu", name: "PDU", icon: "terminal", note: "Data center distribution" },
  { id: "harmonic-filter", name: "Harmonic Filter", icon: "pulse", note: "Power quality" },
  { id: "fire-alarm", name: "Fire Alarm", icon: "alert", note: "Life-safety controls" },
  { id: "earthing", name: "Earthing", icon: "plug", note: "Grounding and bonding" },
];

const DEFAULT_BOARD_SUBTYPE = "No subtype";
const GENERAL_BOARD_SUBTYPES = [DEFAULT_BOARD_SUBTYPE, "Control", "EV Charger", "Metering", "Automation", "Pump Control", "HVAC Control", "Generator Control", "Solar", "UPS", "Temporary Site"];

function boardSubtypeOptions(boardType) {
  const lower = String(boardType || "").toLowerCase();
  if (lower.includes("ev") || lower.includes("charging")) {
    return [DEFAULT_BOARD_SUBTYPE, "EV Charger", "Load Management", "Parking Level", "Fast Charger", "Metering"];
  }
  if (lower.includes("mcc") || lower.includes("motor") || lower.includes("pump") || lower.includes("hvac")) {
    return [DEFAULT_BOARD_SUBTYPE, "Control", "Pump Control", "HVAC Control", "VFD", "Soft Starter", "Automation"];
  }
  if (lower.includes("lighting")) {
    return [DEFAULT_BOARD_SUBTYPE, "Indoor Lighting", "Outdoor Lighting", "Emergency Lighting", "Timer Control", "Astronomical Clock"];
  }
  if (lower.includes("ats") || lower.includes("generator")) {
    return [DEFAULT_BOARD_SUBTYPE, "Generator Control", "ATS Control", "Synchronization", "Bypass"];
  }
  return GENERAL_BOARD_SUBTYPES;
}

function openNewBoardModal() {
  boardCreationMode = null;
  boardCreationType = null;
  boardSchemeReading = null;
  boardSchemeUpload = null;
  switchView("board-create");
}

function creationSteps(activeStep, labels = ["Start", "Source / type", "Review & create"]) {
  const steps = el("div", "creation-steps");
  labels.forEach((label, index) => {
    const step = el("div", `${index + 1 === activeStep ? "active" : ""}${index + 1 < activeStep ? " done" : ""}`);
    step.append(el("span", null, index + 1 < activeStep ? "✓" : String(index + 1)), el("strong", null, label));
    steps.append(step);
  });
  return steps;
}

function creationStart(kind, onScan, onManual) {
  const wrap = el("div", "creation-start");
  const hero = el("div", "creation-hero creation-start-hero");
  hero.append(el("span", "eyebrow", `New ${kind.toLowerCase()}`));
  hero.append(el("h2", null, `How do you want to start this ${kind.toLowerCase()}?`));
  hero.append(el("p", null, kind === "Board"
    ? "Use the electrical scheme to prepare the draft automatically, or enter every detail yourself."
    : "Read a scheme to pull out the customer and project, or enter the project details yourself."));
  const choices = el("div", "creation-mode-grid");
  const choice = (iconName, eyebrow, title, note, accent, action) => {
    const button = el("button", `creation-mode-card${accent ? " recommended" : ""}`);
    button.type = "button";
    button.append(chipIcon(iconName, accent ? "var(--primary)" : "var(--secondary)"));
    const copy = el("div");
    copy.append(el("span", "eyebrow", eyebrow), el("h3", null, title), el("p", null, note));
    button.append(copy, icon("chevron", 19));
    button.addEventListener("click", action);
    return button;
  };
  choices.append(
    choice("scan", "Recommended", "Scan with AI", "Attach the AutoCAD PDF. PanelVault reads it and prepares a reviewable draft.", true, onScan),
    choice("note", "Manual", "Enter manually", `Start with a blank ${kind.toLowerCase()} form and fill in the details yourself.`, false, onManual),
  );
  wrap.append(hero, choices);
  return wrap;
}

function fileAsBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(String(reader.result).split(",")[1] || ""));
    reader.addEventListener("error", () => reject(new Error("Could not read this file.")));
    reader.readAsDataURL(file);
  });
}

function schemeIntakePanel(kind, onComplete) {
  const panel = el("section", "scheme-intake-panel");
  const head = el("div", "scheme-intake-head");
  head.append(chipIcon("scan", "var(--primary)"));
  const copy = el("div");
  copy.append(el("span", "eyebrow", "AI scheme reader"), el("h2", null, `Scan a scheme for this ${kind.toLowerCase()}`),
    el("p", null, "PDF, PNG, JPG, WebP or HEIC · up to 8 MB. Nothing is created until you review and confirm it."));
  head.append(copy);
  panel.append(head);

  const input = el("input");
  input.type = "file";
  input.accept = "application/pdf,image/jpeg,image/png,image/webp,image/heic";
  input.className = "hidden";
  const drop = el("button", "scheme-upload-zone");
  drop.type = "button";
  drop.append(icon("note", 28), el("strong", null, "Choose the AutoCAD scheme"), el("span", null, "PDF or supported image"));
  const status = el("div", "scheme-file-status", "No file selected");
  const error = el("div", "form-error hidden");
  const actions = el("div", "page-form-actions");
  const scan = el("button", "btn-primary", "Read scheme with AI");
  scan.type = "button";
  scan.disabled = true;
  let selectedFile = null;
  drop.addEventListener("click", () => input.click());
  input.addEventListener("change", () => {
    const file = input.files?.[0];
    error.classList.add("hidden");
    if (!file) return;
    if (file.size > 8_000_000) {
      error.textContent = "The scheme must be 8 MB or smaller.";
      error.classList.remove("hidden");
      input.value = "";
      selectedFile = null;
      scan.disabled = true;
      return;
    }
    selectedFile = file;
    status.textContent = `${file.name} · ${Math.max(1, Math.round(file.size / 1024)).toLocaleString()} KB`;
    drop.classList.add("selected");
    scan.disabled = false;
  });
  scan.addEventListener("click", async () => {
    if (!selectedFile) return;
    error.classList.add("hidden");
    scan.disabled = true;
    scan.textContent = "Reading drawing…";
    drop.classList.add("reading");
    try {
      const data = await fileAsBase64(selectedFile);
      const upload = {
        fileName: selectedFile.name,
        mimeType: selectedFile.type || "application/pdf",
        data,
        size: selectedFile.size,
      };
      const reading = await api("/api/ai/board-scheme", upload);
      await onComplete(reading, upload);
    } catch (caught) {
      error.textContent = caught.message || "PanelVault could not read this scheme.";
      error.classList.remove("hidden");
      scan.disabled = false;
      scan.textContent = "Read scheme with AI";
      drop.classList.remove("reading");
    }
  });
  actions.append(scan);
  panel.append(input, drop, status, error, actions);
  return panel;
}

function normalizedCreationBoardType(value) {
  const source = String(value || "").trim().toUpperCase();
  if (!source) return null;
  if (source.includes("SMDB") || source === "SDB" || source.includes("SUB DISTRIBUTION")) return "sub-distribution";
  if (source.includes("MAIN LV") || source.includes("MAIN LOW VOLTAGE") || source === "MLVB") return "main-lv";
  if (source.includes("MDB") || source.includes("MAIN DISTRIBUTION")) return "mdb";
  const aliases = [
    ["mcc", /\bMCC\b|MOTOR CONTROL/], ["ats", /\bATS\b|AUTOMATIC TRANSFER/],
    ["metering", /METERING|METER BOARD/], ["capacitor", /CAPACITOR|POWER FACTOR|\bPFC\b/],
    ["outdoor-lighting", /OUTDOOR|STREET|FACADE/], ["lighting", /LIGHTING/],
    ["apartment", /APARTMENT|RESIDENTIAL|DWELLING/], ["generator", /GENERATOR|\bGENSET\b/],
    ["ups", /\bUPS\b|UNINTERRUPTIBLE/], ["pv", /\bPV\b|SOLAR|PHOTOVOLTAIC/],
    ["ev", /\bEV\b|CHARGING/], ["temporary-site", /TEMPORARY|CONSTRUCTION SITE/],
    ["fire-pump", /FIRE PUMP/], ["fire-alarm", /FIRE ALARM/], ["hvac", /\bHVAC\b|AIR CONDITION/],
    ["elv-bms", /\bELV\b|\bBMS\b|LOW CURRENT/], ["pcc", /\bPCC\b|POWER CONTROL CENTER/],
    ["synchronizing", /SYNCHRON/], ["bypass", /BYPASS/], ["transformer", /TRANSFORMER/],
    ["pump", /PUMP/], ["elevator", /ELEVATOR|\bLIFT\b/], ["pdu", /\bPDU\b|POWER DISTRIBUTION UNIT/],
    ["harmonic-filter", /HARMONIC FILTER/], ["earthing", /EARTHING|GROUNDING/],
    ["cabinet-collection", /CABINET COLLECTION|MULTI.CABINET/], ["control", /CONTROL|AUTOMATION/],
    ["power", /POWER BOARD|POWER DISTRIBUTION|\bPDB\b/],
  ];
  const alias = aliases.find(([, pattern]) => pattern.test(source));
  if (alias) return alias[0];
  return BOARD_CREATION_TYPES.find((item) => source.includes(item.id.toUpperCase())
    || source.includes(item.name.toUpperCase()))?.id || null;
}

function boardTypeVerification(reading, selectedType) {
  const board = reading?.board || {};
  const suggestion = normalizedCreationBoardType(board.type);
  const wrap = el("div", "board-type-verification");
  const copy = el("div", "board-type-verification-copy");
  const confidence = String(board.typeConfidence || "low").toLowerCase();
  copy.append(
    el("span", `ai-confidence ${confidence}`, `AI suggestion · ${confidence} confidence`),
    el("strong", null, suggestion ? `Verify ${selectedType.name}` : "Choose the correct board type"),
    el("p", null, board.typeEvidence || `Gemini classified the drawing as “${board.type || selectedType.name}”. Confirm or change it before creation.`),
  );
  const fieldWrap = el("label", "board-type-verification-field", "Board type");
  const select = el("select");
  BOARD_CREATION_TYPES.forEach((type) => select.append(new Option(type.name, type.id, false, type.id === selectedType.id)));
  select.addEventListener("change", () => {
    boardCreationType = select.value;
    renderBoardCreate();
    window.scrollTo({ top: 0, behavior: "smooth" });
  });
  fieldWrap.append(select, el("small", null, "You can override the AI guess."));
  wrap.append(copy, fieldWrap);
  return wrap;
}

function schemeReviewCard(reading, context) {
  const review = el("section", "scheme-review-card");
  const board = reading?.board || {};
  const head = el("div", "scheme-review-head");
  head.append(chipIcon("check", "var(--positive)"));
  const copy = el("div");
  copy.append(el("span", "eyebrow", "AI draft ready"), el("h3", null, `Review the ${context.toLowerCase()} draft`),
    el("p", null, "AI can make mistakes. Confirm every field against the drawing before creating anything."));
  head.append(copy);
  review.append(head);
  const facts = el("div", "scheme-review-facts");
  [
    ["Board", [board.number, board.name].filter(Boolean).join(" — ")],
    ["AI board type", [board.type, board.typeConfidence ? `${board.typeConfidence} confidence` : ""].filter(Boolean).join(" · ")],
    ["Project", board.project],
    ["Customer", board.customer],
    ["Main breaker", [board.mainBreakerType, board.mainBreakerModel, board.mainBreakerAmpere].filter(Boolean).join(" · ")],
    ["Supply", [board.supplyVoltage, board.frequency, board.earthingSystem].filter(Boolean).join(" · ")],
    ["Enclosure", [board.ipRating, board.formSeparation, board.enclosureSize].filter(Boolean).join(" · ")],
    ["Matched parts", String((reading.components || []).length)],
    ["Needs review", String((reading.unmatched || []).length)],
  ].forEach(([label, value]) => {
    if (!value) return;
    const fact = el("div");
    fact.append(el("span", null, label), el("strong", null, value));
    facts.append(fact);
  });
  review.append(facts);
  if (board.notes) review.append(el("p", "scheme-review-note", board.notes));
  if (reading.warnings?.length) {
    review.append(el("p", "scheme-review-note", `Check the drawing: ${reading.warnings.join(" · ")}`));
  }
  return review;
}

function pageField(control) {
  control.label.classList.add("page-field");
  return control;
}

function renderBoardCreate() {
  const view = $("#view-board-create");
  if (!view || !isAdmin()) return;
  view.replaceChildren();

  const backLabel = boardCreationType ? "← Change board type" : boardCreationMode ? "← Start over" : "← Boards";
  const back = smallBtn(backLabel, "", null, () => {
    if (boardCreationType) {
      boardCreationType = null;
      renderBoardCreate();
    } else if (boardCreationMode) {
      boardCreationMode = null;
      boardSchemeReading = null;
      boardSchemeUpload = null;
      renderBoardCreate();
    } else switchView("boards");
  });
  const activeStep = !boardCreationMode ? 1 : !boardCreationType ? 2 : 3;
  view.append(back, creationSteps(activeStep));

  if (!boardCreationMode) {
    view.append(creationStart("Board", () => {
      boardCreationMode = "ai";
      renderBoardCreate();
    }, () => {
      boardCreationMode = "manual";
      renderBoardCreate();
    }));
    return;
  }

  if (boardCreationMode === "ai" && !boardSchemeReading) {
    const hero = el("div", "creation-hero compact");
    hero.append(el("span", "eyebrow", "New production board"), el("h2", null, "Let the drawing start the board"),
      el("p", null, "PanelVault reads the title block and counts the components used across the schematic, then opens a draft for your review."));
    view.append(hero, schemeIntakePanel("Board", async (reading, upload) => {
      boardSchemeReading = reading;
      boardSchemeUpload = upload;
      boardCreationType = normalizedCreationBoardType(reading.board?.type);
      renderBoardCreate();
      window.scrollTo({ top: 0, behavior: "smooth" });
    }));
    return;
  }

  if (!boardCreationType) {
    const hero = el("div", "creation-hero");
    hero.append(el("span", "eyebrow", "New production board"));
    hero.append(el("h2", null, boardSchemeReading ? "Confirm the board type" : "What are you building?"));
    hero.append(el("p", null, boardSchemeReading
      ? "The drawing did not identify a supported type clearly. Choose it before reviewing the draft."
      : "Start with the board type. The next page only asks for details that matter to that build."));
    view.append(hero);
    if (boardSchemeReading) view.append(schemeReviewCard(boardSchemeReading, "Board"));
    const grid = el("div", "board-type-grid");
    BOARD_CREATION_TYPES.forEach((boardType) => {
      const button = el("button", "board-type-card");
      button.append(chipIcon(boardType.icon, "var(--primary)"));
      const copy = el("div");
      copy.append(el("span", "board-type-code", boardType.note), el("h3", null, boardType.name));
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
  heroCopy.append(el("span", "eyebrow", selectedType.note), el("h2", null, selectedType.name));
  heroType.append(heroCopy);
  detailsHero.append(heroType);
  if (boardSchemeReading) detailsHero.append(boardTypeVerification(boardSchemeReading, selectedType));
  view.append(detailsHero);
  if (boardSchemeReading) view.append(schemeReviewCard(boardSchemeReading, "Board"));

  const form = el("form", "board-create-form");
  const aiDraft = boardSchemeReading?.board || {};
  const number = pageField(field("Board number", "3918.24-1"));
  const group = pageField(field("Board group", "optional group"));
  const name = pageField(field("Board name", "Main LV Board"));
  const projects = ["No Project", ...state.projects.map((item) => item.name)];
  const project = pageField(selectField("Project", projects, "No Project"));
  const customer = pageField(field("Customer name", "search or type customer"));
  const company = pageField(field("Company you are doing it for", "optional company"));
  const subtype = pageField(selectField("Subtype", boardSubtypeOptions(selectedType.name), DEFAULT_BOARD_SUBTYPE));
  const manufacturer = pageField(selectField("Board manufacturer", BOARD_MANUFACTURERS, "Generic"));
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
  const qaAssign = el("label", "page-field", "QA reviewer");
  const qaAssignee = memberSelect(null, (member) => ["owner", "manager", "staff-manager", "qa"].includes(member.role), "Assign later");
  qaAssign.append(qaAssignee);

  if (boardSchemeReading) {
    number.input.value = aiDraft.number || "";
    name.input.value = aiDraft.name || "";
    customer.input.value = aiDraft.customer || "";
    const matchedProject = state.projects.find((item) =>
      item.name.toLowerCase() === String(aiDraft.project || "").trim().toLowerCase());
    project.select.value = matchedProject?.name || "No Project";
    if (matchedProject) {
      customer.input.value = matchedProject.customer;
      customer.input.disabled = true;
    }
    const availableManufacturers = [...manufacturer.select.options].map((option) => option.value);
    const manufacturerKey = (value) => String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
    const aiManufacturer = String(aiDraft.manufacturer || "").trim();
    const matchedManufacturer = availableManufacturers.find((value) =>
      manufacturerKey(value) === manufacturerKey(aiManufacturer));
    if (matchedManufacturer) {
      manufacturer.select.value = matchedManufacturer;
    } else if (aiManufacturer) {
      // Never erase a printed manufacturer merely because it is not in the
      // built-in picker yet. The server already accepts company-specific names.
      manufacturer.select.append(new Option(aiManufacturer, aiManufacturer, true, true));
    }
    cabinets.select.value = String(Math.max(1, Math.min(12, Number(aiDraft.cabinetCount) || 1)));
    const breakerTypes = [...mainBreakerType.select.options].map((option) => option.value);
    const matchedBreakerType = breakerTypes.find((value) =>
      value.toLowerCase() === String(aiDraft.mainBreakerType || "").trim().toLowerCase());
    if (matchedBreakerType) mainBreakerType.select.value = matchedBreakerType;
    mainBreakerModel.input.value = aiDraft.mainBreakerModel || "";
    mainBreakerAmpere.input.value = aiDraft.mainBreakerAmpere || "630A";
  }

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
    section("Schedule & ownership", "The builder completes production. QA is a separate approval stage.", dateOut, dueDate, assign, qaAssign),
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
        type: selectedType.name,
        subtype: subtype.select.value,
        manufacturer: manufacturer.select.value,
        cabinetCount: cabinets.select.value,
        buildFormat: buildFormat.select.value,
        dateOut: dateOut.input.value,
        dueDate: dueDate.input.value || null,
        mainBreakerType: mainBreakerType.select.value,
        mainBreakerModel: mainBreakerModel.input.value,
        mainBreakerAmpere: mainBreakerAmpere.input.value,
        assignedTo: assignee.value || null,
        qaAssignedTo: qaAssignee.value || null,
        components: boardSchemeReading?.components || [],
        componentDrafts: boardSchemeReading?.unmatched || [],
      });
      const followups = [];
      if (boardSchemeUpload && boardSchemeUpload.size <= 6_000_000) {
        followups.push(api("/api/board-attachment", {
          boardID: board.id,
          kind: "scheme",
          fileName: boardSchemeUpload.fileName,
          mimeType: boardSchemeUpload.mimeType,
          data: boardSchemeUpload.data,
        }));
      }
      if (followups.length) await Promise.allSettled(followups);
      const hasImportedComponents = Boolean(
        (boardSchemeReading?.components || []).length || (boardSchemeReading?.unmatched || []).length,
      );
      selectedBoardID = board.id;
      selectedBoardCabinet = 0;
      selectedBoardTab = hasImportedComponents ? "components" : "overview";
      boardCreationMode = null;
      boardCreationType = null;
      boardSchemeReading = null;
      boardSchemeUpload = null;
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
  projectCreationMode = null;
  projectSchemeReading = null;
  switchView("project-create");
}

function renderProjectCreate() {
  const view = $("#view-project-create");
  if (!view || !isAdmin()) return;
  view.replaceChildren();
  const back = smallBtn(projectCreationMode ? "← Start over" : "← Projects", "", null, () => {
    if (projectCreationMode) {
      projectCreationMode = null;
      projectSchemeReading = null;
      renderProjectCreate();
    } else switchView("projects");
  });
  const activeStep = !projectCreationMode ? 1
    : projectCreationMode === "ai" && !projectSchemeReading ? 2 : 3;
  view.append(back, creationSteps(activeStep, ["Start", "Project source", "Review & create"]));

  if (!projectCreationMode) {
    view.append(creationStart("Project", () => {
      projectCreationMode = "ai";
      renderProjectCreate();
    }, () => {
      projectCreationMode = "manual";
      renderProjectCreate();
    }));
    return;
  }

  if (projectCreationMode === "ai" && !projectSchemeReading) {
    const hero = el("div", "creation-hero compact");
    hero.append(el("span", "eyebrow", "New project"), el("h2", null, "Start the project from a drawing"),
      el("p", null, "PanelVault reads the project and customer from the scheme, then gives you a short form to confirm."));
    view.append(hero, schemeIntakePanel("Project", async (reading) => {
      projectSchemeReading = reading;
      renderProjectCreate();
      window.scrollTo({ top: 0, behavior: "smooth" });
    }));
    return;
  }

  const draft = projectSchemeReading?.board || {};
  const hero = el("div", "creation-hero compact");
  hero.append(el("span", "eyebrow", projectCreationMode === "ai" ? "AI-assisted project" : "Manual project"),
    el("h2", null, "Create the project workspace"),
    el("p", null, "Confirm the customer, site and schedule. Boards can be attached as soon as the project is created."));
  view.append(hero);
  if (projectSchemeReading) view.append(schemeReviewCard(projectSchemeReading, "Project"));

  const form = el("form", "board-create-form project-create-form");
  const name = pageField(field("Project name", "Azrieli Office Tower"));
  const customer = pageField(field("Customer", "search or type customer"));
  const site = pageField(field("Site or building", "optional location"));
  const dueDate = pageField(field("Expected finish", "optional", "datetime-local"));
  if (projectSchemeReading) {
    name.input.value = draft.project || draft.name || "";
    customer.input.value = draft.customer || "";
  }
  const section = el("section", "creation-section");
  const head = el("div", "creation-section-head");
  head.append(el("h3", null, "Project details"), el("p", null, "The shared container for its customer, boards, drawings and progress."));
  const grid = el("div", "page-form-grid project-form-grid");
  [name, customer, site, dueDate].forEach((control) => grid.append(control.label));
  section.append(head, grid);
  const error = el("div", "form-error hidden");
  const actions = el("div", "page-form-actions");
  const cancel = el("button", "btn-ghost", "Cancel");
  cancel.type = "button";
  cancel.addEventListener("click", () => switchView("projects"));
  const submit = el("button", "btn-primary", "Create project");
  submit.type = "submit";
  actions.append(cancel, submit);
  form.append(section, error, actions);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.classList.add("hidden");
    if (!name.input.value.trim() || !customer.input.value.trim()) {
      error.textContent = "Project name and customer are required.";
      error.classList.remove("hidden");
      return;
    }
    submit.disabled = true;
    submit.textContent = "Creating…";
    try {
      const { project } = await api("/api/projects", {
        name: name.input.value,
        customer: customer.input.value,
        site: site.input.value,
        dueDate: dueDate.input.value || null,
      });
      projectCreationMode = null;
      projectSchemeReading = null;
      await refresh();
      switchView("projects");
      openProjectOverview(project.name);
    } catch (caught) {
      error.textContent = caught.message || "Could not create this project.";
      error.classList.remove("hidden");
      submit.disabled = false;
      submit.textContent = "Create project";
    }
  });
  view.append(form);
}

function openAssignModal(board) {
  const returnView = currentView;
  openModal((modal, close) => {
    modal.append(el("h3", null, "Assign board"));
    modal.append(el("div", "modal-sub", [board.number, board.name].filter(Boolean).join(" — ")));
    const label = el("label", null, "Builder");
    const select = memberSelect(board.assignedTo);
    label.append(select);
    const qaLabel = el("label", null, "QA reviewer");
    const qaSelect = memberSelect(board.qaAssignedTo, (member) => ["owner", "manager", "staff-manager", "qa"].includes(member.role), "Assign later");
    qaLabel.append(qaSelect);
    modal.append(label, qaLabel);
    modal.append(modalActions(close, "Save", async () => {
      await api("/api/board-update", {
        boardID: board.id,
        assignedTo: select.value || null,
        qaAssignedTo: qaSelect.value || null,
      });
      close();
      await refresh();
      switchView(returnView === "board-detail" ? "board-detail" : "boards");
    }));
  });
}

function openQAModal(board) {
  const returnView = currentView;
  openModal((modal, close) => {
    modal.append(el("span", "eyebrow", "Quality assurance"), el("h3", null, `Review ${board.number}`));
    modal.append(el("div", "modal-sub", "Approval unlocks Complete. A correction request returns the board to Finishing."));
    const note = field("QA note", "What passed, or what needs correction");
    note.input.value = board.qaNote || "";
    const error = el("div", "form-error hidden");
    modal.append(note.label, error);
    const actions = el("div", "modal-actions qa-modal-actions");
    const cancel = el("button", "btn-ghost", "Cancel");
    cancel.type = "button";
    cancel.addEventListener("click", close);
    const changes = el("button", "btn-danger", "Request corrections");
    changes.type = "button";
    const approve = el("button", "btn-primary", "Approve QA");
    approve.type = "button";
    const submit = async (action, button) => {
      changes.disabled = true;
      approve.disabled = true;
      button.textContent = action === "approve" ? "Approving…" : "Sending…";
      try {
        await api("/api/board-qa", { boardID: board.id, action, note: note.input.value });
        close();
        await refresh();
        switchView(returnView === "board-detail" ? "board-detail" : "boards");
      } catch (caught) {
        error.textContent = caught.message || "QA could not be updated.";
        error.classList.remove("hidden");
        changes.disabled = false;
        approve.disabled = false;
        changes.textContent = "Request corrections";
        approve.textContent = "Approve QA";
      }
    };
    changes.addEventListener("click", () => submit("request_changes", changes));
    approve.addEventListener("click", () => submit("approve", approve));
    actions.append(cancel, changes, approve);
    modal.append(actions);
  });
}

// ---------------------------------------------------------------- start

boot();
