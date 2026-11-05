extends Node

## Autoload screen manager. Screens are Controls parented to the root window;
## one lives at a time. Theme is set at the window so every screen inherits it.

var _current: Control = null


func _ready() -> void:
	set_process(false)
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		set_process(str(window.location.search).contains("e2e=1"))
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


## Opt-in, read-only browser test telemetry. Tests still drive real input events.
func _process(_delta: float) -> void:
	if _current == null or not is_instance_valid(_current):
		return
	var snapshot := {"screen": _current.get_script().resource_path.get_file().trim_suffix(".gd")}
	if snapshot["screen"] == "play_screen":
		var flow: RoundFlow = _current.get("flow")
		if flow == null:
			return
		snapshot["state"] = RoundFlow.State.keys()[flow.state]
		snapshot["paused"] = _current.get("_paused")
		snapshot["bankroll"] = flow.bankroll
		snapshot["settled"] = flow.settled_results.size()
		snapshot["position"] = flow.positions.back() if not flow.positions.is_empty() else 0
		snapshot["exit_reason"] = flow.settled_results.back().get("exit_reason", "") if not flow.settled_results.is_empty() else ""
		snapshot["plan"] = _current.get("_plan_picker").selected
		var popup: PopupMenu = _current.get("_plan_picker").get_popup()
		snapshot["plan_open"] = popup.visible
		snapshot["manual_plan"] = [popup.position.x + popup.size.x * 0.5, popup.position.y + 16]
		snapshot["ff"] = flow.ff_mult
		for control_name in ["_skip_btn", "_plan_picker", "_exit_button", "_pause_btn"]:
			var control: Control = _current.get(control_name)
			var center := control.get_global_rect().get_center()
			snapshot[control_name] = [center.x, center.y]
		var pad: DecisionBar = _current.get("_decision_bar")
		var call_button: Control = pad._buttons[RoundRules.LONG]
		var center := call_button.get_global_rect().get_center()
		snapshot["call_button"] = [center.x, center.y]
	JavaScriptBridge.eval("window.__alleyway = %s;" % JSON.stringify(snapshot))
