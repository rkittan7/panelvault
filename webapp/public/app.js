// PanelVault Cloud frontend — vanilla JS, no build step.

let state = null; // last /api/state payload
let catalog = null; // lazy-loaded parts list

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
};

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

const isAdmin = () => state && (state.me.role === "owner" || state.me.role === "manager");

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
  document.querySelectorAll(".auth-tabs button").forEach((b) =>
    b.classList.toggle("active", b.dataset.tab === tab));
  ["login", "create", "join"].forEach((name) =>
    $(`#form-${name}`).classList.toggle("hidden", name !== tab));
  $("#auth-error").classList.add("hidden");
}

document.querySelectorAll(".auth-tabs button").forEach((b) =>
  b.addEventListener("click", () => switchAuthTab(b.dataset.tab)));

function wireAuthForm(id, endpoint, transform) {
  $(id).addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.target));
    try {
      await api(endpoint, transform ? transform(data) : data);
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

document.querySelectorAll(".tabs button").forEach((b) =>
  b.addEventListener("click", () => switchView(b.dataset.view)));

function switchView(view) {
  document.querySelectorAll(".tabs button").forEach((b) =>
    b.classList.toggle("active", b.dataset.view === view));
  document.querySelectorAll(".view").forEach((v) =>
    v.classList.toggle("hidden", v.id !== `view-${view}`));
}

async function refresh() {
  state = await api("/api/state");
  $("#company-name").textContent = state.company.name;
  $("#me-line").textContent = `${state.me.name} • ${state.me.role} • code ${state.company.code}`;
  $("#tab-team").classList.toggle("hidden", !isAdmin());
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

// ---------------------------------------------------------------- dashboard

function statTile(icon, label, value, colorVar) {
  const card = el("div", "card stat");
  card.append(el("div", "icon", icon));
  const v = el("div", "value", String(value));
  v.style.color = `var(--${colorVar})`;
  card.append(v, el("div", "label", label));
  return card;
}

function movementRow(m) {
  const card = el("div", "card row");
  const grow = el("div", "grow");
  grow.append(el("div", "title", m.partName));
  const when = new Date(m.date).toLocaleString();
  grow.append(el("div", "sub", [m.reference, m.userName, when].filter(Boolean).join(" • ")));
  const delta = m.kind === "consume" ? -m.quantity : m.quantity;
  card.append(grow, el("div", `delta ${delta >= 0 ? "pos" : "neg"}`, delta >= 0 ? `+${delta}` : `${delta}`));
  return card;
}

function renderDashboard() {
  const view = $("#view-dashboard");
  view.replaceChildren();

  const low = state.stock.filter((s) => s.minimumLevel != null && s.onHand <= s.minimumLevel);
  const units = state.stock.reduce((sum, s) => sum + s.onHand, 0);

  const stats = el("div", "stats");
  stats.append(
    statTile("📦", "Parts stocked", state.stock.length, "primary"),
    statTile("#", "Units on hand", units, "secondary"),
    statTile("⚠️", "Low stock", low.length, low.length ? "warning" : "positive"),
    statTile("🛠", "Boards", state.boards.length, "positive"),
  );
  view.append(stats);

  if (low.length) {
    view.append(el("div", "section-title", "Low stock"));
    low.forEach((s) => {
      const card = el("div", "card row");
      const grow = el("div", "grow");
      grow.append(el("div", "title", `${s.part.manufacturer} ${s.part.model}`));
      grow.append(el("div", "sub", `${s.onHand} left • minimum ${s.minimumLevel}`));
      card.append(grow, el("div", "qty low", s.onHand));
      view.append(card);
    });
  }

  view.append(el("div", "section-title", "Recent activity"));
  if (!state.movements.length) {
    view.append(el("div", "card muted", "No stock movements yet."));
  }
  state.movements.slice(0, 10).forEach((m) => view.append(movementRow(m)));
}

// ---------------------------------------------------------------- stock

function renderStock() {
  const view = $("#view-stock");
  view.replaceChildren();

  const toolbar = el("div", "toolbar");
  const search = el("input");
  search.placeholder = "Search stock…";
  toolbar.append(search);
  if (isAdmin()) {
    const addBtn = el("button", "chip accent", "＋ Add part to stock");
    addBtn.addEventListener("click", () => openPartPicker());
    const newBtn = el("button", "chip", "＋ New custom part");
    newBtn.addEventListener("click", () => openNewPartModal());
    toolbar.append(addBtn, newBtn);
  }
  view.append(toolbar);

  const list = el("div", "view");
  view.append(list);

  const draw = () => {
    list.replaceChildren();
    const q = search.value.trim().toLowerCase();
    const rows = state.stock.filter((s) =>
      !q || `${s.part.manufacturer} ${s.part.model} ${s.part.type} ${s.location}`.toLowerCase().includes(q));
    if (!rows.length) {
      list.append(el("div", "card muted", state.stock.length
        ? "Nothing matches that search."
        : "No stock yet. The boss or a manager adds parts here."));
    }
    rows.forEach((s) => {
      const card = el("div", "card row");
      const grow = el("div", "grow");
      grow.append(el("div", "title", `${s.part.manufacturer} ${s.part.model}`));
      const bits = [s.part.type, s.part.rating, s.location].filter(Boolean).join(" • ");
      grow.append(el("div", "sub", bits));
      const isLow = s.minimumLevel != null && s.onHand <= s.minimumLevel;
      card.append(grow, el("div", `qty ${isLow ? "low" : "ok"}`, String(s.onHand)));
      if (isAdmin()) {
        const actions = el("div", "toolbar");
        const receive = el("button", "chip accent", "＋ In");
        receive.addEventListener("click", () => openMovementModal(s, "receive"));
        const consume = el("button", "chip", "－ Out");
        consume.addEventListener("click", () => openMovementModal(s, "consume"));
        const settings = el("button", "chip", "⚙");
        settings.addEventListener("click", () => openSettingsModal(s));
        actions.append(receive, consume, settings);
        card.append(actions);
      }
      list.append(card);
    });
  };
  search.addEventListener("input", draw);
  draw();
}

// ---------------------------------------------------------------- boards

function renderBoards() {
  const view = $("#view-boards");
  view.replaceChildren();

  if (isAdmin()) {
    const toolbar = el("div", "toolbar");
    const btn = el("button", "chip accent", "＋ New board");
    btn.addEventListener("click", openNewBoardModal);
    toolbar.append(btn);
    view.append(toolbar);
  }

  if (!state.boards.length) {
    view.append(el("div", "card muted", "No boards yet."));
  }

  const mine = state.boards.filter((b) => b.assignedTo === state.me.id);
  const others = state.boards.filter((b) => b.assignedTo !== state.me.id);

  const boardCard = (b, isMine) => {
    const card = el("div", "card row");
    const grow = el("div", "grow");
    const title = [b.number, b.name].filter(Boolean).join(" — ");
    grow.append(el("div", "title", title + (isMine ? "  (yours)" : "")));
    grow.append(el("div", "sub", [b.customer, b.assignedName ? `→ ${b.assignedName}` : "unassigned"].filter(Boolean).join(" • ")));
    card.append(grow);
    const status = el("span", `badge ${b.status.replace(" ", "")}`, b.status);
    card.append(status);
    if (isAdmin() || isMine) {
      const next = el("button", "chip", "Status ▸");
      next.addEventListener("click", async () => {
        const order = ["Design", "In Progress", "Completed"];
        const nextStatus = order[(order.indexOf(b.status) + 1) % order.length];
        await api("/api/board-update", { boardID: b.id, status: nextStatus });
        await refresh();
        switchView("boards");
      });
      card.append(next);
    }
    if (isAdmin()) {
      const assign = el("button", "chip", "Assign");
      assign.addEventListener("click", () => openAssignModal(b));
      card.append(assign);
    }
    return card;
  };

  if (mine.length) {
    view.append(el("div", "section-title", "Your boards"));
    mine.forEach((b) => view.append(boardCard(b, true)));
  }
  if (others.length) {
    view.append(el("div", "section-title", mine.length ? "All boards" : "Boards"));
    others.forEach((b) => view.append(boardCard(b, false)));
  }
}

// ---------------------------------------------------------------- team

function renderTeam() {
  const view = $("#view-team");
  view.replaceChildren();

  view.append(el("div", "section-title", "Invite links"));
  const info = el("div", "card muted small",
    "Send a link to your team. Workers see stock and their boards; managers can also change the warehouse and assign boards.");
  view.append(info);

  const toolbar = el("div", "toolbar");
  const workerBtn = el("button", "chip accent", "＋ Worker invite link");
  workerBtn.addEventListener("click", () => createInvite("worker"));
  toolbar.append(workerBtn);
  if (state.me.role === "owner") {
    const managerBtn = el("button", "chip", "＋ Manager invite link");
    managerBtn.addEventListener("click", () => createInvite("manager"));
    toolbar.append(managerBtn);
  }
  view.append(toolbar);

  (state.invites || []).forEach((invite) => {
    const card = el("div", "card");
    const link = `${location.origin}/#join/${state.company.code}/${invite.code}`;
    const head = el("div", "row");
    head.append(el("span", `badge ${invite.role}`, invite.role));
    const copy = el("button", "chip accent", "Copy link");
    copy.addEventListener("click", async () => {
      await navigator.clipboard.writeText(link);
      copy.textContent = "Copied ✓";
      setTimeout(() => (copy.textContent = "Copy link"), 1500);
    });
    const revoke = el("button", "chip danger", "Revoke");
    revoke.addEventListener("click", async () => {
      await api("/api/invite-revoke", { code: invite.code });
      await refresh();
      switchView("team");
    });
    const grow = el("div", "grow");
    head.insertBefore(grow, copy);
    head.append(copy, revoke);
    card.append(head, el("div", "invite-box", link));
    view.append(card);
  });

  view.append(el("div", "section-title", "Members"));
  (state.members || []).forEach((member) => {
    const card = el("div", "card row");
    const grow = el("div", "grow");
    grow.append(el("div", "title", member.name + (member.active ? "" : "  (disabled)")));
    grow.append(el("div", "sub", `joined ${new Date(member.createdAt).toLocaleDateString()}`));
    card.append(grow, el("span", `badge ${member.role}`, member.role));
    if (state.me.role === "owner" && member.role !== "owner") {
      const toggle = el("button", `chip ${member.active ? "danger" : "accent"}`, member.active ? "Disable" : "Enable");
      toggle.addEventListener("click", async () => {
        await api("/api/member-update", { userID: member.id, active: !member.active });
        await refresh();
        switchView("team");
      });
      card.append(toggle);
    }
    view.append(card);
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
  const modal = el("div", "card modal");
  const close = () => root.replaceChildren();
  backdrop.addEventListener("click", (event) => {
    if (event.target === backdrop) close();
  });
  build(modal, close);
  backdrop.append(modal);
  root.replaceChildren(backdrop);
}

function modalActions(close, submitLabel, onSubmit) {
  const actions = el("div", "actions");
  const cancel = el("button", "ghost", "Cancel");
  cancel.addEventListener("click", close);
  const ok = el("button", "primary", submitLabel);
  ok.addEventListener("click", onSubmit);
  actions.append(cancel, ok);
  return actions;
}

function labeledInput(labelText, placeholder, type = "text") {
  const label = el("label", "small");
  label.style.display = "flex";
  label.style.flexDirection = "column";
  label.style.gap = "6px";
  label.style.fontWeight = "700";
  label.style.color = "var(--muted)";
  label.append(labelText);
  const input = el("input");
  input.placeholder = placeholder;
  input.type = type;
  label.append(input);
  return { label, input };
}

function openMovementModal(entry, kind) {
  openModal((modal, close) => {
    modal.append(el("h3", null, kind === "receive" ? "Stock in" : "Stock out"));
    modal.append(el("div", "muted small", `${entry.part.manufacturer} ${entry.part.model} — ${entry.onHand} on hand`));
    const qty = labeledInput("Quantity", "e.g. 10", "number");
    const ref = labeledInput(kind === "consume" ? "Board number" : "Delivery note / reference", "optional");
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
    modal.append(el("div", "muted small", `${entry.part.manufacturer} ${entry.part.model}`));
    const min = labeledInput("Minimum level (0 = no alert)", "0", "number");
    min.input.value = entry.minimumLevel ?? 0;
    const loc = labeledInput("Location", "Shelf / drawer");
    loc.input.value = entry.location;
    modal.append(min.label, loc.label);
    modal.append(modalActions(close, "Save", async () => {
      const minimum = parseInt(min.input.value, 10) || 0;
      await api("/api/part-settings", {
        partID: entry.part.id,
        minimumLevel: minimum === 0 ? null : minimum,
        location: loc.input.value,
      });
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
    const search = el("input");
    search.placeholder = "Search 199+ parts…";
    modal.append(search);
    const list = el("div", "list-scroll");
    modal.append(list);

    const draw = () => {
      list.replaceChildren();
      const q = search.value.trim().toLowerCase();
      const matches = catalog
        .filter((p) => !q || `${p.manufacturer} ${p.model} ${p.type}`.toLowerCase().includes(q))
        .slice(0, 40);
      matches.forEach((p) => {
        const row = el("div", "card row");
        const grow = el("div", "grow");
        grow.append(el("div", "title", `${p.manufacturer} ${p.model}`));
        grow.append(el("div", "sub", `${p.type} • ${p.rating}`));
        row.append(grow);
        row.style.cursor = "pointer";
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
    const model = labeledInput("Model", "e.g. Cable tray 200mm");
    const manufacturer = labeledInput("Manufacturer", "optional");
    const type = labeledInput("Type", "e.g. Cable Tray");
    const rating = labeledInput("Rating", "optional");
    modal.append(model.label, manufacturer.label, type.label, rating.label);
    modal.append(modalActions(close, "Add part", async () => {
      if (!model.input.value.trim() || !type.input.value.trim()) return;
      const { part } = await api("/api/parts", {
        model: model.input.value,
        manufacturer: manufacturer.input.value,
        type: type.input.value,
        rating: rating.input.value,
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
    const number = labeledInput("Board number", "e.g. 2026-114");
    const name = labeledInput("Name", "e.g. Azrieli MDB");
    const customer = labeledInput("Customer", "optional");
    const assignLabel = el("label", "small", "Give the board to");
    assignLabel.style.cssText = "display:flex;flex-direction:column;gap:6px;font-weight:700;color:var(--muted)";
    const select = memberSelect(null);
    assignLabel.append(select);
    modal.append(number.label, name.label, customer.label, assignLabel);
    modal.append(modalActions(close, "Create", async () => {
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
    modal.append(el("div", "muted small", [board.number, board.name].filter(Boolean).join(" — ")));
    const select = memberSelect(board.assignedTo);
    modal.append(select);
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
