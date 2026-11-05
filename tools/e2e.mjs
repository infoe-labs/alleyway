// Local dev E2E: boots the exported web build in headless Chromium, drives a
// Quick Flip round (menu via Tab/Enter focus nav, gameplay via Space/Tab),
// and writes screenshots for visual review.
//
//   python3 tools/serve.py dist 8080 &
//   node tools/e2e.mjs
import { createRequire } from "node:module";
import { existsSync, mkdirSync } from "node:fs";

let chromium;
const localRequire = createRequire(import.meta.url);
const localPlaywright = "/home/seong/git/alleyway/references/learn-stock-trading/node_modules/playwright";
if (existsSync(localPlaywright)) {
  chromium = localRequire(localPlaywright).chromium;
} else {
  ({ chromium } = await import("playwright"));
}

const OUT = "/tmp/opencode/e2e";
mkdirSync(OUT, { recursive: true });
const URL = process.argv[2] || "http://localhost:8080/index.html";

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on("console", (m) => {
  if (m.type() === "error") errors.push(m.text());
});
page.on("pageerror", (e) => errors.push(String(e)));

const shot = (name) => page.screenshot({ path: `${OUT}/${name}.png` });
const wait = (ms) => page.waitForTimeout(ms);

await page.goto(URL, { waitUntil: "load", timeout: 60000 });
await page.click("canvas", { position: { x: 210, y: 800 } }).catch(() => {});
await wait(9000); // engine boot
await shot("01-title");

// Title -> mode select: Tab focuses PLAY, Enter activates.
await page.keyboard.press("Tab");
await wait(300);
await page.keyboard.press("Enter");
await wait(1500);
await shot("02-mode-select");

// Mode select -> Quick Flip intro: Tab past back, focus "Open the market".
await page.keyboard.press("Tab"); // back
await page.keyboard.press("Tab"); // open the market
await page.keyboard.press("Enter");
await wait(2000);
await shot("03-intro-card");

// Start the session (Space handled by PlayScreen during INTRO).
await page.keyboard.press("Space");
await wait(2500);
await shot("04-watch");

// Tap the chart to 4x fast-forward the warmup until the decision window.
await page.mouse.click(210, 450);
await page.mouse.click(389, 34); // skip warmup, retain full decision window
await wait(400);
await shot("05-decide");

// CASH is selected by default; Tab selects PUT, Space commits.
await page.keyboard.press("Tab");
await wait(400);
await page.keyboard.press("Space");
await wait(500);
await shot("06-holding");

await page.keyboard.press("x"); // player-controlled exit at the live price
await wait(400);
await shot("07-settle-card");

// Regression: Space on the settle card must start a fresh round (was frozen).
await page.keyboard.press("Space");
await wait(3000);
await shot("08-next-round");

// Fresh round: skip warmup, then tap CALL directly (leftmost pad button).
await page.mouse.click(210, 300); // chart -> 4x
await page.mouse.click(389, 34);
await wait(400);
await page.mouse.click(83, 786); // CALL
await wait(500);
await shot("09-call-tap");
await page.keyboard.press("x");
await wait(400); // manual exit or bracket settlement
await shot("10-settle-2");

// Reload for a clean state, then keyboard-navigate into Day Trader mode
// (focus order on mode select: back, QF open, QF hall, DT open).
await page.reload({ waitUntil: "load" });
await page.click("canvas", { position: { x: 210, y: 800 } }).catch(() => {});
await wait(9000); // engine boot
await page.keyboard.press("Tab");  // PLAY on title
await wait(250);
await page.keyboard.press("Enter");
await wait(1500);
await shot("11-mode-select");
for (let i = 0; i < 4; i++) { await page.keyboard.press("Tab"); await wait(200); }
await page.keyboard.press("Enter"); // Day Trader "Open the market"
await wait(1500);
await shot("12-dt-intro");
await page.keyboard.press("Space"); // START SESSION
await wait(800);

// Finger-drag while the tape streams: popover must appear, FF must NOT toggle.
await page.mouse.move(180, 300);
await page.mouse.down();
await page.mouse.move(300, 320, { steps: 8 });
await wait(600); // held well past the tap threshold
await shot("13a-dt-scrub-watch");
await page.mouse.up();

await page.mouse.click(210, 300); // quick tap -> 4x fast-forward
await wait(5000);
await shot("13-dt-watch");
await page.mouse.click(396, 33); // ">>" if still streaming
await wait(1200);
await shot("14-dt-decide");

// Scrub the crosshair across the day's candles.
await page.mouse.move(230, 300);
await page.mouse.down();
await page.mouse.move(300, 260, { steps: 6 });
await wait(400);
await shot("15-dt-scrub");
await page.mouse.up();

const canvasOk = await page.evaluate(() => {
  const c = document.querySelector("canvas");
  return !!c && c.width > 0;
});

console.log("canvas:", canvasOk ? "ok" : "MISSING");
const realErrors = errors.filter(
  (e) => !/Autoplay|AudioContext|favicon|Service Worker|manifest|WebGL|GPU stall|ERR_|Failed to load resource/i.test(e)
);
// join consecutive ERROR/at: lines for readable stacks
const stacks = [];
for (const e of realErrors) {
  if (e.trimStart().startsWith("at:")) {
    if (stacks.length) stacks[stacks.length - 1] += "\n    " + e.trim();
  } else stacks.push(e.trim());
}
console.log("console errors:", stacks.length);
for (const e of stacks.slice(0, 6)) console.log("  -", e.slice(0, 2000), "\n");
await browser.close();
console.log(stacks.length === 0 && canvasOk ? "E2E OK — screenshots in " + OUT : "E2E saw problems");

if (stacks.length || !canvasOk) process.exitCode = 1;
