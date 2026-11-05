extends SceneTree

## Headless smoke tests: run with
##   godot --headless --path game -s res://tests/run_tests.gd
## Covers the contracts that matter: data integrity, seed determinism
## ("same seed = same level"), tape synthesis bounds, and settlement math.

var failures := 0


func _initialize() -> void:
	print("── Alleyway tests ──")
	_test_series()
	_test_rng()
	_test_tape()
	_test_levels()
	_test_rules()
	_test_indicators()
	_test_analysis()
	print("── %s ──" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	quit(0 if failures == 0 else 1)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		failures += 1
		printerr(" FAIL %s" % label)


func _test_series() -> void:
	var spy := MarketSeries.load_from("res://data/SPY.bin")
	check(spy != null, "SPY.bin loads")
	if spy == null:
		return
	check(spy.count() == 6709, "bar count is 6709 (got %d)" % spy.count())
	check(spy.date_of(0) == "2000-01-03", "first bar is 2000-01-03")
	check(absf(spy.closes[0] - 145.4375) < 0.001, "first close is 145.4375")
	var monotonic := true
	for i in range(1, spy.count()):
		if spy.days[i] <= spy.days[i - 1]:
			monotonic = false
	check(monotonic, "dates strictly ascend")
	var lehman := spy.index_for_date("2008-09-15")
	check(lehman > 0 and spy.date_of(lehman) >= "2008-09-15", "index_for_date finds 2008-09-15")
	var beyond := spy.index_for_date("2099-01-01")
	check(beyond == -1, "index_for_date past the end returns -1")
	check(spy.session_clock(0, 24) == "09:30", "session opens 09:30")
	check(spy.session_clock(23, 24) == "16:00", "session closes 16:00")


func _test_rng() -> void:
	var a := SplitMix32.new(42)
	var b := SplitMix32.new(42)
	var same := true
	for i in 100:
		if a.next_int() != b.next_int():
			same = false
	var c := SplitMix32.new(43)
	var d := SplitMix32.new(42)
	var differs := false
	for i in 100:
		if c.next_int() != d.next_int():
			differs = true
	check(same, "splitmix is reproducible")
	check(differs, "different seeds diverge")
	var f := SplitMix32.new(7)
	var in_range := true
	for i in 1000:
		var v := f.next_float()
		if v < 0.0 or v >= 1.0:
			in_range = false
	check(in_range, "next_float in [0,1)")
	check(SplitMix32.new(1).range_i(5, 5) == 5, "range_i degenerate")


func _test_tape() -> void:
	var spy := MarketSeries.load_from("res://data/SPY.bin")
	if spy == null:
		return
	var t1 := Tape.new(spy, 24)
	var t2 := Tape.new(spy, 24)
	var ticks := t1.bar_ticks(1000)
	check(ticks.size() == 24, "bar has 24 ticks")
	var equal := true
	for i in 24:
		if absf(ticks[i] - t2.bar_ticks(1000)[i]) > 0.0:
			equal = false
	check(equal, "tape is deterministic per bar")
	check(absf(ticks[0] - spy.opens[1000]) < 0.0001, "first tick is the open")
	check(absf(ticks[23] - spy.closes[1000]) < 0.0001, "last tick is the close")
	var inside := true
	for i in 24:
		if ticks[i] < spy.lows[1000] - 0.001 or ticks[i] > spy.highs[1000] + 0.001:
			inside = false
	check(inside, "ticks stay inside the bar's range")
	var gap := t1.gap_ticks(1000)
	check(gap.size() == Tape.GAP_TICKS, "gap has GAP_TICKS points")
	var synthetic := MarketSeries.new()
	synthetic.symbol = "TEST"
	synthetic.opens = PackedFloat32Array([100.0])
	synthetic.highs = PackedFloat32Array([110.0])
	synthetic.lows = PackedFloat32Array([90.0])
	synthetic.closes = PackedFloat32Array([105.0])
	var bullish := Tape.new(synthetic, 24).bar_ticks(0)
	synthetic.closes[0] = 95.0
	var bearish := Tape.new(synthetic, 24).bar_ticks(0)
	check(bullish[7] == bearish[7] and bullish[15] == bearish[15], "synthetic high/low order does not reveal future closing direction")
	check(absf(gap[gap.size() - 1] - spy.opens[1001]) < 0.0001, "gap lands on next open")


func _test_levels() -> void:
	var spy := MarketSeries.load_from("res://data/SPY.bin")
	if spy == null:
		return
	var fake := {"SPY": spy}
	var quick: ModeConfig = load("res://src/resources/modes/quick_flip.tres")
	var day: ModeConfig = load("res://src/resources/modes/day_trader.tres")
	var swing: ModeConfig = load("res://src/resources/modes/swing.tres")

	for mode in [quick, day, swing]:
		var a := LevelGen.make(mode, 12345, fake)
		var b := LevelGen.make(mode, 12345, fake)
		check(a.start_bar == b.start_bar and a.segments == b.segments
				and absf(a.decision_seconds - b.decision_seconds) < 0.0001
				and absf(a.bar_seconds - b.bar_seconds) < 0.0001,
				"%s: same seed reproduces level" % mode.id)
		check(a.start_bar >= 0 and a.last_bar() < spy.count(), "%s: level fits inside archive" % mode.id)
		check(a.decision_count() >= 1, "%s: at least one decision" % mode.id)

	var day_l := LevelGen.make(day, 999, fake)
	check(day_l.segments.size() == 5 and day_l.decision_count() == 4, "day trader: 5 sessions, 4 calls")
	var quick_l := LevelGen.make(quick, 999, fake)
	check(quick_l.segments.size() == 2, "quick flip: watch + horizon")

	var distinct := 0
	var prev := -1
	for i in 10:
		var l := LevelGen.make(quick, 1000 + i * 77, fake)
		if l.start_bar != prev:
			distinct += 1
		prev = l.start_bar
	check(distinct >= 8, "seeds explore different dates (%d/10)" % distinct)

	var lehman: Dictionary = LevelGen.CURATED_SPECS[0]
	var curated := LevelGen.make_curated(lehman, day, fake)
	check(curated.display_name.contains("Lehman"), "curated level carries its title")
	check(spy.date_of(curated.start_bar) >= str(lehman["date"]), "curated level starts on or after its date")
	check(LevelGen.curated_for("day_trader").size() >= 4, "hall of fame has day weeks")


func _test_rules() -> void:
	var r := RoundRules.settle(10000.0, RoundRules.LONG, 100.0, 105.0)
	check(absf(float(r["pnl"]) - 500.0) < 0.01, "long +5%% pays 500")
	r = RoundRules.settle(10000.0, RoundRules.SHORT, 100.0, 102.0)
	check(absf(float(r["pnl"]) + 200.0) < 0.01, "short loses on a 2%% rise")
	r = RoundRules.settle(10000.0, RoundRules.SHORT, 100.0, 90.0)
	check(absf(float(r["pnl"]) - 1000.0) < 0.01, "short gains on a 10%% drop")
	r = RoundRules.settle(10000.0, RoundRules.CASH, 100.0, 200.0)
	check(absf(float(r["pnl"])) < 0.001, "cash pays nothing")
	r = RoundRules.settle(10000.0, RoundRules.SHORT, 100.0, 400.0)
	check(float(r["bankroll"]) == 0.0, "short squeeze liquidates at -100%%")
	check(RoundRules.stars_for(0.12) == 3 and RoundRules.stars_for(0.05) == 2
			and RoundRules.stars_for(0.001) == 1 and RoundRules.stars_for(-0.2) == 0,
			"star thresholds")
	check(RoundRules.fmt_money(-1234.5) == "-$1,235" or RoundRules.fmt_money(-1234.5) == "-$1,234",
			"money formats with thousands separator (%s)" % RoundRules.fmt_money(-1234.5))
	check(RoundRules.position_label(RoundRules.LONG) == "CALL"
			and RoundRules.position_label(RoundRules.SHORT) == "PUT"
			and RoundRules.position_label(RoundRules.CASH) == "CASH",
			"position labels read CALL / PUT / CASH")


func _test_indicators() -> void:
	var flat := PackedFloat32Array()
	flat.resize(60)
	flat.fill(50.0)
	var e := Indicators.ema(flat, 9)
	check(is_nan(e[7]) and absf(e[59] - 50.0) < 0.0001, "ema flat holds, NAN before warm-up")

	var src := PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var s := Indicators.sma(src, 3)
	check(is_nan(s[1]) and absf(s[2] - 2.0) < 0.0001 and absf(s[4] - 4.0) < 0.0001,
			"sma window math")

	var ramp := PackedFloat32Array()
	for i in 80:
		ramp.append(float(i))
	var m := Indicators.macd(ramp, 12, 26, 9)
	var ml: PackedFloat32Array = m["macd"]
	var ms: PackedFloat32Array = m["signal"]
	var mh: PackedFloat32Array = m["hist"]
	check(is_finite(ml[79]) and ml[79] > 0.0, "macd positive on a rising ramp")
	check(absf(ml[79] - ms[79] - mh[79]) < 0.0001, "macd hist = line - signal")
	var mf := Indicators.macd(flat, 12, 26, 9)
	var mfl: PackedFloat32Array = mf["macd"]
	check(absf(mfl[59]) < 0.0001, "macd flat is zero")
	var short := Indicators.macd(PackedFloat32Array([1.0, 2.0, 3.0]), 12, 26, 9)
	var sl: PackedFloat32Array = short["macd"]
	check(is_nan(sl[2]), "macd under warm-up is NAN")

	var spy := MarketSeries.load_from("res://data/SPY.bin")
	if spy != null:
		var closes := PackedFloat32Array()
		for i in range(60, 120):
			closes.append(spy.closes[i])
		var bb := Indicators.bollinger(closes, 20, 2.0)
		var bu: PackedFloat32Array = bb["upper"]
		var bm: PackedFloat32Array = bb["mid"]
		var bll: PackedFloat32Array = bb["lower"]
		check(bu[59] > bm[59] and bm[59] > bll[59], "bollinger bands bracket the mean")
		var sma20 := Indicators.sma(closes, 20)
		check(absf(bm[59] - sma20[59]) < 0.0001, "bollinger mid is the sma")

	var up := PackedFloat32Array()
	for i in 40:
		up.append(float(i))
	var ru := Indicators.rsi(up, 14)
	check(is_nan(ru[13]) and absf(ru[39] - 100.0) < 0.0001, "rsi pins at 100 on a straight climb")
	var down := PackedFloat32Array()
	for i in 40:
		down.append(float(40 - i))
	var rd := Indicators.rsi(down, 14)
	check(rd[39] < 0.0001, "rsi bottoms at 0 on a straight slide")
	var zz := PackedFloat32Array()
	for i in 40:
		zz.append(50.0 + (1.0 if i % 2 == 0 else -1.0))
	var rz := Indicators.rsi(zz, 14)
	check(absf(rz[39] - 50.0) < 4.0, "rsi hovers near 50 on even chop (%.1f)" % rz[39])


func _test_analysis() -> void:
	var closes := PackedFloat32Array()
	var highs := PackedFloat32Array()
	var lows := PackedFloat32Array()
	for i in 40:
		closes.append(100.0 + i)
		highs.append(100.5 + i)
		lows.append(99.5 + i)
	var a := TapeAnalysis.read(closes, highs, lows)
	check(int(a["score"]) >= 3 and a["event"].begins_with("Resistance break"), "analysis explains rising trend and observed breakout")
	check(absf(float(a["resistance"]) - 138.5) < 0.001, "resistance excludes forming candle")
	highs[39] = 10000.0
	lows[39] = 0.01
	var b := TapeAnalysis.read(closes, highs, lows)
	check(a["atr"] == b["atr"] and a["support"] == b["support"] and a["resistance"] == b["resistance"], "forming extremes cannot leak into range or bracket sizing")
	closes.reverse()
	highs = closes.duplicate()
	lows = closes.duplicate()
	var bear := TapeAnalysis.read(closes, highs, lows)
	check(int(bear["score"]) <= -3, "falling trend produces PUT lean")
	check(TapeAnalysis.read(PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0])).is_empty(), "analysis waits for warmup")
