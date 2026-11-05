// Assert real input-driven gameplay in the exported Web build.
// npm ci && npx playwright install chromium
// python3 tools/serve.py dist 8080 & npm run test:e2e
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { chromium } from "playwright";

const out = process.env.E2E_OUTPUT || "test-results/browser";
mkdirSync(out, { recursive: true });
const url = new URL(process.argv[2] || "http://localhost:8080/index.html");
url.searchParams.set("e2e", "1");
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: Number(process.env.E2E_WIDTH || 420), height: 900 },
});
await context.tracing.start({ screenshots: true, snapshots: true });
const page = await context.newPage();
const errors = [];
page.on("pageerror", e => errors.push(String(e)));
page.on("console", m => {
  // Ignore only known harmless audio autoplay messages; resource/engine errors fail CI.
  if (m.type() === "error" && !/AudioContext.*(allowed|suspended)|Autoplay/i.test(m.text())) {
    errors.push(m.text());
  }
});
page.on("requestfailed", request => errors.push(`${request.method()} ${request.url()}: ${request.failure()?.errorText}`));
page.on("response", response => {
  if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`);
});
const snapshot = () => page.evaluate(() => window.__alleyway);
const waitFor = async expected => {
  console.log("Expect:", expected);
  await page.waitForFunction(expected => Object.entries(expected).every(
    ([key, value]) => window.__alleyway?.[key] === value,
  ), expected, { timeout: 45000 });
  return snapshot();
};
const clickControl = async key => {
  const state = await snapshot();
  assert.ok(Array.isArray(state[key]), `Missing control: ${key}`);
  await page.mouse.click(...state[key]);
};
const shot = name => page.screenshot({ path: `${out}/${name}.png` });

try {
  const response = await page.goto(url.href, { waitUntil: "load" });
  assert.equal(response.status(), 200);
  await waitFor({ screen: "title_screen" });
  assert.ok(await page.locator("canvas").evaluate(c => c.width > 0 && c.height > 0));
  await shot("01-title");
  await page.keyboard.press("Tab");
  await page.keyboard.press("Enter");
  await waitFor({ screen: "mode_select" });
  await page.keyboard.press("Tab");
  await page.keyboard.press("Tab");
  await page.keyboard.press("Enter");
  await waitFor({ screen: "play_screen", state: "INTRO" });
  await page.keyboard.press("Space");
  await waitFor({ state: "WATCH" });
  await page.keyboard.press("Escape");
  await waitFor({ paused: true });
  await page.keyboard.press("Escape");
  await waitFor({ paused: false });
  await clickControl("_skip_btn");
  await waitFor({ state: "DECIDE" });
  await shot("02-decision");
  // Select manual management so a bracket cannot settle before the exit assertion.
  await clickControl("_plan_picker");
  await waitFor({ plan_open: true });
  await clickControl("manual_plan");
  await waitFor({ plan: 0 });
  await page.keyboard.press("Tab"); // CASH -> PUT
  await page.keyboard.press("Space");
  await waitFor({ state: "RESOLVE", position: -1 });
  await shot("03-put-open");
  await page.keyboard.press("x");
  let state = await waitFor({ state: "SETTLE", settled: 1, exit_reason: "manual exit" });
  assert.ok(Number.isFinite(state.bankroll) && state.bankroll > 0);
  await shot("04-manual-exit");
  await page.keyboard.press("Space");
  await waitFor({ state: "WATCH", settled: 0 });
  await clickControl("_skip_btn");
  await waitFor({ state: "DECIDE" });
  await clickControl("call_button");
  await waitFor({ state: "RESOLVE", position: 1 });
  await clickControl("_exit_button");
  await waitFor({ state: "SETTLE", settled: 1, exit_reason: "manual exit" });
  await shot("05-call-exit");

  // A clean reload exercises browser persistence and Day Trader screen construction.
  await page.reload({ waitUntil: "load" });
  await waitFor({ screen: "title_screen" });
  await page.keyboard.press("Tab");
  await page.keyboard.press("Enter");
  await waitFor({ screen: "mode_select" });
  for (let i = 0; i < 4; i++) await page.keyboard.press("Tab");
  await page.keyboard.press("Enter");
  await waitFor({ screen: "play_screen", state: "INTRO" });
  await page.keyboard.press("Space");
  await waitFor({ state: "WATCH" });
  await clickControl("_skip_btn");
  await waitFor({ state: "DECIDE" });
  await shot("06-day-trader");
  assert.deepEqual(errors, [], "Browser or Godot reported errors");
  console.log("E2E PASS: boot, navigation, pause, PUT/CALL, keyboard/tap exits, next round, reload, Day Trader");
} catch (error) {
  await shot("failure").catch(() => {});
  throw error;
} finally {
  writeFileSync(`${out}/console.json`, JSON.stringify(errors, null, 2));
  writeFileSync(`${out}/state.json`, JSON.stringify((await snapshot().catch(() => null)) ?? null, null, 2));
  await context.tracing.stop({ path: `${out}/trace.zip` });
  await browser.close();
}
