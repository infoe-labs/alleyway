class_name PlayScreen
extends Control

## The single in-game screen. HUD on top, the chart fills the middle, the tap
## pad sits at the bottom. Overlay cards handle intro / settle / summary / bust
## / pause. All game logic lives in RoundFlow; this screen is presentation.
##
## Pause is implemented by freezing the flow node directly rather than
## tree.paused, because this screen and its overlay need input while paused.

var level: LevelDef
var flow: RoundFlow
var chart: PriceChart

var _bankroll_label: Label
var _info_label: Label
var _pos_badge: Label
var _decision_bar: DecisionBar
var _pause_btn: Button
var _skip_btn: Button
var _overlay: ColorRect
var _card: PanelContainer
var _card_box: VBoxContainer
var _paused := false
var _quick_carry := 0.0
var _last_settled: Dictionary = {}


func with_params(p: Dictionary) -> void:
	level = p["level"]
	_quick_carry = float(p.get("carry_bankroll", 0.0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(side, 12)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)

	# --- top bar ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.custom_minimum_size = Vector2(48, 44)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_toggle_pause)
	top.add_child(_pause_btn)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	var lvl_lbl := UI.label(level.display_name, 17)
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(lvl_lbl)
	var sub_lbl := UI.label("%s · %s" % [level.mode.display_name, level.subtitle], 12, UI.TEXT_DIM)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_lbl.clip_text = true
	title_box.add_child(sub_lbl)
	_bankroll_label = UI.label(RoundRules.fmt_money(_starting_bankroll()), 22)
	_bankroll_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bankroll_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bankroll_label.custom_minimum_size = Vector2(110, 0)
	_bankroll_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bankroll_label.clip_text = true
	top.add_child(_bankroll_label)
	_skip_btn = Button.new()
	_skip_btn.text = ">>"
	_skip_btn.tooltip_text = "Skip to decision"
	_skip_btn.custom_minimum_size = Vector2(48, 44)
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.pressed.connect(func() -> void: flow.skip_stream())
	top.add_child(_skip_btn)

	# --- info / position row ---
	var info_row := HBoxContainer.new()
	col.add_child(info_row)
	_info_label = UI.label("", 13, UI.TEXT_DIM)
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info_label.custom_minimum_size = Vector2(140, 22)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_label.clip_text = true
	info_row.add_child(_info_label)
	_pos_badge = UI.label("", 14, UI.CASH_BLUE)
	_pos_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pos_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pos_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pos_badge.clip_text = true
	info_row.add_child(_pos_badge)

	# --- chart ---
	chart = PriceChart.new()
	chart.configure(level.mode.ticks_per_bar)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.gui_input.connect(_on_chart_input)
	col.add_child(chart)

	# --- decision pad ---
	_decision_bar = DecisionBar.new(level.mode.allow_cash)
	_decision_bar.committed.connect(func(pos: int) -> void: flow.continue_decision(pos))
	col.add_child(_decision_bar)

	# --- overlay card ---
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var card_center := CenterContainer.new()
	card_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(card_center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(340, 0)
	card_center.add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 10)
	_card.add_child(_card_box)

	# --- flow ---
	flow = RoundFlow.new()
	add_child(flow)
	flow.state_changed.connect(_on_state_changed)
	flow.session_started.connect(_on_session_started)
	flow.tick_pushed.connect(_on_tick)
	flow.window_opened.connect(_on_window_opened)
	flow.decision_progress.connect(func(f: float) -> void: _decision_bar.set_time_left(f))
	flow.position_opened.connect(_on_position_opened)
	flow.settled.connect(_on_settled)
	flow.run_finished.connect(_on_run_finished)

	flow.setup(level, MarketData.get_series(level.symbol))
	if _quick_carry > 0.0:
		flow.bankroll = _quick_carry
		flow.begin()  # continuation round: skip the intro card
	else:
		flow.start()
		_show_intro()


func _starting_bankroll() -> float:
	return _quick_carry if _quick_carry > 0.0 else level.mode.start_bankroll


# --- cards -------------------------------------------------------------------

func _clear_card() -> void:
	# Remove immediately (not just queue_free) so the panel never measures
	# the outgoing card's children alongside the new ones.
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()


func _show_card() -> void:
	_overlay.visible = true


func _hide_card() -> void:
	_overlay.visible = false


func _card_button(text: String, cb: Callable, accent: Color = UI.PANEL_LIGHT) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.focus_mode = Control.FOCUS_NONE
	if accent != UI.PANEL_LIGHT:
		UI.tint_button(b, accent)
	b.pressed.connect(cb)
	_card_box.add_child(b)


func _show_intro() -> void:
	_clear_card()
	_card_box.add_child(UI.label(level.mode.display_name.to_upper(), 13, UI.GOLD))
	_card_box.add_child(UI.label(level.display_name, 22))
	_card_box.add_child(UI.label(level.subtitle, 14, UI.TEXT_DIM))
	_card_box.add_child(UI.label("Bankroll %s" % RoundRules.fmt_money(_starting_bankroll()), 16))
	if level.mode.allow_cash:
		_card_box.add_child(UI.label(
			"Before each night, decide the move: BUY rides it up, SHORT profits from the fall, CASH sits it out.",
			14, UI.TEXT_DIM, true))
	_card_box.add_child(UI.label("seed #%d" % level.seed_value, 11, UI.TEXT_DIM))
	var hint := "Tap BUY / SHORT" + (" / CASH" if level.mode.allow_cash else "") + "\nTab switches - Space commits"
	_card_box.add_child(UI.label(hint, 13, UI.TEXT_DIM))
	_card_button("START SESSION", func() -> void:
		_hide_card()
		flow.begin())
	_show_card()


func _show_settle_card(info: Dictionary) -> void:
	_clear_card()
	var pnl := float(info["pnl"])
	var color := UI.GREEN if pnl > 0 else (UI.RED if pnl < 0 else UI.TEXT_DIM)
	_card_box.add_child(UI.label("CALL SETTLED", 13, UI.GOLD))
	_card_box.add_child(UI.label("%s  @  %.2f -> %.2f" % [RoundRules.position_label(int(info["pos"])),
			float(info["entry"]), float(info["exit"])], 14, UI.TEXT_DIM))
	_card_box.add_child(UI.label("%s  (%s)" % [RoundRules.fmt_money(pnl), RoundRules.fmt_pct(float(info["ret"]))], 26, color))
	_card_box.add_child(UI.label("Bankroll %s" % RoundRules.fmt_money(flow.bankroll), 16))
	_card_button("NEXT CALL >", _next_quick_round, UI.GREEN_DARK)
	_card_button("CASH OUT", _back_to_select)
	_show_card()


func _show_summary(info: Dictionary) -> void:
	_clear_card()
	var pct := float(info["pct"])
	var stars := int(info["stars"])
	var kind_title := "WEEK COMPLETE" if level.mode.kind == ModeConfig.Kind.DAY_TRADER else "SWING COMPLETE"
	if level.is_curated:
		kind_title = "HALL OF FAME · " + kind_title
	_card_box.add_child(UI.label(kind_title, 13, UI.GOLD))
	_card_box.add_child(UI.label(level.display_name, 20))
	_card_box.add_child(UI.label("*".repeat(stars) + "·".repeat(3 - stars), 30, UI.GOLD))
	var color := UI.GREEN if pct > 0 else (UI.RED if pct < 0 else UI.TEXT_DIM)
	_card_box.add_child(UI.label("%s   (%s)" % [RoundRules.fmt_money(float(info["bankroll"])), RoundRules.fmt_pct(pct)], 22, color))
	_card_box.add_child(UI.label("Buy & hold was %s over the same stretch" % RoundRules.fmt_pct(float(info["benchmark"])), 13, UI.TEXT_DIM, true))
	for r in info["settled"]:
		var ret := float(r["ret"])
		var line := "Day %d · %s · %s" % [int(r["day"]), RoundRules.position_label(int(r["pos"])), RoundRules.fmt_pct(ret)]
		_card_box.add_child(UI.label(line, 13, UI.GREEN if ret > 0 else (UI.RED if ret < 0 else UI.TEXT_DIM)))
	_card_button("BACK TO FLOOR", _back_to_select, UI.GREEN_DARK)
	_show_card()


func _show_game_over(info: Dictionary) -> void:
	_clear_card()
	_card_box.add_child(UI.label("MARGIN CALL", 13, UI.RED))
	_card_box.add_child(UI.label("You're out.", 26))
	_card_box.add_child(UI.label("Bankroll hit %s. The market always collects." % RoundRules.fmt_money(float(info["bankroll"])), 14, UI.TEXT_DIM, true))
	_card_button("BACK TO FLOOR", _back_to_select, UI.RED_DARK)
	_show_card()


func _show_pause() -> void:
	_clear_card()
	_card_box.add_child(UI.label("PAUSED", 20, UI.GOLD))
	_card_button("RESUME", _toggle_pause)
	_card_button("QUIT SESSION", _back_to_select)
	_show_card()


# --- flow callbacks ------------------------------------------------------------

func _on_state_changed(state: int) -> void:
	_skip_btn.visible = state in [RoundFlow.State.WATCH, RoundFlow.State.RESOLVE]
	match state:
		RoundFlow.State.DECIDE:
			_info_label.text = "DECIDE NOW"
			_info_label.add_theme_color_override("font_color", UI.GOLD)
		RoundFlow.State.SETTLE:
			if level.mode.kind == ModeConfig.Kind.QUICK_FLIP and not _last_settled.is_empty():
				_show_settle_card(_last_settled)
		RoundFlow.State.SUMMARY, RoundFlow.State.GAME_OVER:
			_decision_bar.close_window()


func _on_session_started(index: int, first_price: float, reset_view: bool) -> void:
	if reset_view:
		chart.reset()
		chart.session_start_price = first_price
		_pos_badge.text = ""
		_bankroll_label.add_theme_color_override("font_color", UI.TEXT)
		var first_bar := level.start_bar if index == 0 else level.checkpoint_bar(index - 1) + 1
		var s := series()
		chart.seed_history(s, maxi(0, first_bar - PriceChart.HIST_BARS), first_bar - 1)
	else:
		chart.session_start_price = first_price
		chart.refresh_view(true)
		chart.queue_redraw()


func _on_tick(price: float, vol: float, bar: int, tick: int, in_gap: bool) -> void:
	chart.push(price, vol, bar, tick, in_gap)
	if in_gap:
		_info_label.text = ">> OVERNIGHT"
	elif level.mode.kind == ModeConfig.Kind.DAY_TRADER:
		_info_label.text = "DAY %d/%d · %s" % [flow.session_idx + 1, level.mode.sessions,
				MarketSeries.session_clock(tick, level.mode.ticks_per_bar)]
	else:
		_info_label.text = series().date_of(bar)


func _on_window_opened(_seconds: float) -> void:
	_decision_bar.open_window(level.decision_seconds)
	_pos_badge.text = ""


func _on_position_opened(pos: int, entry: float) -> void:
	_decision_bar.close_window()
	_pos_badge.text = "%s @ %.2f" % [RoundRules.position_label(pos), entry]
	_pos_badge.add_theme_color_override("font_color",
		UI.GREEN if pos == RoundRules.LONG else (UI.RED if pos == RoundRules.SHORT else UI.CASH_BLUE))
	if pos != RoundRules.CASH:
		chart.set_entry(entry, "%s @ %.2f" % [RoundRules.position_label(pos), entry])
	else:
		chart.set_entry(-1.0, "")


func _on_settled(info: Dictionary) -> void:
	_last_settled = info
	_bankroll_label.text = RoundRules.fmt_money(flow.bankroll)
	var pnl := float(info["pnl"])
	var color := UI.GREEN if pnl > 0 else (UI.RED if pnl < 0 else UI.TEXT_DIM)
	_pos_badge.text = "%s (%s)" % [RoundRules.fmt_money(pnl), RoundRules.fmt_pct(float(info["ret"]))]
	_pos_badge.add_theme_color_override("font_color", color)
	_bankroll_label.add_theme_color_override("font_color", color)
	chart.set_entry(-1.0, "")
	# Quick-flip runs are endless: keep the record hot after every call.
	if level.mode.kind == ModeConfig.Kind.QUICK_FLIP:
		var pct := flow.bankroll / level.mode.start_bankroll - 1.0
		GameState.record_run_end(level.mode.id, flow.bankroll, pct, 0, "")


func _on_run_finished(reason: String, info: Dictionary) -> void:
	if reason == "bust":
		_show_game_over(info)
	else:
		_show_summary(info)


# --- quick flip endless ------------------------------------------------------------

func _next_quick_round() -> void:
	_hide_card()
	_last_settled = {}
	var carry := flow.bankroll
	level = LevelGen.make(level.mode, randi(), MarketData.series)
	flow.setup(level, series())
	flow.bankroll = carry
	# setup() keeps the machine parked in SETTLE after the card; begin() only
	# fires from INTRO, so route through start() or the round never begins.
	flow.start()
	flow.begin()


func series() -> MarketSeries:
	return MarketData.get_series(level.symbol)


# --- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _paused:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
		return
	match event.keycode:
		KEY_TAB:
			if flow.state == RoundFlow.State.DECIDE:
				_decision_bar.cycle()
				accept_event()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			accept_event()
			match flow.state:
				RoundFlow.State.INTRO:
					_hide_card()
					flow.begin()
				RoundFlow.State.DECIDE:
					_decision_bar.commit_selected()
				RoundFlow.State.SETTLE:
					if level.mode.kind == ModeConfig.Kind.QUICK_FLIP and _overlay.visible:
						_next_quick_round()
		KEY_ESCAPE:
			if flow.state != RoundFlow.State.INTRO:
				_toggle_pause()


func _on_chart_input(event: InputEvent) -> void:
	# Tapping the tape fast-forwards while watching — the other half of the
	# one-thumb design. Decision taps go to the pad buttons only.
	if event is InputEventScreenTouch and event.pressed:
		if flow.state in [RoundFlow.State.WATCH, RoundFlow.State.RESOLVE]:
			flow.set_ff(4 if flow.ff_mult == 1 else 1)


func _toggle_pause() -> void:
	_paused = not _paused
	flow.set_process(not _paused)
	if _paused:
		_show_pause()
	else:
		_hide_card()


func _process(_delta: float) -> void:
	# Auto-pause when the tab loses focus (browsers throttle hidden tabs).
	if not _paused and flow != null \
			and flow.state in [RoundFlow.State.WATCH, RoundFlow.State.RESOLVE, RoundFlow.State.DECIDE] \
			and not get_tree().root.has_focus():
		_toggle_pause()


func _back_to_select() -> void:
	if _paused:
		_toggle_pause()
	Main.goto(load("res://src/screens/mode_select.gd"))
