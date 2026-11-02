# PROGRESS — Afterbell

> Status snapshot for a fresh session. Read this plus `docs/decisions/2026-11-01-afterbell-game.md` and you can work on this repo cold.
> Last updated: 2026-11-02. Working tree clean, tests green, live site deployed.

## What this is

**Afterbell** — a mobile-first, tap-to-trade web game built in Godot 4.7.2 (GDScript). It streams real historical SPY daily data as a "live" line chart ("as if looking at charts 3 years ago, in realtime"), gives you a few seconds per bar to go LONG / CASH / SHORT, and tracks your bankroll across Flappy-Bird-simple rounds. Spawns from a failed stock-trading replay project (`references/learn-stock-trading/`, kept read-only for reference).

**Live now:** https://infoe-labs.github.io/alleyway/ (repo `infoe-labs/alleyway`, `gh` CLI authenticated on this machine). PWA/add-to-home-screen works; served by GitHub Pages via CI-built export.

**Done-state:** game fully built, unit tests + smoke + Playwright e2e all green (0 console errors), exported, committed, pushed. CI deploys on every push to `main`. Nothing is blocked. Next work is tuning/content, not architecture.

## Repo map

```
game/                  Godot project (open THIS dir, not repo root)
  project.godot        420x900 portrait, canvas_items/stretch expand, GL Compatibility,
                       autoloads: Main, GameState, MarketData; touch-emulating mouse
  src/main.gd          root scene (main.tscn) + "Main" autoload: screen manager,
                       Main.goto(script: Script, params: Dictionary = {}) — screens are
                       Control scripts .new()'d onto the root window; optional with_params()
  src/autoload/game_state.gd   "GameState": profile meta (rank, records, curated stars),
                       ConfigFile at user://profile.cfg → IndexedDB on web. persistence_ok().
  src/autoload/market_data.gd  "MarketData": loads data/manifest.json → {symbol: MarketSeries}
  src/core/            pure logic, no nodes — the part worth unit-testing:
                       splitmix.gd     SplitMix32 seeded RNG (same seed = same level)
                       market_series.gd packed binary OHLC loader (load_from(path))
                       tape.gd         deterministic OHLC→tick-path synthesis:
                                       O→L→H→C or O→H→L→C per day + overnight gap bridges
                                       (this is what makes daily bars feel like a live tape)
                       level_def.gd    LevelDef: everything a round needs
                       level_gen.gd    LevelGen.make(mode, seed, market) / make_curated(spec, mode, market)
                                       + CURATED_SPECS (Hall-of-Fame historical weeks)
                       mode_config.gd  ModeConfig Resource (Kind: QUICK_FLIP/DAY_TRADER/SWING)
                       round_rules.gd  RoundRules: LONG=1/CASH=0/SHORT=-1, settle(), stars_for(),
                                       fmt_money(), fmt_pct() — static, test directly
  src/game/round_flow.gd  RoundFlow: THE unified round FSM, enum State {INTRO, WATCH, DECIDE,
                       RESOLVE, SETTLE, SUMMARY, GAME_OVER}. All three modes share it; modes
                       differ only by ModeConfig data (Quick Flip = K=2 case). Node-based FSM
                       was considered and rejected (see decision doc).
  src/ui/              ui_theme.gd (class_name UI — palette + theme/widget factories),
                       price_chart.gd (PriceChart, Geometry2D line+fill), decision_bar.gd
  src/screens/         title_screen.gd, mode_select.gd, rank_screen.gd, play_screen.gd
                       (all plain Control scripts, built 100% in code)
  src/resources/modes/*.tres  three ModeConfig resources
  data/                SPY.bin + manifest.json (committed; regenerate via tools/build_data.py)
  web/offline.html     served when offline (copied into export)
  tests/run_tests.gd   headless unit tests   tests/smoke.gd   boots the real scene tree
  export_presets.cfg   Web preset — see "Export gotchas" below
tools/
  build_data.py        CSV → binary pipeline: drop CSV in tools/csv/, edit symbol list, run it,
                       it rewrites game/data/. THIS is how tickers get added.
  make_icons.py        generates the PWA icon set
  serve.py             static server with correct wasm MIME (python http.server doesn't set it)
  e2e.mjs              Playwright e2e (see commands)
docs/decisions/2026-11-01-afterbell-game.md   full decision record — read it
.github/workflows/deploy.yml   CI: downloads Godot 4.7.2 + web templates (cached in ~/godot-cache
                               on the runner), --import, --export-release, actions/deploy-pages
dist/                  local export output — GITIGNORED, purely a local artifact; CI builds its own
references/            old project (venv, node_modules, extra CSVs incl. QQQ/AAPL) — GITIGNORED, never commit
```

## Core design facts (don't re-litigate without reading the decision doc)

- **Input:** only taps, or Tab (cycle BUY/SELL/CASH pad) + Space/Enter (commit), Esc (quit). Handled via direct `KEY_TAB/KEY_SPACE/KEY_ENTER/KEY_ESCAPE` in `play_screen.gd` `_unhandled_input` — deliberately *no* InputMap actions.
- **Gameplay:** all-in staking per position; shorts liquidate at −100%; bust = game over. Rounds are snappy (20–35s). Ranks keyed on *best bankroll ever*: Intern $0 / Broker $12k (unlocks Day Trader) / Trader $16k (unlocks Swing) / Senior $40k / Fund Mgr $100k / Market Wizard $250k. Thresholds were deliberately eased in commit `cf80368` — don't tighten them back.
- **Determinism:** seed + ticker + dates fully determine a level (SplitMix32 everywhere). Keep it that way; tests assert it.
- **Data:** SPY only for now, bundled binary. Multi-ticker = scriptable CSV ingest via `tools/build_data.py` then commit the `.bin`+manifest. `references/learn-stock-trading/data/exports/` has QQQ/AAPL CSVs ready when wanted.
- **UI:** built in code only (single main.tscn). **ASCII-only strings** — the default font lacks ★▶🔒 glyphs (uses `*`, `>`, `<`, `-` instead). Palette/consts on `UI` (e.g. `UI.GREEN`, `UI.tint_button`, `UI.label`).
- **Pause/idle:** pause a round with `flow.set_process(false)` — `tree.paused` does NOT work here (screens are children of the Window, which ignores process mode).

## Commands (verified working on this machine)

```bash
# Unit tests / smoke (fast; both currently ALL PASS / clean):
~/tools/godot/godot --headless --path game -s res://tests/run_tests.gd
~/tools/godot/godot --headless --path game -s res://tests/smoke.gd

# Export (run import first after adding/changing files, else export can use stale cache):
~/tools/godot/godot --headless --path game --import
~/tools/godot/godot --headless --path game --export-release "Web" ../dist/index.html

# Serve + e2e (screenshots land in /tmp/opencode/e2e):
python3 tools/serve.py dist 8080 &        # must be serve.py — correct wasm MIME
node tools/e2e.mjs                          # defaults to http://localhost:8080/index.html
node tools/e2e.mjs https://infoe-labs.github.io/alleyway/   # against the live site

# Add a ticker:
#   put CSV in tools/csv/, update symbol list in tools/build_data.py, run it, commit game/data/
python3 tools/build_data.py
```

Toolchain installed locally: Godot 4.7.2 at `~/tools/godot/godot`; web export templates at `~/.local/share/godot/export_templates/4.7.2.stable/`; Playwright + `chromium_headless_shell-1243` come from `references/learn-stock-trading/node_modules` (e2e.mjs auto-detects it; if missing: `cd references/learn-stock-trading && npx playwright install chromium-headless-shell`).

## Export / PWA gotchas (each of these already bit once)

- `variant/thread_support=false` is **required** — GitHub Pages can't serve COOP/COEP headers.
- Preset **fails silently** if `vram_texture_compression/for_mobile=true` without project setting `textures/vram_compression/import_etc2_astc=true` (both are set correctly now; keep them paired).
- PWA metas go through `html/head_include` in `export_presets.cfg` (mobile-web-app-capable, apple-* tags, theme-color). Icons from `tools/make_icons.py`.
- `include_filter="*.bin,*.json,*.html"` — without it `game/data/` and `web/offline.html` don't ship.
- `tools/serve.py` instead of `python -m http.server`: wasm needs `application/wasm` MIME or the browser refuses to run it.

## GDScript/UI gotchas (verified the hard way)

- Autowrap Labels inside HBox collapse to 1-char width — give them `SIZE_EXPAND_FILL` or set `AUTOWRAP_OFF`.
- In `-s` scripts, autoload identifiers (MarketData, GameState) are NOT compile-time available — use `root.get_node_or_null("MarketData")`.
- No `for k, v in dict` and no `not in` in GDScript — iterate keys, use `not x in` / `has()`.
- `PriceChart` fill polygon needs a `Geometry2D.triangulate_polygon` guard (degenerate polygons crash triangulation).
- Rounded corners fail triangulation on very thin StyleBox fills (see ProgressBar comment in `ui_theme.gd` — square corners there on purpose).

## Deferred / good next steps

- **Run resume** (save mid-run bankroll/position/bar index, "RESUME SESSION" on title). An attempt at this was made and **reverted uncommitted** on 2026-11-02 because it invented APIs (`Profile`, `GameState.goto`, `Money`, run persistence) that don't exist — the committed `title_screen.gd` is the working one. If you build this, persist into `GameState`/`user://` following the existing ConfigFile pattern, and navigate only via `Main.goto(script, params)`.
- **How-to-Play screen** — never built; title screen has no help entry (rules are learnable by playing).
- **More tickers** (QQQ/AAPL CSVs ready in references tree) via the `tools/build_data.py` flow.
- **Sound** — deferred by decision, nothing exists.
- Share codes / level codes — deferred in the decision doc.
- Balance tuning: ranks' pacing, decision-window lengths per mode (`ModeConfig` fields).

## Conventions

- Keep screens plain `Control` scripts built in code, opened via `Main.goto(load("res://src/screens/x.gd"), {...})`; params arrive in `with_params(p: Dictionary)`.
- Keep new pure logic in `src/core/` as `class_name`'d `RefCounted` with static funcs → add cases to `tests/run_tests.gd`.
- Never commit `references/`, `dist/`, `game/.godot/` (already in `.gitignore`).
- Commits so far: `f3fea93` (whole game), `cf80368` (rank easing). Push to `main` = auto-deploy; watch with `gh run list` / `gh run watch`.
