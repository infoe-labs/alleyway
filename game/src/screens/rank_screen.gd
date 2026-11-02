extends Control

## The desk record: rank, progression, stats, Hall of Fame badges.

var _confirm_reset := false
var _reset_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroller := ScrollContainer.new()
	scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroller)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var back := Button.new()
	back.text = "<"
	back.custom_minimum_size = Vector2(48, 44)
	back.pressed.connect(func() -> void: Main.goto(load("res://src/screens/title_screen.gd")))
	head.add_child(back)
	var head_lbl := UI.label("DESK RECORD", 20)
	head_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(head_lbl)

	var rank_panel := PanelContainer.new()
	col.add_child(rank_panel)
	var rp := VBoxContainer.new()
	rp.add_theme_constant_override("separation", 6)
	rank_panel.add_child(rp)
	var idx := GameState.rank_index()
	rp.add_child(UI.label(GameState.RANKS[idx]["name"].to_upper(), 26, UI.GOLD))
	var nxt: Dictionary = GameState.next_rank()
	if idx < GameState.RANKS.size() - 1:
		var need := float(nxt["min"])
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = need
		bar.value = GameState.best_bankroll
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		rp.add_child(bar)
		rp.add_child(UI.label("Best bankroll %s — %s at %s" % [
			RoundRules.fmt_money(GameState.best_bankroll),
			nxt["name"], RoundRules.fmt_money(need)], 13, UI.TEXT_DIM, true))
	else:
		rp.add_child(UI.label("Best bankroll %s — you've reached the top of the street." % RoundRules.fmt_money(GameState.best_bankroll), 13, UI.TEXT_DIM, true))

	var stats := PanelContainer.new()
	col.add_child(stats)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	stats.add_child(grid)
	var rate := 0
	if GameState.total_settlements > 0:
		rate = int(round(100.0 * GameState.wins / float(GameState.wins + GameState.losses))) if GameState.wins + GameState.losses > 0 else 0
	_add_stat(grid, "Settled calls", str(GameState.total_settlements))
	_add_stat(grid, "Win rate", "%d%%" % rate)
	_add_stat(grid, "Current streak", str(GameState.streak))
	_add_stat(grid, "Best streak", str(GameState.best_streak))
	_add_stat(grid, "Lifetime gains", RoundRules.fmt_money(GameState.total_profit))
	for mode_id in GameState.best_run_pct:
		_add_stat(grid, "Best %s" % mode_id, RoundRules.fmt_pct(float(GameState.best_run_pct[mode_id])))

	var fame_title := UI.label("HALL OF FAME", 16, UI.GOLD)
	col.add_child(fame_title)
	for spec in LevelGen.CURATED_SPECS:
		var stars := int(GameState.curated_stars.get(spec["id"], 0))
		var line := UI.label("%s  ·  %s  ·  %s  %s" % [
			spec["title"], spec["date"], spec["mode"],
			("*".repeat(stars) + "·".repeat(3 - stars)) if stars > 0 else "-"], 13,
			UI.TEXT if stars > 0 else UI.TEXT_DIM, true)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(line)

	_reset_btn = Button.new()
	_reset_btn.text = "Reset record"
	_reset_btn.custom_minimum_size = Vector2(0, 48)
	_reset_btn.pressed.connect(_on_reset)
	col.add_child(_reset_btn)


func _add_stat(grid: GridContainer, name_text: String, value_text: String) -> void:
	var n := UI.label(name_text, 14, UI.TEXT_DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(n)
	var v := UI.label(value_text, 14)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(v)


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_btn.text = "Tap again to erase everything"
		_reset_btn.add_theme_color_override("font_color", UI.RED)
		return
	GameState.reset_profile()
	_confirm_reset = false
	Main.goto(load("res://src/screens/rank_screen.gd"))
