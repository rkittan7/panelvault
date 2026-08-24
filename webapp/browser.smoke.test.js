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

test("an owner can sign up, navigate, and create a project", async ({ page }) => {
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
  expect(failures).toEqual([]);
});
