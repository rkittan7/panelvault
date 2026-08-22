const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const webapp = __dirname;

async function startServer() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "panelvault-cloud-test-"));
  const child = spawn(process.execPath, ["server.js"], {
    cwd: webapp,
    env: { ...process.env, PORT: "0", DATA_DIR: dataDir },
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

    const assigned = await json(server.baseURL, "/api/board-update", {
      method: "POST", headers,
      body: JSON.stringify({ boardID: createdBoard.body.board.id, assignedTo: registered.body.user.id }),
    });
    assert.equal(assigned.response.status, 200);
    assert.equal(assigned.body.status, "In Progress");
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
    assert.equal(firstCheck.body.status, "In Progress");
    assert.ok(firstCheck.body.completion > 0);

    for (let cabinetIndex = 0; cabinetIndex < 3; cabinetIndex += 1) {
      for (const item of createdBoard.body.board.checklist) {
        if (cabinetIndex === 0 && item.id === createdBoard.body.board.checklist[0].id) continue;
        const checked = await json(server.baseURL, "/api/board-checklist", {
          method: "POST", headers,
          body: JSON.stringify({ boardID: createdBoard.body.board.id, cabinetIndex, itemID: item.id, checked: true }),
        });
        assert.equal(checked.response.status, 200);
      }
    }

    const state = await json(server.baseURL, "/api/state", { headers });
    assert.equal(state.body.projects.length, 1);
    assert.equal(state.body.boards[0].group, "3918.24");
    assert.equal(state.body.boards[0].completion, 100);
    assert.equal(state.body.boards[0].status, "Completed");
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
