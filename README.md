# Alleyway

**▶ [Play now: https://infoe-labs.github.io/alleyway/](https://infoe-labs.github.io/alleyway/)**

*The market, years ago, in realtime — right now.*

A tap-only trading game built in Godot 4.7 that replays real SPY history as a
live-looking tape. You watch the chart stream, then **tap CALL, CASH, or PUT**
before the clock runs out. Money is the score; going bust ends the run.

Born from `references/learn-stock-trading/`, a local market replay
studio: same OHLCV archive, rebuilt as a mobile-first web game.

## How it plays

- **Quick Flip** — one read of the tape. Watch ~20 s of synthesized live
  price action from a random historical window, then call the next move
  (**CALL / CASH / PUT**) inside a roughly 9–14 s window. Endless; your bankroll
  carries across calls. Bust → run over.
- **Day Trader** — five sessions, one week. At every close you commit
  overnight: **call, cash, or put**. Settled at next close.
- **Swing Trader** — months compressed to minutes, rebalance at each
  checkpoint.
- **Hall of Fame** — curated famous weeks (Lehman, COVID capitulation,
  Flash Crash…) as fixed-seed levels with star records.

Levels are `(mode, seed)` → date + pacing + horizons, so procedural content is
endless yet reproducible: the same seed is the same level forever. Ranks
(Intern → Market Wizard) are pure honors earned from your best bankroll —
every mode is playable from the start.

### Controls

| Action | Mobile | Keyboard |
|---|---|---|
| Place a call | tap CALL / CASH / PUT | `Tab` switches side, `Space`/`Enter` commits |
| Fast-forward the tape | tap the chart | tap the chart (or `>>` to skip to the decision) |
| Pause | `II` | `Esc` |
| Exit an open trade | tap EXIT NOW | `X` |

The live read explains EMA9/EMA21 alignment, slope, RSI, crossovers, and breaks
of the previous 14 candles' support/resistance. It uses observed candles only;
the current forming candle does not set its own range levels.

Before entering, choose manual exits or a bracket: a stop one observed average
true range away and a target twice that distance, or a wider 1.5x/3x plan.
Levels freeze at entry. You can override either plan with EXIT NOW. Stops and
targets fill at the observed tick, so gaps can pass the requested level. Trades
still open at the final checkpoint settle there. Early exits in Day/Swing leave
you in cash until the next scheduled decision.

CALL and PUT are directional game positions using the original bankroll return
math; there are no option premiums or expiry pricing. Quick Flip shows live
P&L, profitable-call counts, win streaks, and best open gain versus realized
return so you can work on exit timing. Its reveal runs at a controllable pace
and resets fast-forward on entry.

## Run / build locally

Requires Godot 4.7.2 (standard build) with web export templates.

```sh
# 1. Rebuild market data (only needed when tools/csv/*.csv changes)
python3 tools/build_data.py        # -> game/data/SPY.bin + manifest.json
python3 tools/make_icons.py        # -> PWA icons

# 2. Export the web build (or open game/ in the editor to iterate)
godot --headless --path game --import
godot --headless --path game --export-release "Web" ../dist/index.html

# 3. Serve with correct wasm MIME type
python3 tools/serve.py dist 8080   # http://localhost:8080/index.html
```

Tests (also run in CI):

```sh
godot --headless --path game -s res://tests/run_tests.gd   # logic contracts
godot --headless --path game -s res://tests/smoke.gd       # screens + flow
npm ci && npx playwright install chromium
# In a separate terminal: python3 tools/serve.py dist 8080
npm run test:e2e                                          # real browser gameplay assertions
```

## Web / PWA / mobile install

- Built with the **no-threads** web template — GitHub Pages can't send the
  COOP/COEP headers SharedArrayBuffer would need.
- Godot's PWA export generates `manifest.json` + `service_worker.js`, so the
  game installs offline:
  - **Android**: Chrome → menu → *Add to home screen*.
  - **iOS**: Safari → Share → *Add to Home Screen* (fullscreen, standalone,
    `apple-touch-icon` included via `html/head_include`).
- `user://` saves (ranks, records, badges) live in IndexedDB; private-tabs
  won't persist them (the title screen warns).

## Adding tickers

The game loads whatever the manifest lists. To add a symbol:

1. Drop a provider CSV (`SYMBOL_1d_....csv` with `date,open,high,low,close,volume`)
   into `tools/csv/`.
2. `python3 tools/build_data.py` — regenerates `game/data/` (commit the `.bin`).
3. Add the symbol to a mode's `symbols` list in `game/src/resources/modes/*.tres`.

v1 ships SPY only (2000→2026 daily, 6,709 bars, from the original project's
split-adjusted Yahoo archive). QQQ/AAPL exports already exist in the old
project's `data/exports/` if you want to extend the game.

## Architecture (Godot side)

```
game/
  src/main.gd            autoload screen manager (theme + goto)
  src/autoload/          GameState (profile, ranks, save) · MarketData (archives)
  src/core/              MarketSeries · Tape (OHLC -> deterministic ticks) · Indicators
                         LevelGen/LevelDef (seeded levels) · RoundRules (settle math)
  src/game/round_flow.gd enum FSM: INTRO>WATCH>DECIDE>RESOLVE>SETTLE>... shared by all modes
  src/ui/                PriceChart (candles + grid-locked tape, EMA/BB, volume, MACD),
                         DecisionBar (CALL/CASH/PUT pad), UI theme
  src/screens/           title, mode select (+ Hall of Fame), rank record, play
  tests/                 headless logic tests + UI/flow smoke
tools/                   build_data.py, make_icons.py, serve.py, e2e.mjs
docs/decisions/          decision records (see 2026-11-01-alleyway-game.md)
```

The chart's "live" feel is synthesized: each daily bar becomes a seeded
tick path `open -> (low|high) -> (high|low) -> close` inside the bar's range,
with deterministic bridges across overnight gaps. High/low order is seeded
independently of the closing direction, avoiding a synthetic tell. Same seed on any machine
reproduces every tick, which is what makes levels shareable and tests
meaningful.

## CI and deployment

Pull requests to `main` run `.github/workflows/ci.yml`:

- **Workflow and data checks**: actionlint, Python/shell syntax, and rebuilding
  the market archive to verify committed data matches its CSV source.
- **Godot tests and web export**: import, logic tests, screen/flow tests, and
  release export using Godot 4.7.2. The runner checks log errors as well as exit
  codes and requires each test suite's success marker.
- **Browser gameplay checks (420px / 1280px)**: Chromium boots the exported
  build and asserts navigation, pause/resume, CALL/PUT entries, keyboard/tap
  exits, next-round behavior, reload, and Day Trader navigation. Failed network
  requests and browser/engine errors fail the check.

Runs retain Godot logs, browser screenshots, console output, and Playwright
traces for seven days. Browser assertions use read-only state snapshots enabled
only by `?e2e=1`; all actions still use real keyboard/mouse input. Browser
packages are locked in `package-lock.json`. Actions are pinned to commit SHAs,
with weekly Dependabot updates for Actions and browser dependencies.

The deployment workflow calls this same CI workflow on `main` and publishes
its tested `web-build` artifact only after all checks pass. PRs have read-only
repository permissions; Pages/OIDC permissions belong only to the deployment
job. Manual deployment is restricted to `main`.

To enforce these checks before merging, select the named checks above in the
repository's branch protection/ruleset for `main`.


Pushing to `main` runs `.github/workflows/deploy.yml`, validates the release,
and publishes it to GitHub Pages (Settings → Pages → Source: **GitHub Actions**, one time).

After the first deploy: [https://infoe-labs.github.io/alleyway/](https://infoe-labs.github.io/alleyway/).
