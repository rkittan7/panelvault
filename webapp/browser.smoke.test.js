const { test, expect } = require("@playwright/test");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

let server;
let dataDir;
let baseURL;

test.beforeAll(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "panelvault-browser-test-"));
  server = spawn(process.execPath, ["server.js"], {
    cwd: __dirname,
    env: { ...process.env, PORT: "0", DATA_DIR: dataDir },
    stdio: ["ignore", "pipe", "pipe"],
  });

  baseURL = await new Promise((resolve, reject) => {
    let stderr = "";
    const timer = setTimeout(() => reject(new Error(`Server did not start. ${stderr}`)), 10_000);
    server.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    server.once("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`Server exited with ${code}. ${stderr}`));
    });
    server.stdout.on("data", (chunk) => {
      const match = chunk.toString().match(/localhost:(\d+)/);
      if (!match) return;
      clearTimeout(timer);
      resolve(`http://127.0.0.1:${match[1]}`);
    });
  });
});

test.afterAll(() => {
  server?.kill("SIGTERM");
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true });
});

test("a fresh browser reaches the sign-in screen without runtime errors", async ({ browser }) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  const failures = [];

  page.on("console", (message) => {
    if (message.type() === "error") failures.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => failures.push(`page: ${error.message}`));

  const response = await page.goto(baseURL, { waitUntil: "networkidle" });
  expect(response?.status()).toBe(200);
  await expect(page.getByRole("heading", { name: "PanelVault Cloud" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in", exact: true })).toBeVisible();
  await expect(page.locator("#startup-error")).toBeHidden();
  for (const width of [390, 720, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(page.getByRole("heading", { name: "PanelVault Cloud" })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
  expect(failures).toEqual([]);

  await context.close();
});

test("password recovery dialog has keyboard-safe focus behavior", async ({ page }) => {
  await page.goto(baseURL, { waitUntil: "networkidle" });
  const trigger = page.getByRole("button", { name: "Forgot password?" });
  await trigger.click();
  const dialog = page.getByRole("dialog", { name: "Reset password" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Close dialog" })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused();
});

test("an owner can create work and select the board's actual main breaker", async ({ page }) => {
  const failures = [];
  page.on("console", (message) => {
    if (message.type() === "error") failures.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => failures.push(`page: ${error.message}`));

  await page.goto(baseURL, { waitUntil: "networkidle" });
  await page.getByRole("tab", { name: "Sign up", exact: true }).click();
  await page.getByRole("radio", { name: /Start a company/ }).click();
  await page.locator('#signup-create input[name="companyName"]').fill("Browser Pilot Panels");
  await page.locator("#form-signup").getByLabel("Name").fill("Browser Owner");
  await page.locator("#form-signup").getByLabel("Email").fill("browser-owner@example.com");
  await page.locator("#form-signup").getByLabel("Password").fill("browser-secret-12");
  await page.getByRole("button", { name: "Create account" }).click();

  await expect(page.getByRole("button", { name: "Dashboard" })).toBeVisible();
  await page.getByRole("button", { name: "Open Projects", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Projects", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "New project" }).click();
  await page.getByRole("button", { name: /Enter manually/ }).click();
  await page.getByLabel("Project name").fill("Browser Tower");
  await page.getByRole("textbox", { name: "Customer", exact: true }).fill("Browser Customer");
  await page.getByRole("button", { name: "Create project" }).click();
  await expect(page.getByRole("dialog", { name: "Browser Tower" })).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();

  const createdBoard = await page.request.post(`${baseURL}/api/boards`, {
    data: {
      number: "PV-100-1",
      name: "Browser Main Board",
      customer: "Browser Customer",
      project: "Browser Tower",
      manufacturer: "ABB",
      type: "MDB",
      subtype: "Form 3b",
      mainBreakerType: "MCCB",
      mainBreakerModel: "ABB Tmax XT7",
      mainBreakerAmpere: "630A",
    },
  });
  expect(createdBoard.status()).toBe(200);

  await page.reload({ waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Open Boards", exact: true }).click();
  await page.getByRole("button", { name: /PV-100-1 — Browser Main Board/ }).click();
  const manufacturerLogo = page.locator(".board-property .manufacturer-logo");
  await expect(manufacturerLogo).toHaveCSS("width", "34px");
  await expect(manufacturerLogo).toHaveCSS("height", "34px");

  await page.getByRole("tab", { name: "Main Breaker" }).click();
  await expect(page.getByRole("button", { name: "Edit selected main breaker" })).toContainText("ABB Tmax XT7");
  await page.getByLabel("Search breakers").fill("ATyS r");
  const changeover = page.locator(".main-breaker-choice").filter({ hasText: "ATyS r" }).first();
  await expect(changeover).toBeVisible();
  await changeover.click();
  const editor = page.getByRole("dialog", { name: "Select the actual main breaker" });
  await expect(editor.getByLabel("Main breaker type")).toHaveValue("Changeover Switch");
  await editor.getByLabel("Main breaker ampere").fill("1600A");
  await editor.getByRole("button", { name: "Save main breaker" }).click();
  await expect(page.getByRole("button", { name: "Edit selected main breaker" })).toContainText("ATyS r");
  await expect(page.getByRole("button", { name: "Edit selected main breaker" })).toContainText("1600A");
  await page.setViewportSize({ width: 390, height: 900 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  expect(failures).toEqual([]);
});

test("an administrator can record a signed stock correction from the stock screen", async ({ page }) => {
  await page.goto(baseURL, { waitUntil: "networkidle" });
  await page.getByRole("tab", { name: "Sign up", exact: true }).click();
  await page.getByRole("radio", { name: /Start a company/ }).click();
  await page.locator('#signup-create input[name="companyName"]').fill("Correction Test Panels");
  await page.locator("#form-signup").getByLabel("Name").fill("Correction Owner");
  await page.locator("#form-signup").getByLabel("Email").fill("correction-owner@example.com");
  await page.locator("#form-signup").getByLabel("Password").fill("correction-secret-12");
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.getByRole("button", { name: "Dashboard" })).toBeVisible();

  const createdPart = await page.request.post(`${baseURL}/api/parts`, {
    data: { manufacturer: "Test", type: "Accessory", model: "Correction Widget" },
  });
  expect(createdPart.status()).toBe(200);
  const partID = (await createdPart.json()).part.id;
  const openingStock = await page.request.post(`${baseURL}/api/movements`, {
    data: { partID, kind: "receive", quantity: 10, reference: "Opening count" },
  });
  expect(openingStock.status()).toBe(200);

  await page.reload({ waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Stock", exact: true }).click();
  const stockRow = page.locator("#view-stock .row").filter({ hasText: "Correction Widget" });
  await expect(stockRow).toBeVisible();
  await page.setViewportSize({ width: 390, height: 900 });
  await expect(stockRow.locator(".row-title")).toContainText("Correction Widget");
  await expect(stockRow.getByRole("button", { name: "In", exact: true })).toBeVisible();
  await expect(stockRow.getByRole("button", { name: "Out", exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await stockRow.getByRole("button", { name: "Correction" }).click();

  const dialog = page.getByRole("dialog", { name: "Stock correction" });
  await dialog.getByLabel("Change (+/-)").fill("-3");
  await dialog.getByLabel("Reason / reference").fill("Cycle count");
  await dialog.getByRole("button", { name: "Save correction" }).click();

  await expect(dialog).toBeHidden();
  await expect(stockRow.locator(".qty-col .num").first()).toHaveText("7");
  const state = await (await page.request.get(`${baseURL}/api/state`)).json();
  const correction = state.movements.find((movement) => movement.kind === "adjust");
  expect(correction).toMatchObject({ partID, quantity: -3, reference: "Cycle count" });
});
