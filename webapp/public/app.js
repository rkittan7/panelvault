import { renderMovementChart } from "/chart.js";

// PanelVault Cloud frontend — vanilla JS, no build step.

let state = null; // last /api/state payload
let catalog = null; // lazy-loaded parts list
let currentView = "dashboard";

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

  // Invite links look like /#join/COMPANY/INVITE — preselect the join tab.
  const parts = location.hash.split("/");
  if (parts[0] === "#join" && parts.length >= 3) {
    switchAuthTab("join");
    const form = $("#form-join");
    form.companyCode.value = parts[1];
    form.inviteCode.value = parts[2];
  }
}

function switchAuthTab(tab) {
  document.querySelectorAll(".seg button").forEach((b) =>
    b.classList.toggle("active", b.dataset.tab === tab));
  ["login", "create", "join"].forEach((name) =>
    $(`#form-${name}`).classList.toggle("hidden", name !== tab));
  $("#auth-error").classList.add("hidden");
}

document.querySelectorAll(".seg button").forEach((b) =>
  b.addEventListener("click", () => switchAuthTab(b.dataset.tab)));

function wireAuthForm(id, endpoint) {
  $(id).addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target));
    try {
      await api(endpoint, data);
      location.hash = "";
      await boot();
    } catch (error) {
      const box = $("#auth-error");
      box.textContent = error.message;
      box.classList.remove("hidden");
    }
  });
}

wireAuthForm("#form-login", "/api/login");
wireAuthForm("#form-create", "/api/company");
wireAuthForm("#form-join", "/api/join");

$("#logout").addEventListener("click", async () => {
  await api("/api/logout", {});
  state = null;
  showAuth();
});

// ---------------------------------------------------------------- shell

const NAV_ITEMS = [
  { view: "dashboard", label: "Dashboard", icon: "grid" },
  { view: "stock", label: "Stock", icon: "box", count: () => state.stock.length },
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
    btn.classList.toggle("active", currentView === item.view);
    btn.addEventListener("click", () => switchView(item.view));
    nav.append(btn);
  });
}

function switchView(view) {
  currentView = view;
  document.querySelectorAll(".view").forEach((v) =>
    v.classList.toggle("hidden", v.id !== `view-${view}`));
  renderNav();
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
  renderBoards();
  if (isAdmin()) renderTeam();
}

async function boot() {
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
  view.append(viewHead("Dashboard"));

  const low = state.stock.filter((s) => s.minimumLevel != null && s.onHand <= s.minimumLevel);
  const units = state.stock.reduce((sum, s) => sum + s.onHand, 0);
  const open = state.boards.filter((b) => b.status !== "Completed").length;
  const movedIn = state.movements.filter((m) => m.kind !== "consume").length;

  const stats = el("div", "stats");
  stats.append(
    statTile("var(--primary)", "Parts", state.stock.length, "tracked in stock"),
    statTile("var(--secondary)", "Units", units.toLocaleString(), "total on hand"),
    statTile(low.length ? "var(--warning)" : "var(--positive)", "Low stock", low.length,
      low.length ? "need ordering" : "all levels ok"),
    statTile("var(--positive)", "Open boards", open, `${state.boards.length} total`),
  );
  view.append(stats);

  if (canSeeCosts() && state.costSummary) {
    const c = state.costSummary;
    const moneyStats = el("div", "stats");
    moneyStats.append(
      statTile("var(--primary)", "Stock value", money(c.stockValueMinor), "on the shelf"),
      statTile("var(--secondary)", "Board cost", money(c.boardCostMinor), "parts consumed"),
      statTile(
        c.unpricedParts ? "var(--warning)" : "var(--positive)",
        "Priced parts",
        `${c.pricedParts}/${c.pricedParts + c.unpricedParts}`,
        c.unpricedParts ? `${c.unpricedParts} need a price` : "all parts priced",
      ),
    );
    view.append(el("div", "money-head", "Costs \u00b7 visible to you only"), moneyStats);
  }

  const grid = el("div", "dash-grid");
  const left = el("div", "dash-col");
  const right = el("div", "dash-col");
  grid.append(left, right);
  view.append(grid);

  // --- movement chart
  const chartPanel = panel("Stock movement", "last 14 days");
  const legend = el("div", "chart-legend");
  legend.innerHTML =
    '<span><i style="background:var(--positive)"></i>In</span>' +
    '<span><i style="background:var(--secondary)"></i>Out</span>';
  chartPanel.querySelector(".panel-head").append(legend);
  const chartHost = el("div", "chart-wrap");
  chartPanel.body.append(chartHost);
  left.append(chartPanel);
  if (state.movements.length) {
    renderMovementChart(chartHost, state.movements);
  } else {
    chartHost.append(emptyState("pulse", "No movement yet. Receiving stock or using it on a board will chart here."));
  }

  // --- stock levels with meters
  const levelsPanel = panel("Stock levels", `${state.stock.length} parts`);
  levelsPanel.body.classList.add("flush");
  const rows = el("div", "rows");
  const top = [...state.stock].sort((a, b) => b.onHand - a.onHand).slice(0, 6);
  const peak = Math.max(1, ...top.map((s) => s.onHand));
  if (!top.length) {
    levelsPanel.body.append(emptyState("box", isAdmin()
      ? "No parts tracked yet. Add one from the Stock page."
      : "No parts tracked yet."));
  } else {
    top.forEach((s) => {
      const isLow = s.minimumLevel != null && s.onHand <= s.minimumLevel;
      const row = el("div", "row click");
      const main = el("div", "row-main");
      main.append(el("div", "row-title", `${s.part.manufacturer} ${s.part.model}`));
      const meter = el("div", "meter");
      const fill = el("i");
      fill.style.width = `${Math.max(3, (s.onHand / peak) * 100)}%`;
      fill.style.background = isLow ? "var(--warning)" : "var(--primary)";
      meter.append(fill);
      main.append(meter);
      const qty = el("div", "qty-col");
      qty.append(el("div", `num ${isLow ? "low" : "ok"}`, String(s.onHand)));
      row.append(main, qty);
      row.addEventListener("click", () => switchView("stock"));
      rows.append(row);
    });
    levelsPanel.body.append(rows);
  }
  left.append(levelsPanel);

  // --- right rail: activity
  const activity = panel("Recent activity", movedIn ? `${state.movements.length} events` : "");
  activity.body.classList.add("flush");
  if (!state.movements.length) {
    activity.body.append(emptyState("pulse", "Nothing has moved yet."));
  } else {
    const feed = el("div", "rows");
    state.movements.slice(0, 7).forEach((m) => feed.append(movementRow(m)));
    activity.body.append(feed);
  }
  right.append(activity);

  // --- right rail: boards snapshot
  const boardsPanel = panel("Boards", `${open} open`);
  boardsPanel.body.classList.add("flush");
  if (!state.boards.length) {
    boardsPanel.body.append(emptyState("board", isAdmin()
      ? "Create a board and assign it to whoever builds it."
      : "No boards assigned yet."));
  } else {
    const feed = el("div", "rows");
    state.boards.slice(0, 5).forEach((b) => {
      const row = el("div", "row click");
      const main = el("div", "row-main");
      main.append(el("div", "row-title", [b.number, b.name].filter(Boolean).join(" \u2014 ")));
      main.append(el("div", "row-sub", b.assignedName ? `assigned to ${b.assignedName}` : "unassigned"));
      row.append(main, statusBadge(b.status));
      row.addEventListener("click", () => switchView("boards"));
      feed.append(row);
    });
    boardsPanel.body.append(feed);
  }
  right.append(boardsPanel);
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
      !q || `${s.part.manufacturer} ${s.part.model} ${s.part.type} ${s.part.serialNumber || ""} ${s.location}`.toLowerCase().includes(q));
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
      row.append(chipIcon("box", colorForType(s.part.type)));
      const main = el("div", "row-main");
      main.append(el("div", "row-title", `${s.part.manufacturer} ${s.part.model}`));
      const bits = [s.part.type, s.part.rating, s.part.serialNumber && `Serial: ${s.part.serialNumber}`, s.location].filter(Boolean).join(" · ");
      main.append(el("div", "row-sub", bits));
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

// ---------------------------------------------------------------- boards

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
    const row = el("div", "row");
    row.append(chipIcon("board", isMine ? "var(--primary)" : "var(--secondary)"));
    const main = el("div", "row-main");
    const title = [b.number, b.name].filter(Boolean).join(" — ");
    main.append(el("div", "row-title", title));
    main.append(el("div", "row-sub",
      [b.customer, b.assignedName ? `assigned to ${b.assignedName}` : "unassigned"].filter(Boolean).join(" · ")));
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
    if (isAdmin() || isMine) {
      rowActions.append(smallBtn("Status", "", "chevron", async () => {
        const order = ["Design", "In Progress", "Completed"];
        const nextStatus = order[(order.indexOf(b.status) + 1) % order.length];
        await api("/api/board-update", { boardID: b.id, status: nextStatus });
        await refresh();
        switchView("boards");
      }));
    }
    if (isAdmin()) {
      rowActions.append(smallBtn("Assign", "", null, () => openAssignModal(b)));
    }
    if (rowActions.childElementCount) row.append(rowActions);
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

function openMovementModal(entry, kind) {
  openModal((modal, close) => {
    modal.append(el("h3", null, kind === "receive" ? "Stock in" : "Stock out"));
    modal.append(el("div", "modal-sub", `${entry.part.manufacturer} ${entry.part.model} · ${entry.onHand} on hand`));
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
    modal.append(el("div", "modal-sub", `${entry.part.manufacturer} ${entry.part.model}`));
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
        .filter((p) => !q || `${p.manufacturer} ${p.model} ${p.type} ${p.serialNumber || ""}`.toLowerCase().includes(q))
        .slice(0, 40)
        .forEach((p) => {
          const row = el("div", "row click");
          row.append(chipIcon("box", colorForType(p.type)));
          const main = el("div", "row-main");
          main.append(el("div", "row-title", `${p.manufacturer} ${p.model}`));
          main.append(el("div", "row-sub", [p.type, p.rating, p.serialNumber && `Serial: ${p.serialNumber}`].filter(Boolean).join(" · ")));
          row.append(main);
          row.addEventListener("click", async () => {
            await api("/api/part-settings", { partID: p.id, minimumLevel: null, location: "" });
            close();
            await refresh();
            switchView("stock");
          });
          list.append(row);
        });
    };
    search.addEventListener("input", draw);
    draw();
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
    const serialNumber = field("Serial number", "optional");
    modal.append(model.label, manufacturer.label, type.label, rating.label, serialNumber.label);
    modal.append(modalActions(close, "Add part", async () => {
      if (!model.input.value.trim() || !type.input.value.trim()) return;
      const { part } = await api("/api/parts", {
        model: model.input.value,
        manufacturer: manufacturer.input.value,
        type: type.input.value,
        rating: rating.input.value,
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

function openNewBoardModal() {
  openModal((modal, close) => {
    modal.append(el("h3", null, "New board"));
    const number = field("Board number", "e.g. 2026-114");
    const name = field("Name", "e.g. Azrieli MDB");
    const customer = field("Customer", "optional");
    const assign = el("label", null, "Give the board to");
    const select = memberSelect(null);
    assign.append(select);
    modal.append(number.label, name.label, customer.label, assign);
    modal.append(modalActions(close, "Create", async () => {
      if (!number.input.value.trim() && !name.input.value.trim()) return;
      await api("/api/boards", {
        number: number.input.value,
        name: name.input.value,
        customer: customer.input.value,
        assignedTo: select.value || null,
      });
      close();
      await refresh();
      switchView("boards");
    }));
  });
}

function openAssignModal(board) {
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
      switchView("boards");
    }));
  });
}

// ---------------------------------------------------------------- start

boot();
