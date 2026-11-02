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
await wait(10000);
await shot("05-decide");

// Tab to switch side, Space to commit.
await page.keyboard.press("Tab");
await wait(400);
await page.keyboard.press("Space");
await wait(1500);
await shot("06-holding");

await wait(6000); // reveal + settle card
await shot("07-settle-card");

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
