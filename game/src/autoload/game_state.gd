extends Node

## Autoload: profile meta — ranks, records, curated badges, persistence.
## user:// maps to IndexedDB on the web export.

const SAVE_PATH := "user://profile.cfg"

const RANKS: Array[Dictionary] = [
	{"name": "Intern", "min": 0.0},
	{"name": "Broker", "min": 15000.0},
	{"name": "Trader", "min": 30000.0},
	{"name": "Senior Trader", "min": 60000.0},
	{"name": "Fund Manager", "min": 120000.0},
	{"name": "Market Wizard", "min": 250000.0},
]

var best_bankroll := 0.0
var total_settlements := 0
var wins := 0
var losses := 0
var streak := 0
var best_streak := 0
var best_run_pct := {}   # mode_id -> float (best % on a completed run)
var curated_stars := {}  # curated_id -> stars
var total_profit := 0.0  # lifetime $ earned across runs

# Transient handoff to screens (mode select -> play -> summary).
var pending_level: LevelDef = null


func _ready() -> void:
	load_profile()


func rank_for(best: float) -> int:
	var idx := 0
	for i in RANKS.size():
		if best >= RANKS[i]["min"]:
			idx = i
	return idx


func rank_index() -> int:
	return rank_for(best_bankroll)


func rank_name() -> String:
	return RANKS[rank_index()]["name"]


func next_rank() -> Dictionary:
	var i := rank_index()
	return RANKS[i + 1] if i + 1 < RANKS.size() else RANKS[i]


func is_unlocked(mode: ModeConfig) -> bool:
	return rank_index() >= mode.unlock_rank


func record_settlement(pnl: float) -> void:
	total_settlements += 1
	total_profit += maxf(pnl, 0.0)
	if pnl > 0.0:
		wins += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
	elif pnl < 0.0:
		losses += 1
		streak = 0
	save_profile()


func record_run_end(mode_id: String, final_bankroll: float, result_pct: float, stars: int, curated_id: String) -> void:
	best_bankroll = maxf(best_bankroll, final_bankroll)
	if result_pct > float(best_run_pct.get(mode_id, -999.0)):
		best_run_pct[mode_id] = result_pct
	if curated_id != "":
		curated_stars[curated_id] = maxi(int(curated_stars.get(curated_id, 0)), stars)
	save_profile()


func reset_profile() -> void:
	best_bankroll = 0.0
	total_settlements = 0
	wins = 0
	losses = 0
	streak = 0
	best_streak = 0
	best_run_pct = {}
	curated_stars = {}
	total_profit = 0.0
	save_profile()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "best_bankroll", best_bankroll)
	cfg.set_value("meta", "total_settlements", total_settlements)
	cfg.set_value("meta", "wins", wins)
	cfg.set_value("meta", "losses", losses)
	cfg.set_value("meta", "streak", streak)
	cfg.set_value("meta", "best_streak", best_streak)
	cfg.set_value("meta", "total_profit", total_profit)
	for k in best_run_pct:
		cfg.set_value("runs", k, best_run_pct[k])
	for k in curated_stars:
		cfg.set_value("curated", k, curated_stars[k])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GameState: could not save profile (err %d)" % err)


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_bankroll = cfg.get_value("meta", "best_bankroll", 0.0)
	total_settlements = cfg.get_value("meta", "total_settlements", 0)
	wins = cfg.get_value("meta", "wins", 0)
	losses = cfg.get_value("meta", "losses", 0)
	streak = cfg.get_value("meta", "streak", 0)
	best_streak = cfg.get_value("meta", "best_streak", 0)
	total_profit = cfg.get_value("meta", "total_profit", 0.0)
	if cfg.has_section("runs"):
		for k in cfg.get_section_keys("runs"):
			best_run_pct[k] = cfg.get_value("runs", k, 0.0)
	if cfg.has_section("curated"):
		for k in cfg.get_section_keys("curated"):
			curated_stars[k] = cfg.get_value("curated", k, 0)


func persistence_ok() -> bool:
	return OS.has_feature("web") == false or OS.is_userfs_persistent()
