# Alleyway

**▶ [Play now: https://infoe-labs.github.io/alleyway/](https://infoe-labs.github.io/alleyway/)**

*The market, years ago, in realtime — right now.*

A tap-only trading game built in Godot 4.7 that replays real SPY history as a
live-looking tape. You watch the chart stream, then **tap BUY, CASH, or SHORT**
before the clock runs out. Money is the score; going bust ends the run.

Born from `references/learn-stock-trading/`, a local market replay
studio: same OHLCV archive, rebuilt as a mobile-first web game.

## How it plays

- **Quick Flip** — one read of the tape. Watch ~20 s of synthesized live
  price action from a random historical window, then call the next move
  (**BUY / CASH / SHORT**) inside a 5–7 s window. Endless; your bankroll
  carries across calls. Bust → run over.
- **Day Trader** — five sessions, one week. At every close you commit
  overnight: **buy, cash, or short**. Settled at next close.
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
| Place a call | tap BUY / CASH / SHORT | `Tab` switches side, `Space`/`Enter` commits |
| Fast-forward the tape | tap the chart | tap the chart (or `>>` to skip to the decision) |
| Pause | `II` | `Esc` |

Everything else is watching lines go up and down.

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
node tools/e2e.mjs                                         # headless browser (needs playwright)
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
                         DecisionBar (BUY/CASH/SHORT pad), UI theme
  src/screens/           title, mode select (+ Hall of Fame), rank record, play
  tests/                 headless logic tests + UI/flow smoke
tools/                   build_data.py, make_icons.py, serve.py, e2e.mjs
docs/decisions/          decision records (see 2026-11-01-alleyway-game.md)
```

The chart's "live" feel is synthesized: each daily bar becomes a seeded
tick path `open -> (low|high) -> (high|low) -> close` inside the bar's range,
with deterministic bridges across overnight gaps. Same seed on any machine
reproduces every tick, which is what makes levels shareable and tests
meaningful.

## Deployment

Pushing to `main` runs `.github/workflows/deploy.yml`: imports the project,
runs both test suites, exports the no-threads Web build, and publishes `dist/`
to GitHub Pages (Settings → Pages → Source: **GitHub Actions**, one time).

After the first deploy: [https://infoe-labs.github.io/alleyway/](https://infoe-labs.github.io/alleyway/).
