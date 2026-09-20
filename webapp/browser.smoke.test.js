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

test("the main breaker card shows the part, its specification and the stage guard holds", async ({ page }) => {
  await page.goto(baseURL, { waitUntil: "networkidle" });
  await page.getByRole("tab", { name: "Sign up", exact: true }).click();
  await page.getByRole("radio", { name: /Start a company/ }).click();
  await page.locator('#signup-create input[name="companyName"]').fill("Breaker Card Panels");
  await page.locator("#form-signup").getByLabel("Name").fill("Card Owner");
  await page.locator("#form-signup").getByLabel("Email").fill("card-owner@example.com");
  await page.locator("#form-signup").getByLabel("Password").fill("browser-secret-12");
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.getByRole("button", { name: "Dashboard" })).toBeVisible();

  const created = await page.request.post(`${baseURL}/api/boards`, {
    data: {
      number: "PV-200-1", name: "Card Board", customer: "Card Customer", project: "No Project",
      manufacturer: "ABB", type: "MDB",
      mainBreakerType: "MCCB", mainBreakerModel: "ABB SACE Tmax XT7", mainBreakerAmpere: "630A",
    },
  });
  expect(created.status()).toBe(200);

  await page.reload({ waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Open Boards", exact: true }).click();
  await page.getByRole("button", { name: /PV-200-1 — Card Board/ }).click();
  await page.locator(".board-property").filter({ hasText: "Main breaker" }).click();

  const card = page.locator(".modal.main-breaker-sheet");
  await expect(card).toBeVisible();
  // The photograph, and the catalog behind the model - not three bare fields.
  const photo = card.locator(".part-hero img");
  await expect(photo).toBeVisible();
  const box = await photo.boundingBox();
  expect(box.height).toBeLessThanOrEqual(240);
  await expect(card).toContainText("Catalog specification");
  await expect(card).toContainText("Installed ampere");
  await expect(card).toContainText("630A");
  await expect(card.getByRole("button", { name: "Open catalog part" })).toBeVisible();
  // The card scrolls; nothing in it may be squeezed under the buttons.
  const overlap = await page.evaluate(() => {
    const sheet = document.querySelector(".modal.main-breaker-sheet");
    const row = sheet.querySelector(".board-drilldown-row");
    return row ? row.getBoundingClientRect().bottom - sheet.querySelector(".actions").getBoundingClientRect().top : -1;
  });
  expect(overlap).toBeLessThanOrEqual(0);
  await page.setViewportSize({ width: 390, height: 900 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect(card.getByRole("button", { name: "Change breaker" })).toBeVisible();
  await card.getByRole("button", { name: "Change breaker" }).click();
  await expect(page.getByRole("button", { name: "Edit selected main breaker" })).toBeVisible();

  // Forward is one click; going back asks first, and a refused prompt changes nothing.
  await page.getByRole("tab", { name: "Overview" }).click();
  const stage = (name) => page.locator(".board-stage").filter({ hasText: name }).first();
  await stage("Mechanical Build").click();
  await expect(page.locator(".board-progress-head h3")).toHaveText("Mechanical Build");
  page.once("dialog", (dialog) => dialog.dismiss());
  await stage("Design").click();
  await expect(page.locator(".board-progress-head h3")).toHaveText("Mechanical Build");
  page.once("dialog", (dialog) => dialog.accept());
  await stage("Design").click();
  await expect(page.locator(".board-progress-head h3")).toHaveText("Design");
});
