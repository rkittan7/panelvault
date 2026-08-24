const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const webapp = __dirname;

test("the website board manufacturer picker includes Tamhash and preserves new AI names", () => {
  const browserApp = fs.readFileSync(path.join(webapp, "public", "app.js"), "utf8");
  assert.match(browserApp, /BOARD_MANUFACTURERS[\s\S]*"Tamhash"/);
  assert.match(browserApp, /manufacturer\.select\.append\(new Option\(aiManufacturer/);
});

test("the board Components tab keeps model variants together with highest ampere first", () => {
  const browserApp = fs.readFileSync(path.join(webapp, "public", "app.js"), "utf8");
  assert.match(browserApp, /function compareBoardComponents\(left, right\)/);
  assert.match(browserApp, /return rightAmpere - leftAmpere/);
  assert.match(browserApp, /\[\.\.\.\(board\.components \|\| \[\]\)\]\.sort\(compareBoardComponents\)/);
  assert.match(browserApp, /\[\.\.\.board\.componentDrafts\]\.sort\(compareBoardComponents\)/);
});

async function startServer(extraEnv = {}) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "panelvault-cloud-test-"));
  const child = spawn(process.execPath, ["server.js"], {
    cwd: webapp,
    env: { ...process.env, PORT: "0", DATA_DIR: dataDir, ...extraEnv },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const stop = () => {
    child.kill("SIGTERM");
    fs.rmSync(dataDir, { recursive: true, force: true });
  };

  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Server did not start")), 5000);
    child.once("exit", (code) => reject(new Error(`Server exited with ${code}`)));
    child.stdout.on("data", (chunk) => {
      const match = chunk.toString().match(/localhost:(\d+)/);
      if (!match) return;
      clearTimeout(timer);
      resolve(Number(match[1]));
    });
  });
  return { baseURL: `http://127.0.0.1:${port}`, stop };
}

async function json(baseURL, route, options = {}) {
  const url = new URL(baseURL + route);
  return new Promise((resolve, reject) => {
    const request = http.request(url, {
      method: options.method || "GET",
      headers: { "Content-Type": "application/json", ...options.headers },
    }, (response) => {
      let raw = "";
      response.on("data", (chunk) => { raw += chunk; });
      response.on("end", () => resolve({
        response: { status: response.statusCode },
        body: JSON.parse(raw),
      }));
    });
    request.on("error", reject);
    if (options.body) request.write(options.body);
    request.end();
  });
}

test("mobile movement sync is authenticated, atomic, and idempotent", async () => {
  const server = await startServer();
  const { baseURL } = server;
  try {
  const health = await json(baseURL, "/api/health");
  assert.equal(health.response.status, 200);
  assert.deepEqual(health.body, { ok: true, storage: "local" });

  const registered = await json(baseURL, "/api/company", {
    method: "POST",
    body: JSON.stringify({ companyName: "Kittan Electric", name: "Rawe", password: "secret12" }),
  });
  assert.equal(registered.response.status, 200);

  const login = await json(baseURL, "/api/mobile/login", {
    method: "POST",
    body: JSON.stringify({
      companyCode: registered.body.companyCode,
      name: "Rawe",
      password: "secret12",
    }),
  });
  assert.equal(login.response.status, 200);
  assert.equal(login.body.company.name, "Kittan Electric");
  const authorization = { Authorization: `Bearer ${login.body.token}` };

  const unauthorized = await json(baseURL, "/api/sync/movements?after=0");
  assert.equal(unauthorized.response.status, 401);

  const partID = JSON.parse(fs.readFileSync(path.join(webapp, "catalog.json"), "utf8"))[0].id;
  const customPart = {
    id: "custom-B89AF5A2-79E3-4DA2-92E7-A8094D106A73",
    manufacturer: "Workshop",
    type: "Terminal Block",
    model: "Special TB",
    rating: "32A",
    poles: "1P",
    curve: "",
    about: "Test custom stock item",
    serialNumber: "SN-WORKER-0042",
  };
  const customUpload = await json(baseURL, "/api/sync/parts", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ customParts: [customPart] }),
  });
  assert.equal(customUpload.response.status, 200);
  assert.equal(customUpload.body.customParts[0].id, customPart.id);
  assert.equal(customUpload.body.customParts[0].serialNumber, customPart.serialNumber);
  const websitePart = await json(baseURL, "/api/parts", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({
      manufacturer: "ABB",
      type: "Contactor",
      model: "AF30",
      rating: "30A",
      serialNumber: "SN-WEB-0099",
    }),
  });
  assert.equal(websitePart.response.status, 200);
  assert.equal(websitePart.body.part.serialNumber, "SN-WEB-0099");
  const mcbTemplate = JSON.parse(fs.readFileSync(path.join(webapp, "catalog.json"), "utf8"))
    .find((part) => String(part.type).toUpperCase().includes("MCB")
      && !String(part.type).toUpperCase().includes("MCCB"));
  assert.ok(mcbTemplate, "catalog should contain an MCB template");
  const ratedVariant = {
    manufacturer: mcbTemplate.manufacturer,
    type: mcbTemplate.type,
    model: mcbTemplate.model,
    rating: "16A",
    poles: "1P",
    curve: "C Curve",
    sourceID: mcbTemplate.id,
  };
  const firstVariant = await json(baseURL, "/api/parts", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify(ratedVariant),
  });
  assert.equal(firstVariant.response.status, 200);
  assert.equal(firstVariant.body.part.rating, "16A");
  assert.equal(firstVariant.body.part.poles, "1P");
  assert.equal(firstVariant.body.part.curve, "C Curve");
  assert.equal(firstVariant.body.part.sourceID, mcbTemplate.id);
  const duplicateVariant = await json(baseURL, "/api/parts", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify(ratedVariant),
  });
  assert.equal(duplicateVariant.response.status, 200);
  assert.equal(duplicateVariant.body.part.id, firstVariant.body.part.id);
  assert.equal(duplicateVariant.body.existing, true);
  const barcode = {
    code: "7612270934765",
    symbology: "EAN-13",
    partID,
    packageQuantity: 6,
    boxLabel: "Opening stock box",
    updatedAt: "2026-08-16T12:00:00.000Z",
    updatedByDeviceID: "test-phone",
  };
  const barcodeUpload = await json(baseURL, "/api/sync/barcodes", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ barcodeMappings: [barcode] }),
  });
  assert.equal(barcodeUpload.response.status, 200);
  assert.equal(barcodeUpload.body.barcodeMappings[0].packageQuantity, 6);
  const movement = {
    id: "B89AF5A2-79E3-4DA2-92E7-A8094D106A72",
    partID,
    kind: "receive",
    quantity: 12,
    reference: "Delivery 1842",
    date: "2026-08-16T12:00:00.000Z",
    deviceID: "test-phone",
  };

  const invalidBatch = await json(baseURL, "/api/sync/movements", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ movements: [movement, { ...movement, id: "bad" }] }),
  });
  assert.equal(invalidBatch.response.status, 400);

  const emptyAfterFailure = await json(baseURL, "/api/sync/movements?after=0", { headers: authorization });
  assert.deepEqual(emptyAfterFailure.body.movements, []);

  const firstUpload = await json(baseURL, "/api/sync/movements", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ movements: [movement] }),
  });
  assert.equal(firstUpload.response.status, 200);
  assert.deepEqual(firstUpload.body.acceptedIDs, [movement.id]);
  assert.equal(firstUpload.body.latestSequence, 1);

  const retry = await json(baseURL, "/api/sync/movements", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ movements: [movement] }),
  });
  assert.deepEqual(retry.body.acceptedIDs, []);
  assert.deepEqual(retry.body.duplicateIDs, [movement.id]);

  const downloaded = await json(baseURL, "/api/sync/movements?after=0", { headers: authorization });
  assert.equal(downloaded.body.movements.length, 1);
  assert.equal(downloaded.body.movements[0].quantity, 12);
  assert.equal(downloaded.body.movements[0].sequence, 1);
  assert.equal(downloaded.body.movements[0].deviceID, "test-phone");
  assert.equal(downloaded.body.barcodeMappings[0].code, barcode.code);

  const state = await json(baseURL, "/api/state", { headers: authorization });
  assert.equal(state.body.stock[0].onHand, 12);
  assert.equal(state.body.movements[0].userName, "Rawe");
  } finally {
    server.stop();
  }
});

test("projects and boards use the same creation contract as the app", async () => {
  const server = await startServer();
  try {
    const registered = await json(server.baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Synced Panels", name: "Owner", password: "secret12" }),
    });
    const headers = { Authorization: `Bearer ${registered.body.token}` };
    const createdProject = await json(server.baseURL, "/api/projects", {
      method: "POST", headers,
      body: JSON.stringify({ name: "Tower A", customer: "Acme", site: "Tel Aviv", dueDate: "2026-09-01T12:00:00Z" }),
    });
    assert.equal(createdProject.response.status, 200);
    assert.equal(createdProject.body.project.customer, "Acme");

    const createdBoard = await json(server.baseURL, "/api/boards", {
      method: "POST", headers,
      body: JSON.stringify({
        number: "3918.24-1", group: "3918.24", name: "Main LV Board",
        customer: "Wrong customer", project: "Tower A", company: "PanelVault",
        type: "MDB", subtype: "Form 3b", manufacturer: "ABB", cabinetCount: "3",
        buildFormat: "Panels", dateOut: "2026-08-22", dueDate: "2026-09-01T12:00:00Z",
        mainBreakerType: "MCCB", mainBreakerModel: "Tmax XT7", mainBreakerAmpere: "630A",
        qaAssignedTo: registered.body.user.id,
        components: [{
          partID: "abb-s202-2p", quantity: 4, reference: "QF20-QF23",
          rawText: "ABB S202 C16 x4", rating: "16A", poles: "2P", curve: "C", sourcePage: 7,
        }],
        componentDrafts: [{
          description: "Siemens 5SY C10", manufacturer: "Siemens", model: "5SY",
          type: "MCB", rating: "10A", poles: "1P", curve: "C", quantity: 2, reference: "QF30-QF31",
          rawText: "Siemens 5SY C10 x2", sourcePage: 8,
        }],
      }),
    });
    assert.equal(createdBoard.response.status, 200);
    assert.equal(createdBoard.body.board.customer, "Acme");
    assert.equal(createdBoard.body.board.project, "Tower A");
    assert.equal(createdBoard.body.board.cabinetCount, "3");
    assert.equal(createdBoard.body.board.mainBreakerModel, "Tmax XT7");
    assert.equal(createdBoard.body.board.status, "Design");
    assert.equal(createdBoard.body.board.completion, 0);
    assert.equal(createdBoard.body.board.cabinetChecklists.length, 3);
    assert.equal(createdBoard.body.board.components.length, 1);
    assert.equal(createdBoard.body.board.components[0].source, "ai");
    assert.equal(createdBoard.body.board.components[0].sourcePage, 7);
    assert.equal(createdBoard.body.board.components[0].rating, "16A");
    assert.equal(createdBoard.body.board.components[0].poles, "2P");
    assert.equal(createdBoard.body.board.components[0].curve, "C");
    assert.equal(createdBoard.body.board.componentDrafts.length, 1);
    assert.equal(createdBoard.body.board.componentDrafts[0].description, "Siemens 5SY C10");

    const assigned = await json(server.baseURL, "/api/board-update", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, assignedTo: registered.body.user.id }),
    });
    assert.equal(assigned.response.status, 200);
    assert.equal(assigned.body.status, "Design");
    const unassigned = await json(server.baseURL, "/api/board-update", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, assignedTo: null }),
    });
    assert.equal(unassigned.response.status, 200);
    assert.equal(unassigned.body.status, "Design");

    const manualStatus = await json(server.baseURL, "/api/board-update", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, status: "Completed" }),
    });
    assert.equal(manualStatus.response.status, 400);

    const firstCheck = await json(server.baseURL, "/api/board-checklist", {
      method: "POST", headers,
      body: JSON.stringify({
        boardID: createdBoard.body.board.id,
        cabinetIndex: 0,
        itemID: createdBoard.body.board.checklist[0].id,
        checked: true,
      }),
    });
    assert.equal(firstCheck.response.status, 200);
    assert.equal(firstCheck.body.status, "Design");
    assert.equal(firstCheck.body.completion, 0);

    for (const stageID of ["mechanical", "components", "wiring", "finishing", "qa"]) {
      const staged = await json(server.baseURL, "/api/board-stage", {
        method: "POST", headers,
        body: JSON.stringify({ boardID: createdBoard.body.board.id, stageID }),
      });
      assert.equal(staged.response.status, 200);
    }

    const directComplete = await json(server.baseURL, "/api/board-stage", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, stageID: "complete" }),
    });
    assert.equal(directComplete.response.status, 400);

    const component = await json(server.baseURL, "/api/board-components", {
      method: "POST", headers,
      body: JSON.stringify({
        boardID: createdBoard.body.board.id, action: "add", partID: "abb-s201-1p", quantity: 12, reference: "QF1-QF12",
      }),
    });
    assert.equal(component.response.status, 200);
    assert.equal(component.body.board.components.find((item) => item.reference === "QF1-QF12").quantity, 12);

    const matchedDraft = await json(server.baseURL, "/api/board-components", {
      method: "POST", headers,
      body: JSON.stringify({
        boardID: createdBoard.body.board.id,
        action: "add",
        draftID: createdBoard.body.board.componentDrafts[0].id,
        partID: "siemens-5sy",
        quantity: 2,
        reference: "QF30-QF31",
      }),
    });
    assert.equal(matchedDraft.response.status, 200);
    assert.equal(matchedDraft.body.board.componentDrafts.length, 0);
    const importedDraft = matchedDraft.body.board.components.find((item) => item.reference === "QF30-QF31");
    assert.equal(importedDraft.source, "ai");
    assert.equal(importedDraft.rating, "10A");
    assert.equal(importedDraft.poles, "1P");
    assert.equal(importedDraft.curve, "C");

    const uploaded = await json(server.baseURL, "/api/board-attachment", {
      method: "POST", headers,
      body: JSON.stringify({
        boardID: createdBoard.body.board.id, kind: "scheme", fileName: "main.pdf",
        mimeType: "application/pdf", data: Buffer.from("test-pdf").toString("base64"),
      }),
    });
    assert.equal(uploaded.response.status, 200);
    const downloaded = await fetch(`${server.baseURL}/api/board-attachment?id=${uploaded.body.attachment.id}`, { headers });
    assert.equal(downloaded.status, 200);
    assert.equal(await downloaded.text(), "test-pdf");

    const state = await json(server.baseURL, "/api/state", { headers });
    assert.equal(state.body.projects.length, 1);
    assert.equal(state.body.boards[0].group, "3918.24");
    assert.equal(state.body.boards[0].completion, 100);
    assert.equal(state.body.boards[0].status, "QA Ready");
    assert.equal(state.body.boards[0].currentStage.id, "qa");
    assert.deepEqual(state.body.boards[0].stages.map((stage) => stage.label), [
      "Design", "Mechanical Build", "Components", "Wiring", "Finishing", "QA", "Complete",
    ]);

    const notifications = await json(server.baseURL, "/api/notifications", { headers });
    assert.equal(notifications.response.status, 200);
    assert.equal(notifications.body.notifications.length, 1);
    assert.equal(notifications.body.notifications[0].type, "board_ready_for_qa");

    const approved = await json(server.baseURL, "/api/board-qa", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, action: "approve", note: "QA passed" }),
    });
    assert.equal(approved.response.status, 200);
    assert.equal(approved.body.status, "Completed");
    assert.equal(approved.body.currentStage.id, "complete");

    const reopened = await json(server.baseURL, "/api/board-stage", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, stageID: "qa" }),
    });
    assert.equal(reopened.response.status, 200);
    const corrections = await json(server.baseURL, "/api/board-qa", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, action: "request_changes", note: "Replace one label" }),
    });
    assert.equal(corrections.response.status, 200);
    assert.equal(corrections.body.status, "QA Changes");
    assert.equal(corrections.body.currentStage.id, "finishing");

    const resubmitted = await json(server.baseURL, "/api/board-stage", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, stageID: "qa" }),
    });
    assert.equal(resubmitted.body.status, "QA Ready");
    const resubmissionNotifications = await json(server.baseURL, "/api/notifications", { headers });
    assert.equal(resubmissionNotifications.body.notifications.length, 3);

    const reapproved = await json(server.baseURL, "/api/board-qa", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, action: "approve", note: "Corrections passed" }),
    });
    assert.equal(reapproved.body.status, "Completed");

    const workspace = await json(server.baseURL, "/api/sync/workspace", { headers });
    assert.equal(workspace.response.status, 200);
    assert.equal(workspace.body.boards[0].cabinetChecklists.length, 3);
    const synced = await json(server.baseURL, "/api/sync/workspace", {
      method: "POST", headers,
      body: JSON.stringify({
        expectedVersion: workspace.body.version,
        projects: workspace.body.projects,
        boards: workspace.body.boards.map((board) => ({ ...board, name: "Main LV Board synced from phone" })),
      }),
    });
    assert.equal(synced.response.status, 200);
    assert.equal(synced.body.version, workspace.body.version + 1);
    assert.equal(synced.body.boards[0].name, "Main LV Board synced from phone");
    const phoneProgress = await json(server.baseURL, "/api/sync/board-progress", {
      method: "POST", headers,
      body: JSON.stringify({
        expectedVersion: synced.body.version,
        boards: [{
          id: synced.body.boards[0].id,
          cabinetChecklists: [[], [], []],
          personalChecklistItems: [{ id: "personal-phone", title: "Phone QA", isDone: true }],
        }],
      }),
    });
    assert.equal(phoneProgress.response.status, 200);
    assert.equal(phoneProgress.body.version, synced.body.version + 1);
    assert.equal(phoneProgress.body.boards[0].completion, 100);
    assert.equal(phoneProgress.body.boards[0].status, "Completed");
    assert.equal(phoneProgress.body.boards[0].qaStatus, "approved");
    assert.equal(phoneProgress.body.boards[0].personalChecklistItems[0].title, "Phone QA");
  } finally {
    server.stop();
  }
});

test("scanned requirements consolidate once and issue only available exact stock", async () => {
  const server = await startServer();
  try {
    const owner = await json(server.baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Stocked Panels", name: "Owner", password: "secret12" }),
    });
    const headers = { Authorization: `Bearer ${owner.body.token}` };
    const variant = await json(server.baseURL, "/api/parts", {
      method: "POST", headers,
      body: JSON.stringify({
        sourceID: "abb-s202-2p", manufacturer: "ABB", model: "S202", type: "MCB",
        rating: "16A", poles: "2P", curve: "C Curve",
      }),
    });
    assert.equal(variant.response.status, 200);
    await json(server.baseURL, "/api/movements", {
      method: "POST", headers,
      body: JSON.stringify({ partID: variant.body.part.id, kind: "receive", quantity: 3, reference: "Opening stock" }),
    });

    const created = await json(server.baseURL, "/api/boards", {
      method: "POST", headers,
      body: JSON.stringify({
        number: "STOCK-1", name: "Stock Test Board", customer: "Acme", project: "No Project",
        components: [
          { partID: "abb-s202-2p", quantity: 2, reference: "QF1-QF2", rating: "16A", poles: "2P", curve: "C" },
          { partID: "abb-s202-2p", quantity: 2, reference: "QF3-QF4", rating: "16A", poles: "2P", curve: "C" },
        ],
      }),
    });
    assert.equal(created.response.status, 200);
    assert.equal(created.body.board.components.length, 1);
    assert.equal(created.body.board.components[0].quantity, 4);
    assert.equal(created.body.board.components[0].reference, "QF1-QF2, QF3-QF4");

    const afterCreate = await json(server.baseURL, "/api/state", { headers });
    const board = afterCreate.body.boards.find((item) => item.id === created.body.board.id);
    const stocked = afterCreate.body.stock.find((entry) => entry.part.id === variant.body.part.id);
    assert.equal(stocked.onHand, 0);
    assert.deepEqual(board.components[0].stock, {
      status: "short", required: 4, issued: 3, remaining: 1, available: 0,
    });
    const automaticIssue = afterCreate.body.movements.find((movement) => movement.boardComponentID === board.components[0].id);
    assert.equal(automaticIssue.kind, "consume");
    assert.equal(automaticIssue.quantity, 3);
    assert.equal(automaticIssue.boardID, board.id);

    await json(server.baseURL, "/api/movements", {
      method: "POST", headers,
      body: JSON.stringify({ partID: variant.body.part.id, kind: "receive", quantity: 1, reference: "Back order" }),
    });
    const issued = await json(server.baseURL, "/api/board-components", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: board.id, action: "issueStock" }),
    });
    assert.equal(issued.response.status, 200);

    const complete = await json(server.baseURL, "/api/state", { headers });
    const completeBoard = complete.body.boards.find((item) => item.id === board.id);
    assert.deepEqual(completeBoard.components[0].stock, {
      status: "issued", required: 4, issued: 4, remaining: 0, available: 0,
    });
    assert.equal(complete.body.stock.find((entry) => entry.part.id === variant.body.part.id).onHand, 0);
  } finally {
    server.stop();
  }
});

test("a confirmed delivery uploads once and keeps its paperwork", async () => {
  const server = await startServer();
  const { baseURL } = server;
  try {
    const owner = await json(baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Kittan Electric", name: "Rawe", password: "secret12" }),
    });
    const authorization = { Authorization: `Bearer ${owner.body.token}` };
    const partID = JSON.parse(fs.readFileSync(path.join(webapp, "catalog.json"), "utf8"))[0].id;

    const movement = {
      id: "6C7B1A18-4C6E-4E56-9C6D-7C1B2A3D4E5F",
      partID,
      kind: "receive",
      quantity: 24,
      reference: "DN-5591",
      date: "2026-08-20T08:15:00.000Z",
      deviceID: "workshop-phone",
    };
    const delivery = {
      id: "1D2C3B4A-5E6F-4A7B-8C9D-0E1F2A3B4C5D",
      noteNumber: "DN-5591",
      supplier: "Electrical Supply Ltd",
      source: "scan",
      scannedAt: "2026-08-20T08:10:00.000Z",
      confirmedAt: "2026-08-20T08:15:00.000Z",
      pageCount: 2,
      deviceID: "workshop-phone",
      lines: [
        { rawText: "S203-C16 x24", quantity: 24, partID, included: true, movementID: movement.id },
        { rawText: "PALLET FEE 1", quantity: 1, partID: null, included: false, movementID: null },
      ],
      movementIDs: [movement.id],
    };

    // The batch may reach the server before its movements do — an offline
    // queue that had to upload in order would stall behind one failed request.
    const early = await json(baseURL, "/api/sync/deliveries", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({ deliveries: [delivery] }),
    });
    assert.equal(early.response.status, 200);
    assert.deepEqual(early.body.acceptedIDs, [delivery.id]);

    const pending = await json(baseURL, "/api/delivery?id=" + delivery.id, { headers: authorization });
    assert.equal(pending.body.delivery.missingMovements, 1);
    assert.equal(pending.body.delivery.unitCount, 0);

    await json(baseURL, "/api/sync/movements", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({ movements: [movement] }),
    });

    const detail = await json(baseURL, "/api/delivery?id=" + delivery.id, { headers: authorization });
    assert.equal(detail.response.status, 200);
    assert.equal(detail.body.delivery.supplier, "Electrical Supply Ltd");
    assert.equal(detail.body.delivery.userName, "Rawe");
    assert.equal(detail.body.delivery.missingMovements, 0);
    assert.equal(detail.body.delivery.unitCount, 24);
    assert.equal(detail.body.delivery.lineCount, 2);
    assert.equal(detail.body.delivery.confirmedLineCount, 1);
    // The rejected line is kept: the review decision is part of the evidence.
    assert.equal(detail.body.delivery.lines[1].rawText, "PALLET FEE 1");
    assert.equal(detail.body.delivery.lines[1].included, false);
    assert.equal(detail.body.delivery.movements[0].quantity, 24);

    // Retrying the whole confirmation cannot duplicate the paperwork or stock.
    const retry = await json(baseURL, "/api/sync/deliveries", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({ deliveries: [{ ...delivery, supplier: "Rewritten Supplier" }] }),
    });
    assert.deepEqual(retry.body.acceptedIDs, []);
    assert.deepEqual(retry.body.duplicateIDs, [delivery.id]);

    const unchanged = await json(baseURL, "/api/delivery?id=" + delivery.id, { headers: authorization });
    assert.equal(unchanged.body.delivery.supplier, "Electrical Supply Ltd");

    const unknownPart = await json(baseURL, "/api/sync/deliveries", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({
        deliveries: [{
          ...delivery,
          id: "9F8E7D6C-5B4A-4392-8172-6150493827AB",
          lines: [{ rawText: "ghost", quantity: 1, partID: "custom-not-mine", included: true }],
        }],
      }),
    });
    assert.equal(unknownPart.response.status, 400);

    const state = await json(baseURL, "/api/state", { headers: authorization });
    assert.equal(state.body.deliveries.length, 1);
    assert.equal(state.body.deliveries[0].noteNumber, "DN-5591");
    assert.equal(state.body.deliveries[0].unitCount, 24);

    const downloaded = await json(baseURL, "/api/sync/deliveries?after=0", { headers: authorization });
    assert.equal(downloaded.body.deliveries.length, 1);
    assert.equal(downloaded.body.deliveries[0].sequence, 1);
    assert.equal(downloaded.body.latestSequence, 1);
  } finally {
    server.stop();
  }
});

test("mobile company creation and invite join share the website account database", async () => {
  const server = await startServer();
  const { baseURL } = server;
  try {
    const owner = await json(baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Panel Builders", name: "Owner", password: "owner-secret" }),
    });
    assert.equal(owner.response.status, 200);
    assert.equal(owner.body.user.role, "owner");
    assert.equal(owner.body.company.name, "Panel Builders");
    const ownerAuthorization = { Authorization: `Bearer ${owner.body.token}` };

    const invitation = await json(baseURL, "/api/invites", {
      method: "POST",
      headers: ownerAuthorization,
      body: JSON.stringify({ role: "staff" }),
    });
    assert.equal(invitation.response.status, 200);

    const worker = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({
        companyCode: owner.body.company.code,
        inviteCode: invitation.body.invite.code,
        name: "Workshop Worker",
        password: "worker-secret",
      }),
    });
    assert.equal(worker.response.status, 200);
    assert.equal(worker.body.user.role, "staff");
    assert.equal(worker.body.company.code, owner.body.company.code);

    const workerLogin = await json(baseURL, "/api/mobile/login", {
      method: "POST",
      body: JSON.stringify({
        companyCode: owner.body.company.code,
        name: "Workshop Worker",
        password: "worker-secret",
      }),
    });
    assert.equal(workerLogin.response.status, 200);
    assert.equal(workerLogin.body.user.id, worker.body.user.id);
    assert.equal(workerLogin.body.company.code, owner.body.company.code);

    const assignedBoard = await json(baseURL, "/api/boards", {
      method: "POST",
      headers: ownerAuthorization,
      body: JSON.stringify({
        number: "PV-WORKER-1", name: "Worker board", customer: "Factory",
        project: "No Project", cabinetCount: "1", assignedTo: worker.body.user.id,
      }),
    });
    assert.equal(assignedBoard.response.status, 200);
    const workerAuthorization = { Authorization: `Bearer ${workerLogin.body.token}` };
    const workerWorkspace = await json(baseURL, "/api/sync/workspace", { headers: workerAuthorization });
    const workerProgress = await json(baseURL, "/api/sync/board-progress", {
      method: "POST",
      headers: workerAuthorization,
      body: JSON.stringify({
        expectedVersion: workerWorkspace.body.version,
        boards: [{
          id: assignedBoard.body.board.id,
          cabinetChecklists: [[assignedBoard.body.board.checklist[0].id]],
          personalChecklistItems: [],
        }],
      }),
    });
    assert.equal(workerProgress.response.status, 200);
    assert.equal(workerProgress.body.boards[0].completion, 0);
    const workerStage = await json(baseURL, "/api/board-stage", {
      method: "POST",
      headers: workerAuthorization,
      body: JSON.stringify({ boardID: assignedBoard.body.board.id, stageID: "mechanical" }),
    });
    assert.equal(workerStage.response.status, 200);
    assert.equal(workerStage.body.board.completion, 20);
    const forbiddenFullSync = await json(baseURL, "/api/sync/workspace", {
      method: "POST",
      headers: workerAuthorization,
      body: JSON.stringify({
        expectedVersion: workerProgress.body.version + 1,
        projects: workerProgress.body.projects,
        boards: workerProgress.body.boards,
      }),
    });
    assert.equal(forbiddenFullSync.response.status, 403);

    const websiteState = await json(baseURL, "/api/state", { headers: ownerAuthorization });
    assert.equal(websiteState.response.status, 200);
    assert.deepEqual(websiteState.body.members.map((member) => member.name), ["Owner", "Workshop Worker"]);

    const duplicate = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({
        companyCode: owner.body.company.code,
        inviteCode: invitation.body.invite.code,
        name: "Workshop Worker",
        password: "worker-secret",
      }),
    });
    assert.equal(duplicate.response.status, 400);
  } finally {
    server.stop();
  }
});

test("a worker joins from the invite code alone, with no company code", async () => {
  const server = await startServer();
  const { baseURL } = server;
  try {
    // Two companies, so resolving the invite has to pick the right one rather
    // than just landing on the only company in the database.
    const other = await json(baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Other Electric", name: "Other Owner", password: "owner-secret" }),
    });
    const owner = await json(baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Kittan Electric", name: "Owner", password: "owner-secret" }),
    });
    assert.notEqual(other.body.company.code, owner.body.company.code);

    const invitation = await json(baseURL, "/api/invites", {
      method: "POST",
      headers: { Authorization: `Bearer ${owner.body.token}` },
      body: JSON.stringify({ role: "staff" }),
    });
    assert.equal(invitation.response.status, 200);

    // The website's sign-up form sends the invite code on its own.
    const worker = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({
        inviteCode: invitation.body.invite.code,
        name: "Cold Worker",
        password: "worker-secret",
      }),
    });
    assert.equal(worker.response.status, 200);
    assert.equal(worker.body.user.role, "staff");
    assert.equal(worker.body.company.code, owner.body.company.code);

    // A bad code must not fall through to some other company.
    const bogus = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({ inviteCode: "NOTACODE", name: "Nobody", password: "worker-secret" }),
    });
    assert.equal(bogus.response.status, 400);

    // A revoked invite stops resolving too.
    await json(baseURL, "/api/invite-revoke", {
      method: "POST",
      headers: { Authorization: `Bearer ${owner.body.token}` },
      body: JSON.stringify({ code: invitation.body.invite.code }),
    });
    const revoked = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({
        inviteCode: invitation.body.invite.code,
        name: "Late Worker",
        password: "worker-secret",
      }),
    });
    assert.equal(revoked.response.status, 400);
  } finally {
    server.stop();
  }
});

test("scheme reading is authenticated, guarded, and allowed a document-sized body", async () => {
  // No key on purpose: this exercises the route, the auth gate and the size
  // gate without reaching Gemini. The env is forced rather than inherited so
  // the test behaves the same on a machine that has a key configured.
  const server = await startServer({ GEMINI_API_KEY: "" });
  const { baseURL } = server;
  try {
    const registered = await json(baseURL, "/api/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Kittan Electric", name: "Rawe", password: "secret12" }),
    });
    const login = await json(baseURL, "/api/mobile/login", {
      method: "POST",
      body: JSON.stringify({
        companyCode: registered.body.companyCode,
        name: "Rawe",
        password: "secret12",
      }),
    });
    const authorization = { Authorization: `Bearer ${login.body.token}` };

    const anonymous = await json(baseURL, "/api/ai/board-scheme", {
      method: "POST",
      body: JSON.stringify({ data: "JVBERi0=" }),
    });
    assert.equal(anonymous.response.status, 401);

    const empty = await json(baseURL, "/api/ai/board-scheme", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({}),
    });
    assert.equal(empty.response.status, 400);

    // A scheme PDF is far bigger than the megabyte every other route accepts.
    // Reaching the Gemini check proves the body was not cut off by the size
    // gate on the way in.
    const large = await json(baseURL, "/api/ai/board-scheme", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({
        data: "A".repeat(2_000_000),
        mimeType: "application/pdf",
        fileName: "3918.24-1 MDB.pdf",
      }),
    });
    assert.equal(large.response.status, 503);
    assert.match(large.body.error, /not configured/i);

    // The raised limit belongs to that one route and nowhere else.
    const otherRoute = await json(baseURL, "/api/movements", {
      method: "POST",
      headers: authorization,
      body: JSON.stringify({ partID: "x", kind: "receive", quantity: 1, reference: "A".repeat(2_000_000) }),
    });
    assert.equal(otherRoute.response.status, 400);
    assert.match(otherRoute.body.error, /too large/i);
  } finally {
    server.stop();
  }
});

test("sign-in tells every client the same capabilities, and the Swift copy agrees", async () => {
  const server = await startServer();
  const { baseURL } = server;
  try {
    const registered = await json(baseURL, "/api/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Kittan Electric", name: "Rawe", password: "secret12" }),
    });
    const code = registered.body.companyCode;

    // The phones must be told what they may do, not left to guess from the
    // role name — guessing is what let the apps lock out staff managers.
    const mobile = await json(baseURL, "/api/mobile/login", {
      method: "POST",
      body: JSON.stringify({ companyCode: code, name: "Rawe", password: "secret12" }),
    });
    assert.equal(mobile.response.status, 200);
    assert.deepEqual(mobile.body.can, {
      administer: true, seeCosts: true, signOffQA: true, manageMembers: true,
    });
    assert.equal(mobile.body.roleLabel, "Owner");

    // The browser reads the same block from /api/state.
    const web = await json(baseURL, "/api/login", {
      method: "POST",
      body: JSON.stringify({ companyCode: code, name: "Rawe", password: "secret12" }),
    });
    const cookie = { Cookie: `session=${web.body.token || ""}` };
    const state = await json(baseURL, "/api/state", {
      headers: { Authorization: `Bearer ${mobile.body.token}`, ...cookie },
    });
    assert.deepEqual(state.body.me.can, mobile.body.can);

    // The apps ship the same rules for accounts cached before the server sent
    // them. If server.js and Permissions.swift ever disagree, this fails.
    const swift = fs.readFileSync(
      path.join(webapp, "..", "warehouse", "Sources", "Permissions.swift"), "utf8");
    const setFor = (name) => {
      const line = swift.match(new RegExp(`${name}: \\[([^\\]]*)\\]`));
      return line ? line[1].match(/"([^"]+)"/g).map((s) => s.replace(/"/g, "")).sort() : [];
    };
    assert.deepEqual(setFor("administer"), ["manager", "owner", "staff-manager"]);
    assert.deepEqual(setFor("seeCosts"), ["manager", "owner"]);
    assert.deepEqual(setFor("signOffQA"), ["manager", "owner", "qa", "staff-manager"]);
    assert.match(swift, /manageMembers:\s*role == "owner"/);
    for (const label of ["Owner", "Manager", "Staff Manager", "QA", "Staff"]) {
      assert.ok(swift.includes(`"${label}"`), `Swift is missing the ${label} label`);
    }
  } finally {
    server.stop();
  }
});

test("a board stage moves on the id it was sent, and only a manager deletes a board", async () => {
  const { baseURL, stop } = await startServer();
  try {
    const owner = await json(baseURL, "/api/mobile/company", {
      method: "POST",
      body: JSON.stringify({ companyName: "Stage Works", name: "Owner", password: "secret12" }),
    });
    const manager = { Authorization: `Bearer ${owner.body.token}` };

    const invite = await json(baseURL, "/api/invites", {
      method: "POST", headers: manager, body: JSON.stringify({ role: "staff" }),
    });
    const builder = await json(baseURL, "/api/mobile/join", {
      method: "POST",
      body: JSON.stringify({
        companyCode: owner.body.company.code,
        inviteCode: invite.body.invite.code,
        name: "Builder", password: "builder-secret",
      }),
    });
    const staff = { Authorization: `Bearer ${builder.body.token}` };

    const created = await json(baseURL, "/api/boards", {
      method: "POST", headers: manager,
      body: JSON.stringify({
        number: "3918.26-1", group: "3918.26", name: "Feeder Board",
        customer: "Acme", project: "No Project", type: "MDB",
      }),
    });
    assert.equal(created.response.status, 200);
    const boardID = created.body.board.id;

    // The stage asked for is the stage the board lands on. The website used to
    // send no stageID at all, which reached this route as undefined.
    const moved = await json(baseURL, "/api/board-stage", {
      method: "POST", headers: manager,
      body: JSON.stringify({ boardID, stageID: "wiring" }),
    });
    assert.equal(moved.response.status, 200);
    assert.equal(moved.body.board.currentStage.id, "wiring");

    const noStage = await json(baseURL, "/api/board-stage", {
      method: "POST", headers: manager, body: JSON.stringify({ boardID }),
    });
    assert.equal(noStage.response.status, 400);

    // Deleting is a manager's call, not the builder's.
    const refused = await json(baseURL, "/api/board-delete", {
      method: "POST", headers: staff, body: JSON.stringify({ boardID }),
    });
    assert.equal(refused.response.status, 403);

    const deleted = await json(baseURL, "/api/board-delete", {
      method: "POST", headers: manager, body: JSON.stringify({ boardID }),
    });
    assert.equal(deleted.response.status, 200);

    const after = await json(baseURL, "/api/state", { headers: manager });
    assert.equal(after.body.boards.find((board) => board.id === boardID), undefined);

    const gone = await json(baseURL, "/api/board-delete", {
      method: "POST", headers: manager, body: JSON.stringify({ boardID }),
    });
    assert.equal(gone.response.status, 404);
  } finally {
    stop();
  }
});
