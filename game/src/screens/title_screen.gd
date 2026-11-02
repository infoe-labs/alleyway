extends Control

## Title screen: the marquee, then two doors.

const MODE_SELECT := preload("res://src/screens/mode_select.gd")
const RANK_SCREEN := preload("res://src/screens/rank_screen.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(320, 0)
	center.add_child(col)

	col.add_child(UI.label("A F T E R B E L L", 34, UI.GREEN))
	col.add_child(UI.label("the market, years ago,\nin realtime — right now", 15, UI.TEXT_DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	col.add_child(spacer)

	var play := Button.new()
	play.text = "P L A Y"
	play.custom_minimum_size = Vector2(0, 64)
	UI.tint_button(play, UI.GREEN_DARK)
	play.pressed.connect(func() -> void: Main.goto(MODE_SELECT))
	col.add_child(play)

	var records := Button.new()
	records.text = "Desk Record"
	records.custom_minimum_size = Vector2(0, 52)
	records.pressed.connect(func() -> void: Main.goto(RANK_SCREEN))
	col.add_child(records)

	var chip := UI.label("%s · %dW / %dL" % [GameState.rank_name(), GameState.wins, GameState.losses],
		13, UI.GOLD)
	chip.custom_minimum_size = Vector2(0, 28)
	col.add_child(chip)
	if not GameState.persistence_ok():
		col.add_child(UI.label("Storage is blocked (private mode?) — progress won't persist.", 11, UI.RED))
