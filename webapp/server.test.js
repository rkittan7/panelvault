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
  };
  const customUpload = await json(baseURL, "/api/sync/parts", {
    method: "POST",
    headers: authorization,
    body: JSON.stringify({ customParts: [customPart] }),
  });
  assert.equal(customUpload.response.status, 200);
  assert.equal(customUpload.body.customParts[0].id, customPart.id);
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
