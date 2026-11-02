class_name DecisionBar
extends VBoxContainer

## The tap pad. During a decision window the player taps SELL / CASH / BUY
## directly, or cycles the highlight with Tab and commits with Space/Enter.

signal committed(pos: int)

const OPT_LONG := RoundRules.LONG
const OPT_CASH := RoundRules.CASH
const OPT_SHORT := RoundRules.SHORT

var _buttons := {}       # pos -> Button
var _order: Array[int] = []
var _selected := 0
var _open := false
var _timer: ProgressBar
var _hint: Label


func _init(allow_cash: bool) -> void:
	add_theme_constant_override("separation", 10)
	_timer = ProgressBar.new()
	_timer.min_value = 0.0
	_timer.max_value = 1.0
	_timer.value = 1.0
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(0, 8)
	_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_timer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	_order.assign([OPT_LONG])
	if allow_cash:
		_order.append(OPT_CASH)
	_order.append(OPT_SHORT)
	for pos in _order:
		var btn := Button.new()
		btn.text = _label_for(pos)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 110)
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		match pos:
			OPT_LONG:
				UI.tint_button(btn, UI.GREEN_DARK)
			OPT_SHORT:
				UI.tint_button(btn, UI.RED_DARK)
			_:
				UI.tint_button(btn, Color("2c3e50"))
		btn.add_theme_font_size_override("font_size", 24)
		var p := pos
		btn.pressed.connect(func() -> void: commit(p))
		row.add_child(btn)
		_buttons[pos] = btn

	_hint = UI.label("Tab switches · Space commits · or just tap", 13, UI.TEXT_DIM)
	add_child(_hint)
	_close()


func _label_for(pos: int) -> String:
	match pos:
		OPT_LONG:
			return "BUY\nUP"
		OPT_SHORT:
			return "SHORT\nDOWN"
		_:
			return "CASH\nSIT OUT"


func open_window(seconds: float) -> void:
	_open = true
	_selected = 0
	_timer.value = 1.0
	for pos in _order:
		_buttons[pos].disabled = false
	_refresh_selection()
	show()


func set_time_left(fraction: float) -> void:
	_timer.value = clampf(fraction, 0.0, 1.0)
	_timer.modulate = UI.GREEN if fraction > 0.4 else (UI.GOLD if fraction > 0.18 else UI.RED)


func close_window() -> void:
	_close()


func _close() -> void:
	_open = false
	hide()


func is_open() -> bool:
	return _open


func cycle() -> void:
	if not _open:
		return
	_selected = (_selected + 1) % _order.size()
	_refresh_selection()


func selected_pos() -> int:
	return _order[_selected]


func commit(pos: int) -> void:
	if not _open:
		return
	_close()
	committed.emit(pos)


func commit_selected() -> void:
	if _open:
		commit(selected_pos())


func _refresh_selection() -> void:
	for i in _order.size():
		var btn: Button = _buttons[_order[i]]
		var prefix := "> " if i == _selected else "  "
		btn.text = prefix + _label_for(_order[i])
		btn.self_modulate = Color.WHITE if i == _selected else Color(0.72, 0.72, 0.72, 1.0)


func set_hint(text: String) -> void:
	_hint.text = text
