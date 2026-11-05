extends SceneTree

## Headless boot smoke: exercise every screen's construction and the core flow
## without a display. Complements run_tests.gd (which covers pure logic).

var failures := 0
var market = null
var game_state = null


func _initialize() -> void:
	print("── Alleyway smoke ──")
	# In -s mode autoload singletons exist under /root but are not registered
	# as compile-time globals, so resolve them by node name.
	await process_frame
	market = root.get_node_or_null("MarketData")
	game_state = root.get_node_or_null("GameState")
	_check(market != null and market.is_ready(), "MarketData autoload ready")
	_check(game_state != null and game_state.RANKS.size() == 6, "ranks defined")

	# Build each screen headlessly and free it.
	for screen_path in [
		"res://src/screens/title_screen.gd",
		"res://src/screens/mode_select.gd",
		"res://src/screens/rank_screen.gd",
	]:
		var script: Script = load(screen_path)
		var node: Control = script.new()
		get_root().add_child(node)
		await process_frame
		var ok := is_instance_valid(node)
		_check(ok, "screen builds: %s" % screen_path.get_file())
		node.free()

	# Play screen with a generated quick-flip level.
	var mode: ModeConfig = load("res://src/resources/modes/quick_flip.tres")
	var level := LevelGen.make(mode, 2026, market.series)
	var play_script: Script = load("res://src/screens/play_screen.gd")
	var play: Control = play_script.new()
	play.with_params({"level": level})
	get_root().add_child(play)
	await process_frame
	_check(is_instance_valid(play) and play.flow != null, "play screen builds + owns flow")

	# Drive the flow through a full quick-flip round.
	play._toggle_pause() # hide intro card state churn
	var flow: RoundFlow = play.flow
	_check(flow.state == RoundFlow.State.INTRO, "flow starts in INTRO")
	flow.continue_decision(RoundRules.LONG) # ignored outside DECIDE
	flow.begin()
	_check(flow.state == RoundFlow.State.WATCH, "WATCH streaming")
	flow.skip_stream()
	_check(flow.state == RoundFlow.State.DECIDE, "skip lands in DECIDE")
	var window_seen := flow.decision_fraction() > 0.0
	_check(window_seen, "decision window armed")
	flow.continue_decision(RoundRules.LONG)
	_check(flow.state == RoundFlow.State.SETTLE, "commit -> SETTLE")
	flow._process(1.0) # post-commit hold starts the reveal session
	_check(flow.state == RoundFlow.State.RESOLVE, "reveal streaming")
	flow.skip_stream() # flush the reveal stream
	_check(flow.settled_results.size() == 1, "one settlement recorded")
	_check(play._overlay.visible, "settle card shown")
	_check(is_finite(flow.bankroll) and flow.bankroll >= 0.0, "bankroll sane: %f" % flow.bankroll)

	# Regression: tapping NEXT CALL must actually begin a new round. The flow
	# sits in SETTLE behind the card; _next_quick_round has to route INTRO->begin.
	play._next_quick_round()
	_check(flow.state == RoundFlow.State.WATCH, "next call begins a fresh quick-flip round")
	_check(play._subtitle_label.text.ends_with(play.level.subtitle), "next call refreshes displayed dates")
	_check(play.chart.bar_count() > 5, "chart pre-seeds history candles (%d)" % play.chart.bar_count())
	_check(play.chart.visible_bars == 30 and not play.chart.intraday,
			"quick flip chart keeps the 30-bar date view")

	# Day trader flow smoke: 5 sessions, 4 decisions, then summary.
	var dmode: ModeConfig = load("res://src/resources/modes/day_trader.tres")
	var dlevel := LevelGen.make(dmode, 777, market.series)
	var play2: Control = play_script.new()
	play2.with_params({"level": dlevel})
	get_root().add_child(play2)
	await process_frame
	var dflow: RoundFlow = play2.flow
	_check(play2.chart.visible_bars == 3 and play2.chart.intraday,
			"day trader chart zooms the live day (clock axis)")
	dflow.begin()
	var decisions := 0
	var guard := 0
	while dflow.state != RoundFlow.State.SUMMARY and guard < 500:
		guard += 1
		match dflow.state:
			RoundFlow.State.WATCH, RoundFlow.State.RESOLVE:
				dflow.skip_stream()
			RoundFlow.State.SETTLE:
				dflow._process(10.0)
			RoundFlow.State.DECIDE:
				decisions += 1
				dflow.continue_decision(RoundRules.LONG)
			_:
				break
	_check(decisions == 4, "day trader makes 4 decisions (got %d)" % decisions)
	_check(dflow.state == RoundFlow.State.SUMMARY, "day trader reaches SUMMARY")
	_check(dflow.settled_results.size() == 4, "day trader settles 4 positions")

	_test_exits(mode, dmode)

	print("── %s ──" % ("SMOKE PASS" if failures == 0 else "%d SMOKE FAILURE(S)" % failures))
	quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		failures += 1
		printerr(" FAIL %s" % label)


func _test_exits(quick: ModeConfig, day: ModeConfig) -> void:
	var swing: ModeConfig = load("res://src/resources/modes/swing.tres")
	for mode in [quick, day, swing]:
		for pos in [RoundRules.LONG, RoundRules.SHORT]:
			var f := RoundFlow.new()
			root.add_child(f)
			f.set_process(false)
			var l := LevelGen.make(mode, 2026, market.series)
			f.setup(l, market.get_series(l.symbol))
			f.begin()
			f.skip_stream()
			f.continue_decision(pos)
			f._process(1.0)
			f._push(f.entries[0] * (1.01 if pos == RoundRules.LONG else 0.99), 0.0, 0, 0, false)
			var expected := float(f.live_position()["bankroll"])
			f.exit_now()
			_check(f.settled_results.size() == 1 and absf(f.bankroll - expected) < 0.01,
				"%s %s: manual exit locks current P&L" % [mode.id, RoundRules.position_label(pos)])
			f.exit_now()
			f.skip_stream()
			_check(f.settled_results.size() == 1 and f.bankroll == expected, "exit cannot settle twice or change during remaining tape")
			if mode != quick:
				f._process(10.0)
				_check(f.state == RoundFlow.State.DECIDE, "early exit preserves next decision")
			f.free()
	# Test both sides and both bracket triggers, including a gap through a stop.
	for pos in [RoundRules.LONG, RoundRules.SHORT]:
		for target in [false, true]:
			var f := RoundFlow.new()
			root.add_child(f)
			f.set_process(false)
			var l := LevelGen.make(quick, 77, market.series)
			f.setup(l, market.get_series(l.symbol))
			f.begin()
			f.skip_stream()
			var entry := f.last_price
			f.set_exit_plan(entry - pos * 1.0, entry + pos * 2.0)
			f.continue_decision(pos)
			f._process(1.0)
			var fill: float = entry + pos * (2.5 if target else -1.5)
			f._push(fill, 0.0, 0, 0, not target)
			_check(f.state == RoundFlow.State.SETTLE and f.settled_results.size() == 1,
				"%s bracket closes on %s" % [RoundRules.position_label(pos), "target" if target else "stop"])
			_check(absf(float(f.settled_results[0]["exit"]) - fill) < 0.001, "bracket fills at observed price, including gaps")
			f.free()

	var streamed := RoundFlow.new()
	root.add_child(streamed)
	streamed.set_process(false)
	var stream_level := LevelGen.make(quick, 99, market.series)
	streamed.setup(stream_level, market.get_series(stream_level.symbol))
	streamed.begin()
	streamed.skip_stream()
	streamed.set_exit_plan(streamed.last_price * 1.5, 0.0)
	streamed.continue_decision(RoundRules.LONG)
	streamed._process(1.0)
	streamed.skip_stream()
	_check(streamed.settled_results.size() == 1 and not streamed._streaming, "bracket interrupts real streaming safely")
	streamed.setup(stream_level, market.get_series(stream_level.symbol))
	streamed.start()
	streamed.begin()
	streamed.skip_stream()
	streamed._process(100.0)
	_check(streamed.positions[0] == RoundRules.CASH and streamed.exit_stop == 0.0, "timeout after reset safely sits out with no stale bracket")
	streamed.free()
