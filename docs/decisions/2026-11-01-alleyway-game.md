# Alleyway — game decisions

Godot game built from the "Afterbell" market-replay concept in `references/learn-stock-trading/`:
a tap-only mobile-first trading game that streams historical SPY price action as a live-looking
line chart and gives the player a short window to tap BUY/SELL.

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| v1 scope | 3 modes: Quick Flip (endless single call), Day Trader (week-long, 5 sessions), Swing (multi-week holds) | One shared chart engine, enough variety to feel like a game | post-launch modes (scalp/blitz, position sizing, leaderboards) |
| Fail state | Bankroll = lives. Run starts $10,000; bust → game over, best records kept | Gives taps real tension; user-confirmed | adding a "practice" no-stakes mode |
| Position model (Day Trader) | Long / Cash / Short at each close | "Do nothing" is a real decision; still one tap, Tab cycles | if three-way choice tests as too fiddly |
| Round pacing | 20–35 s streaming chart + 5–7 s decision window | Bus-stop mobile sessions; difficulty ramps via speed & window size | playtest feedback |
| Progression | Rank ladder unlocks modes: Intern $0 → Broker $12k (Day Trader) → Trader $16k (Swing) → Senior $40k → Fund Mgr $100k → Market Wizard $250k, keyed on best run bankroll; levels are seeded historical windows named by real dates ("Week of Oct 6, 2008") + curated famous weeks | Same seed = same level forever; early unlocks reachable within minutes of Quick Flip | more tickers / content packs; retention data |
| Data universe v1 | Bundle **SPY only** (daily OHLCV 2000–2026, 6,709 bars). Pipeline: drop CSV in `tools/csv/`, run converter, commit generated `.bin` | User choice until multi-ticker ingest is scripted; QQQ/AAPL exports exist for later | ticker-adding script is settled and checked in |
| Language | GDScript | Web export has no C# support in Godot 4; mobile-first single dev | never (web is primary) |
| Engine | Godot 4.7.2-stable, Compatibility renderer | Web is always GL Compatibility; deterministic headless export | Godot minor bumps after testing |
| Web build | **No-threads** variant | GitHub Pages cannot serve COOP/COEP headers | moving to a host that can set headers |
| PWA | Godot's own PWA export (manifest + service worker + apple-touch-icon) + `html/head_include` meta tags for iOS standalone | Native, zero post-processing; offline-capable | custom offline page polish |
| Persistence | `user://` ConfigFile (IndexedDB-backed on web); warn if `OS.is_userfs_persistent()` is false | Browser-native; per-origin | cloud saves / share codes |
| Chart look | Line chart ("LINES") from an OHLC-synthesized deterministic intraday tick path, green/red, gradient fill, volume bars | User asked for live-chart feel; daily data can't replay true minutes, so we synthesize per-bar paths that are reproducible by seed | licensed intraday data arrives |
| Levels | `LevelDef` = (mode, seed) → ticker + start bar + pacing params; curated Hall-of-Fame weeks are fixed seeds | Infinite permutation, shareable/reproducible | level packs beyond curated ones |
| Tests | Headless GDScript smoke tests (data load, seeded determinism, P&L math, save round-trip) run in CI | Guards the "same seed = same level" promise without addon weight | GUT if suite grows |
| Pages deploy | GitHub Actions: download pinned Godot + web templates, headless export to `dist/`, `actions/deploy-pages` | Reproducible, no artifacts in git | custom analytics/host needs |

## Open / deferred
- Sound/haptics — deferred (no assets yet; browsers require first-gesture audio anyway).
- QQQ/AAPL/other tickers — exports exist; **assumed** out of v1 bundle per user.
- Save-export/share-code for records — deferred; note per-origin IndexedDB wipe risk.
- Monetization/ads/leaderboards — none in v1.
