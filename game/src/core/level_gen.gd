class_name LevelGen
extends RefCounted

## Seeded level generation. Same (mode, seed) always yields the identical
## LevelDef, which is what makes levels shareable and testable.

const LEHMAN := {"id": "lehman", "date": "2008-09-15", "title": "Lehman Week", "mode": "day_trader"}
const CURATED_SPECS: Array[Dictionary] = [
	LEHMAN,
	{"id": "oct6crash", "date": "2008-10-06", "title": "The Floor Falls Out", "mode": "day_trader"},
	{"id": "covid_bottom", "date": "2020-03-09", "title": "COVID Capitulation", "mode": "day_trader"},
	{"id": "reopen", "date": "2001-09-17", "title": "Markets Reopen", "mode": "day_trader"},
	{"id": "volmageddon", "date": "2018-02-05", "title": "Volmageddon", "mode": "day_trader"},
	{"id": "flash_crash", "date": "2010-05-03", "title": "Flash Crash Week", "mode": "day_trader"},
	{"id": "gfc_recovery", "date": "2009-03-02", "title": "From the Ashes", "mode": "swing"},
	{"id": "dotcom_collapse", "date": "2000-03-13", "title": "The Bubble Bursts", "mode": "swing"},
	{"id": "june_v", "date": "2020-06-01", "title": "The Great V", "mode": "swing"},
	{"id": "debt_ceiling", "date": "2011-07-25", "title": "Debt Ceiling Turbulence", "mode": "swing"},
	{"id": "two_way_tuesday", "date": "2008-10-10", "title": "Two-Way Tuesday", "mode": "quick_flip"},
	{"id": "blooming_thursday", "date": "2020-03-12", "title": "Blooming Thursday", "mode": "quick_flip"},
]


static func curated_for(mode_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in CURATED_SPECS:
		if spec["mode"] == mode_id:
			out.append(spec)
	return out


## Endless procedurally generated level from a seed. `market` is the
## symbol -> MarketSeries dictionary held by the MarketData autoload.
static func make(mode: ModeConfig, seed_value: int, market: Dictionary) -> LevelDef:
	var level := LevelDef.new()
	level.mode = mode
	level.seed_value = seed_value
	var rng := SplitMix32.new((seed_value ^ (int(mode.kind) * 0x51ED2701)) & 0xFFFFFFFF)
	var series := _pick_series(mode, market, rng.next_int())
	if series == null:
		push_error("LevelGen: no loaded series for mode %s" % mode.id)
		return level
	level.symbol = series.symbol

	match mode.kind:
		ModeConfig.Kind.DAY_TRADER:
			_build_day(mode, rng, series, level)
		ModeConfig.Kind.SWING:
			_build_swing(mode, rng, series, level)
		_:
			_build_quick(mode, rng, series, level)

	_apply_pacing(mode, rng, level)
	_apply_name(mode, series, level)
	return level


## Fixed historical level from a curated spec (date-anchored, seeded pacing).
static func make_curated(spec: Dictionary, mode: ModeConfig, market: Dictionary) -> LevelDef:
	var level := LevelDef.new()
	level.mode = mode
	level.is_curated = true
	level.curated_id = spec.id
	level.seed_value = _hash_id(spec.id)
	var rng := SplitMix32.new((level.seed_value ^ (int(mode.kind) * 0x51ED2701)) & 0xFFFFFFFF)
	var series := _pick_series(mode, market, level.seed_value)
	if series == null:
		push_error("LevelGen: no loaded series for curated %s" % spec.id)
		return level
	level.symbol = series.symbol
	level.start_bar = maxi(0, series.index_for_date(spec["date"]))

	match mode.kind:
		ModeConfig.Kind.DAY_TRADER:
			level.segments = []
			for i in mode.sessions:
				level.segments.append(1)
		ModeConfig.Kind.SWING:
			var seg := rng.range_i(mode.segment_bars_min, mode.segment_bars_max)
			level.segments = []
			for i in mode.sessions:
				level.segments.append(seg)
		_:
			level.segments = [rng.range_i(mode.warmup_min, mode.warmup_max), rng.range_i(mode.horizon_min, mode.horizon_max)]

	# Never run past the archive.
	while level.last_bar() >= series.count() - 1 and level.segments.back() > 1:
		level.segments[level.segments.size() - 1] -= 1
	_apply_pacing(mode, rng, level)
	level.display_name = "%s — %s" % [spec.title, series.pretty_date(level.start_bar)]
	level.subtitle = "%s · Hall of Fame" % level.symbol
	return level


static func _build_quick(mode: ModeConfig, rng: SplitMix32, series: MarketSeries, level: LevelDef) -> void:
	var warmup := rng.range_i(mode.warmup_min, mode.warmup_max)
	var horizon := rng.range_i(mode.horizon_min, mode.horizon_max)
	level.segments = [warmup, horizon]
	level.start_bar = _pick_start(rng, series, warmup + horizon, 30)


static func _build_day(mode: ModeConfig, rng: SplitMix32, series: MarketSeries, level: LevelDef) -> void:
	level.segments = []
	for i in mode.sessions:
		level.segments.append(1)
	level.start_bar = _pick_start(rng, series, mode.sessions + 1, 12)


static func _build_swing(mode: ModeConfig, rng: SplitMix32, series: MarketSeries, level: LevelDef) -> void:
	var seg := rng.range_i(mode.segment_bars_min, mode.segment_bars_max)
	level.segments = []
	for i in mode.sessions:
		level.segments.append(seg)
	level.start_bar = _pick_start(rng, series, seg * mode.sessions, 25)


static func _pick_series(mode: ModeConfig, market: Dictionary, seed_value: int) -> MarketSeries:
	var available: Array[String] = []
	for s in mode.symbols:
		if market.has(s):
			available.append(s)
	if available.is_empty():
		return null
	return market[available[seed_value % available.size()]]


static func _pick_start(rng: SplitMix32, series: MarketSeries, needed: int, history_pad: int) -> int:
	var lo := history_pad
	var hi := series.count() - 1 - needed
	if hi < lo:
		return lo
	return rng.range_i(lo, hi)


static func _apply_pacing(mode: ModeConfig, rng: SplitMix32, level: LevelDef) -> void:
	level.bar_seconds = rng.range_f(mode.bar_seconds * 0.88, mode.bar_seconds * 1.12)
	level.decision_seconds = rng.range_f(mode.decision_seconds * 0.85, mode.decision_seconds * 1.15)
	level.reveal_speed = mode.reveal_speed_mult


static func _apply_name(mode: ModeConfig, series: MarketSeries, level: LevelDef) -> void:
	var prev_vol := series.realized_vol(maxi(0, level.start_bar - 12), maxi(1, level.start_bar - 1))
	var vc := MarketSeries.vol_class(prev_vol)
	match mode.kind:
		ModeConfig.Kind.DAY_TRADER:
			level.display_name = "Week of %s" % series.pretty_date(level.start_bar)
			level.subtitle = "%s · %s Week" % [level.symbol, vc]
		ModeConfig.Kind.SWING:
			level.display_name = "%s -> %s" % [series.month_year(level.start_bar), series.month_year(level.last_bar())]
			level.subtitle = "%s · %s Swing" % [level.symbol, vc]
		_:
			level.display_name = "%s · %s Session" % [level.symbol, vc]
			level.subtitle = "%s -> %s" % [
				series.pretty_date(level.start_bar),
				series.pretty_date(level.checkpoint_bar(0)),
			]


static func _hash_id(id: String) -> int:
	var h := 0x811C9DC5
	for b in id.to_utf8_buffer():
		h = h ^ int(b)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h
