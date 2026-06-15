#!/usr/bin/env node
// Local popup smoke: open a flagged Odoo action on the local serve build and
// FAIL on any client-side error. This is the runtime oracle that confirms what
// check-action-shape.py can only flag statically — it actually dispatches the
// action through the web client, where a malformed act_window dict (e.g. a
// `target:'new'` popup missing `views`) throws in `_preprocessAction`.
//
// The generic part (login + console-error-0 verdict) lives here; the per-popup
// trigger is a small recipe module you pass with --recipe, exporting:
//   export async function run(page) { /* navigate + click to open the popup */ }
//
// Usage (against a running `serve.sh`):
//   ODOO_BASE_URL=http://localhost:8069 \
//   node popup-smoke.mjs --recipe ./recipes/purchase-status.mjs
//
// Env: ODOO_BASE_URL (or ODOO_SERVE_PORT -> http://localhost:PORT),
//      ODOO_LOGIN (default admin), ODOO_PASSWORD (default admin),
//      ODOO_DB (optional; selected on the login page if multiple DBs),
//      SMOKE_SETTLE_MS (default 1500) idle wait after the recipe.
//
// Exit 0 = no client errors (popup is safe). Exit 1 = client error(s) captured
// (real bug) or the recipe/login failed. Evidence (errors + a screenshot path)
// is printed; screenshots go to $TMPDIR, never the repo.

import process from "node:process";
import os from "node:os";
import path from "node:path";

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const recipePath = arg("--recipe", "");
const baseUrl =
  process.env.ODOO_BASE_URL ||
  (process.env.ODOO_SERVE_PORT ? `http://localhost:${process.env.ODOO_SERVE_PORT}` : "");
const login = process.env.ODOO_LOGIN || "admin";
const password = process.env.ODOO_PASSWORD || "admin";
const settleMs = Number(process.env.SMOKE_SETTLE_MS || "1500");

function fail(msg) {
  console.error(`[popup-smoke] ERROR: ${msg}`);
  process.exit(1);
}

if (!baseUrl) fail("set ODOO_BASE_URL (or ODOO_SERVE_PORT) to the local serve URL");
if (!recipePath) fail("pass --recipe <file.mjs> exporting `async run(page)` to open the popup");

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  fail("playwright not installed (run inside a project with ./node_modules playwright)");
}

let recipe;
try {
  recipe = await import(path.resolve(recipePath));
} catch (e) {
  fail(`cannot load recipe ${recipePath}: ${e.message}`);
}
if (typeof recipe.run !== "function") fail(`recipe ${recipePath} must export async run(page)`);

const clientErrors = [];
const CRASH_HINT = /Cannot read properties of undefined|is not a function|_preprocessAction/i;

const browser = await chromium.launch();
const context = await browser.newContext();
const page = await context.newPage();
// Capture the failure modes that escape static checks.
page.on("pageerror", (err) => clientErrors.push(`pageerror: ${err.message}`));
page.on("console", (msg) => {
  if (msg.type() === "error") clientErrors.push(`console.error: ${msg.text()}`);
});

let verdict = 0;
try {
  await page.goto(`${baseUrl}/web/login`, { waitUntil: "domcontentloaded" });
  if (process.env.ODOO_DB) {
    const dbSel = page.locator('select[name="db"]');
    if (await dbSel.count()) await dbSel.selectOption(process.env.ODOO_DB);
  }
  await page.fill('input[name="login"]', login);
  await page.fill('input[name="password"]', password);
  await Promise.all([
    page.waitForLoadState("networkidle"),
    page.click('button[type="submit"]'),
  ]);

  // The recipe opens the specific popup under test.
  await recipe.run(page);
  await page.waitForLoadState("networkidle").catch(() => {});
  await page.waitForTimeout(settleMs);
} catch (e) {
  clientErrors.push(`recipe/nav threw: ${e.message}`);
} finally {
  if (clientErrors.length) {
    verdict = 1;
    const shot = path.join(os.tmpdir(), `popup-smoke-${Date.now()}.png`);
    await page.screenshot({ path: shot, fullPage: false }).catch(() => {});
    console.error(`[popup-smoke] FAIL — ${clientErrors.length} client error(s):`);
    for (const e of clientErrors) {
      const tag = CRASH_HINT.test(e) ? "  >>> " : "      ";
      console.error(`${tag}${e}`);
    }
    console.error(`[popup-smoke] evidence: ${shot}`);
  } else {
    console.log("[popup-smoke] PASS — popup opened with 0 client errors");
  }
  await browser.close();
}

process.exit(verdict);
