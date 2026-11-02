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
	_check(play.chart.bar_count() > 5, "chart pre-seeds history candles (%d)" % play.chart.bar_count())

	# Day trader flow smoke: 5 sessions, 4 decisions, then summary.
	var dmode: ModeConfig = load("res://src/resources/modes/day_trader.tres")
	var dlevel := LevelGen.make(dmode, 777, market.series)
	var play2: Control = play_script.new()
	play2.with_params({"level": dlevel})
	get_root().add_child(play2)
	await process_frame
	var dflow: RoundFlow = play2.flow
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

	print("── %s ──" % ("SMOKE PASS" if failures == 0 else "%d SMOKE FAILURE(S)" % failures))
	quit(0 if failures == 0 else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		failures += 1
		printerr(" FAIL %s" % label)
