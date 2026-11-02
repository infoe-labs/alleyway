class_name RoundFlow
extends Node

## Enum-based round FSM, one machine for all three modes:
##   INTRO -> WATCH -> DECIDE -> RESOLVE -> SETTLE -> (next | DECIDE | card | SUMMARY)
## Quick Flip is the K=2 case; Day Trader / Swing chain K sessions, settling
## one all-in position at each checkpoint. Modes differ only through LevelDef
## parameters — the sequencing below never branches on mode except for pacing
## and the end-of-round card.

signal state_changed(state: int)
signal session_started(index: int, first_price: float, reset_view: bool)
signal tick_pushed(price: float, bar_volume: float, bar: int, tick: int, in_gap: bool)
signal window_opened(seconds: float)
signal decision_progress(fraction: float)
signal position_opened(pos: int, entry_price: float)
signal settled(info: Dictionary)
signal run_finished(reason: String, info: Dictionary)

enum State { INTRO, WATCH, DECIDE, RESOLVE, SETTLE, SUMMARY, GAME_OVER }

const GAP_TICK_SECONDS := 0.04
const AUTO_SETTLE_HOLD := 1.8   # flash the day/segment pnl before the next window
const POST_COMMIT_HOLD := 0.35  # beat showing the position badge before tape resumes

var level: LevelDef
var series: MarketSeries
var tape: Tape
var bankroll := 0.0
var state: State = State.INTRO:
	set(v):
		state = v
		state_changed.emit(v)

var session_idx := 0
var positions: Array[int] = []
var entries: Array[float] = []
var settled_results: Array[Dictionary] = []
var last_price := 0.0
var ff_mult := 1

var _stream_bar := 0
var _stream_to := 0
var _tick := 0
var _in_gap := false
var _gap := PackedFloat32Array()
var _sec_per_tick := 0.02
var _acc := 0.0
var _streaming := false
var _on_run_done: Callable
var _decision_left := 0.0
var _decision_total := 1.0
var _settle_hold := 0.0
var _settle_next := "" # "decide" | "stream" | "card" | "finish"


func setup(p_level: LevelDef, p_series: MarketSeries) -> void:
	level = p_level
	series = p_series
	tape = Tape.new(p_series, level.mode.ticks_per_bar)
	bankroll = level.mode.start_bankroll
	session_idx = 0
	positions.clear()
	entries.clear()
	settled_results.clear()
	_streaming = false
	ff_mult = 1  # each round starts at 1x; the tap-toggle is per round
	_on_run_done = Callable()


func start() -> void:
	state = State.INTRO


func begin() -> void:
	if state == State.INTRO:
		_begin_session(0)


func set_ff(mult: int) -> void:
	ff_mult = clampi(mult, 1, 4)


func skip_stream() -> void:
	# Tap-to-skip: flush the rest of the current stream instantly; the stream's
	# completion callback fires at the end, exactly as if it had played out.
	var guard := 0
	while _streaming and guard < 200_000:
		_advance_tick()
		guard += 1


func decision_fraction() -> float:
	return clampf(_decision_left / _decision_total, 0.0, 1.0)


func _process(delta: float) -> void:
	match state:
		State.WATCH, State.RESOLVE:
			_stream_step(delta)
		State.DECIDE:
			_decision_left -= delta
			decision_progress.emit(decision_fraction())
			if _decision_left <= 0.0:
				_commit(RoundRules.CASH)
		State.SETTLE:
			if _settle_next == "card":
				return  # quick-flip result card: UI drives via next_round()/finish_card()
			_settle_hold -= delta
			if _settle_hold <= 0.0:
				match _settle_next:
					"decide":
						_open_window()
					"stream":
						_begin_session(session_idx + 1)
					"finish":
						_finish_run()
		_:
			pass


# --- streaming ---------------------------------------------------------------

func _begin_session(i: int) -> void:
	session_idx = i
	var reset_view := level.mode.kind == ModeConfig.Kind.DAY_TRADER or i == 0
	var first_bar := level.start_bar if i == 0 else level.checkpoint_bar(i - 1) + 1
	var first_price := series.opens[first_bar]
	session_started.emit(i, first_price, reset_view)

	var speed := level.bar_seconds
	if i > 0 and level.mode.kind == ModeConfig.Kind.QUICK_FLIP:
		speed = level.bar_seconds / maxf(level.reveal_speed, 0.5)
	_start_run(first_bar, level.checkpoint_bar(i), speed, i > 0,
		_open_first_window if i == 0 else _settle_and_maybe_decide)
	state = State.WATCH if i == 0 else State.RESOLVE


func _start_run(from_bar: int, to_bar: int, seconds_per_bar: float, gap_first: bool, done: Callable) -> void:
	_stream_bar = from_bar
	_stream_to = to_bar
	_tick = 0
	_in_gap = gap_first
	_acc = 0.0
	_streaming = true
	_on_run_done = done
	_sec_per_tick = maxf(seconds_per_bar, 0.05) / float(tape.ticks_per_bar)
	if _in_gap:
		_gap = tape.gap_ticks(from_bar - 1)


func _stream_step(delta: float) -> void:
	if not _streaming:
		return
	_acc += delta * ff_mult
	var guard := 0
	while _streaming and _acc >= _current_step_seconds() and guard < 4000:
		_acc -= _current_step_seconds()
		_advance_tick()
		guard += 1


func _current_step_seconds() -> float:
	return GAP_TICK_SECONDS if _in_gap else _sec_per_tick


func _advance_tick() -> void:
	if _in_gap:
		_push(_gap[_tick], series.volumes[maxi(0, _stream_bar - 1)], _stream_bar - 1, _tick, true)
		_tick += 1
		if _tick >= _gap.size():
			_in_gap = false
			_tick = 0
		return
	var ticks := tape.bar_ticks(_stream_bar)
	_push(ticks[_tick], series.volumes[_stream_bar], _stream_bar, _tick, false)
	_tick += 1
	if _tick >= ticks.size():
		if _stream_bar >= _stream_to:
			_streaming = false
			var cb := _on_run_done
			_on_run_done = Callable()
			cb.call()
		else:
			_stream_bar += 1
			_tick = 0
			_in_gap = true
			_gap = tape.gap_ticks(_stream_bar - 1)


func _push(price: float, vol: float, bar: int, tick: int, in_gap: bool) -> void:
	last_price = price
	tick_pushed.emit(price, vol, bar, tick, in_gap)


# --- state transitions ---------------------------------------------------------

func _open_first_window() -> void:
	_open_window()


func _open_window() -> void:
	state = State.DECIDE
	_decision_total = level.decision_seconds
	_decision_left = level.decision_seconds
	window_opened.emit(level.decision_seconds)


func _settle_and_maybe_decide() -> void:
	var i := session_idx
	var info := RoundRules.settle(bankroll, positions[i - 1], entries[i - 1], last_price)
	info["index"] = i - 1
	info["pos"] = positions[i - 1]
	info["entry"] = entries[i - 1]
	info["exit"] = last_price
	info["day"] = i + 1
	bankroll = info["bankroll"]
	settled_results.append(info)
	settled.emit(info)
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.record_settlement(info["pnl"])

	if bankroll <= level.mode.bust_at:
		state = State.GAME_OVER
		run_finished.emit("bust", {"bankroll": bankroll, "settled": settled_results})
		return

	if level.mode.kind == ModeConfig.Kind.QUICK_FLIP:
		_settle_next = "card"
		state = State.SETTLE
	elif i >= level.segments.size() - 1:
		_settle_next = "finish"
		_settle_hold = AUTO_SETTLE_HOLD
		state = State.SETTLE
	else:
		_settle_next = "decide"
		_settle_hold = AUTO_SETTLE_HOLD
		state = State.SETTLE


func continue_decision(pos: int) -> void:
	if state == State.DECIDE:
		_commit(pos)


func _commit(pos: int) -> void:
	positions.append(pos)
	entries.append(last_price)
	position_opened.emit(pos, last_price)
	_settle_next = "stream"
	_settle_hold = POST_COMMIT_HOLD
	state = State.SETTLE


func _finish_run() -> void:
	state = State.SUMMARY
	var pct := bankroll / level.mode.start_bankroll - 1.0
	var stars := RoundRules.stars_for(pct)
	var bench := series.total_return(level.start_bar, level.last_bar())
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.record_run_end(level.mode.id, bankroll, pct, stars, level.curated_id)
	run_finished.emit("summary", {
		"bankroll": bankroll,
		"pct": pct,
		"stars": stars,
		"benchmark": bench,
		"settled": settled_results,
	})
