extends Node

## Autoload screen manager. Screens are Controls parented to the root window;
## one lives at a time. Theme is set at the window so every screen inherits it.

var _current: Control = null


func _ready() -> void:
	get_tree().root.theme = UI.build_theme()
	call_deferred("_boot")


func _boot() -> void:
	if not MarketData.is_ready():
		_show_fatal()
		return
	goto(load("res://src/screens/title_screen.gd"))


func goto(script: Script, params: Dictionary = {}) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var screen: Control = script.new()
	if screen.has_method("with_params"):
		screen.with_params(params)
	get_tree().root.add_child(screen)
	_current = screen


func _show_fatal() -> void:
	var l := UI.label("Market archives failed to load.\nRun tools/build_data.py and re-export.", 18, UI.RED)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	get_tree().root.add_child(l)
	_current = l
