class_name UI
extends RefCounted

## Shared theme + widget factories. One dark trading-terminal palette for the
## whole game, applied at the root window; per-node overrides only for accents.

const BG := Color("0b0f14")
const PANEL := Color("121a23")
const PANEL_LIGHT := Color("1a242f")
const TEXT := Color("e8f0f7")
const TEXT_DIM := Color("7d8ea0")
const GREEN := Color("26d07c")
const GREEN_DARK := Color("147a49")
const RED := Color("ff4d5e")
const RED_DARK := Color("8f2733")
const CASH_BLUE := Color("4aa3ff")
const GOLD := Color("ffc857")
const GRID := Color("1a242f")
const MONO_GAP := 2


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", TEXT)

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(16)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var states := {
		"normal": PANEL_LIGHT,
		"hover": Color("22303f"),
		"pressed": Color("0e141b"),
		"disabled": Color("141b23"),
		"focus": Color("1b2836"),
	}
	for state_name in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state_name]
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(14)
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_color = Color("2a3746") if state_name != "focus" else GOLD
		theme.set_stylebox(state_name, "Button", sb)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_font_size("font_size", "Button", 19)

	# Square corners: rounded corners fail triangulation on thin (8px) fills.
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color("18222e")
	pb_bg.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = GOLD
	pb_fill.set_content_margin_all(0)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	return theme


static func label(text: String, size: int = 17, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", MONO_GAP)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Tint a button's styleboxes with an accent color (sell/buy/cash pads).
static func tint_button(btn: Button, color: Color, text_color: Color = Color.WHITE) -> void:
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var copy := StyleBoxFlat.new()
		copy.set_corner_radius_all(12)
		copy.set_content_margin_all(14)
		copy.bg_color = color.darkened(0.25) if state_name == "pressed" else color
		copy.border_color = Color("2a3746") if state_name == "disabled" else color.lightened(0.25)
		btn.add_theme_stylebox_override(state_name, copy)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)


static func dimmed(btn: Button, factor: float) -> void:
	btn.self_modulate = Color(1, 1, 1, factor)
