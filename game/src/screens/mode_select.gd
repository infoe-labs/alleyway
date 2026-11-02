extends Control

## Mode select: three desk cards + the Hall of Fame (curated historical weeks).

const PLAY_SCREEN := preload("res://src/screens/play_screen.gd")

var _main_list: VBoxContainer
var _curated_view: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroller := ScrollContainer.new()
	scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroller)

	_main_list = VBoxContainer.new()
	_main_list.add_theme_constant_override("separation", 12)
	_main_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(_main_list)
	_build_main()

	_curated_view = VBoxContainer.new()
	_curated_view.add_theme_constant_override("separation", 10)
	_curated_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_curated_view.visible = false
	scroller.add_child(_curated_view)


func _build_main() -> void:
	for c in _main_list.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_main_list.add_child(head)
	var back := Button.new()
	back.text = "<"
	back.custom_minimum_size = Vector2(48, 44)
	back.pressed.connect(func() -> void: Main.goto(load("res://src/screens/title_screen.gd")))
	head.add_child(back)
	var title := UI.label("CHOOSE YOUR DESK", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)

	for mode_res in [
		"res://src/resources/modes/quick_flip.tres",
		"res://src/resources/modes/day_trader.tres",
		"res://src/resources/modes/swing.tres",
	]:
		_main_list.add_child(_mode_card(load(mode_res)))


func _mode_card(mode: ModeConfig) -> Control:
	var unlocked := GameState.is_unlocked(mode)
	var panel := PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var name_lbl := UI.label(mode.display_name, 20, UI.GREEN if unlocked else UI.TEXT_DIM)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(name_lbl)
	var best: Variant = GameState.best_run_pct.get(mode.id)
	if best != null:
		var pct_label := UI.label("best %s" % RoundRules.fmt_pct(float(best)), 13, UI.GOLD)
		pct_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		head.add_child(pct_label)
	col.add_child(UI.label(mode.blurb, 13, UI.TEXT_DIM))

	if not unlocked:
		var lock := Button.new()
		lock.text = "[ LOCKED ]  Requires %s" % GameState.RANKS[mode.unlock_rank]["name"]
		lock.disabled = true
		lock.custom_minimum_size = Vector2(0, 52)
		col.add_child(lock)
		return panel

	var run := Button.new()
	run.text = ">  Open the market"
	run.custom_minimum_size = Vector2(0, 56)
	UI.tint_button(run, UI.GREEN_DARK)
	run.pressed.connect(_start_endless.bind(mode))
	col.add_child(run)

	var curated := LevelGen.curated_for(mode.id)
	if not curated.is_empty():
		var fame := Button.new()
		fame.text = "*  Hall of Fame weeks (%d)" % curated.size()
		fame.custom_minimum_size = Vector2(0, 52)
		fame.pressed.connect(_show_curated.bind(mode))
		col.add_child(fame)
	return panel


func _start_endless(mode: ModeConfig) -> void:
	var level := LevelGen.make(mode, randi(), MarketData.series)
	Main.goto(PLAY_SCREEN, {"level": level})


func _show_curated(mode: ModeConfig) -> void:
	for c in _curated_view.get_children():
		c.queue_free()
	_main_list.visible = false
	_curated_view.visible = true

	var head := HBoxContainer.new()
	_curated_view.add_child(head)
	var back := Button.new()
	back.text = "<"
	back.custom_minimum_size = Vector2(48, 44)
	back.pressed.connect(func() -> void:
		_curated_view.visible = false
		_main_list.visible = true)
	head.add_child(back)
	var fame_lbl := UI.label("HALL OF FAME · %s" % mode.display_name, 18, UI.GOLD)
	fame_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fame_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(fame_lbl)

	for spec in LevelGen.curated_for(mode.id):
		var panel := PanelContainer.new()
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		panel.add_child(col)
		var stars := int(GameState.curated_stars.get(spec["id"], 0))
		var row := HBoxContainer.new()
		col.add_child(row)
		row.add_child(UI.label(spec["title"], 17, UI.TEXT))
		var star_lbl := UI.label("*".repeat(stars) + "·".repeat(3 - stars), 15, UI.GOLD)
		star_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(star_lbl)
		col.add_child(UI.label(spec["date"], 12, UI.TEXT_DIM))
		var play := Button.new()
		play.text = ">  Trade it"
		play.custom_minimum_size = Vector2(0, 48)
		UI.tint_button(play, UI.GREEN_DARK)
		play.pressed.connect(_start_curated.bind(spec, mode))
		col.add_child(play)
		_curated_view.add_child(panel)


func _start_curated(spec: Dictionary, mode: ModeConfig) -> void:
	var level := LevelGen.make_curated(spec, mode, MarketData.series)
	Main.goto(PLAY_SCREEN, {"level": level})
