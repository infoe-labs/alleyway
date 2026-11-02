class_name PriceChart
extends Control

## The star of the show: a live-style line chart. Points stream in from the
## RoundFlow; the view auto-scales, colors the tape by session direction, and
## overlays a volume histogram, an entry line, and a last-price tag.

const MAX_POINTS := 720
const PAD_TOP := 0.10
const PAD_BOTTOM := 0.10
const VOL_HEIGHT_RATIO := 0.16

var points := PackedFloat32Array()      # visible rolling window of prices
var vols := PackedFloat32Array()        # per-point bar volume (for the histogram)
var session_start_price := 0.0          # baseline for green/red decision
var entry_price := -1.0                 # dashed entry line; <0 disables
var entry_label := ""
var last_price := 0.0

var _view_min := 0.0
var _view_max := 1.0


func reset(baseline_price: float) -> void:
	points.clear()
	vols.clear()
	session_start_price = baseline_price
	last_price = baseline_price
	entry_price = -1.0
	entry_label = ""
	_view_min = 0.0
	_view_max = 0.0
	refresh_view(true)


func push(price: float, bar_volume: float) -> void:
	points.append(price)
	vols.append(bar_volume)
	if points.size() > MAX_POINTS:
		points = points.slice(points.size() - MAX_POINTS)
		vols = vols.slice(vols.size() - MAX_POINTS)
	last_price = price
	refresh_view(false)
	queue_redraw()


func set_entry(price: float, label_text: String) -> void:
	entry_price = price
	entry_label = label_text
	queue_redraw()


func _current_direction_up() -> bool:
	if points.is_empty() or session_start_price <= 0.0:
		return true
	return last_price >= session_start_price


func _current_color() -> Color:
	return UI.GREEN if _current_direction_up() else UI.RED


func _refresh_target(out_min: Array, out_max: Array) -> void:
	var lo := INF
	var hi := -INF
	for p in points:
		lo = minf(lo, p)
		hi = maxf(hi, p)
	if entry_price > 0.0:
		lo = minf(lo, entry_price)
		hi = maxf(hi, entry_price)
	if last_price > 0.0:
		lo = minf(lo, last_price)
		hi = maxf(hi, last_price)
	if not is_finite(lo):
		return
	if hi - lo < hi * 0.001:
		hi += hi * 0.001 + 0.01
		lo -= hi * 0.001 + 0.01
	out_min[0] = lo
	out_max[0] = hi


func refresh_view(instant: bool) -> void:
	var lo: Array = [_view_min]
	var hi: Array = [_view_max]
	_refresh_target(lo, hi)
	if lo[0] == INF:
		return
	if instant or _view_min == 0.0:
		_view_min = lo[0]
		_view_max = hi[0]
	else:
		_view_min = lerpf(_view_min, lo[0], 0.18)
		_view_max = lerpf(_view_max, hi[0], 0.18)


func _y_for(price: float, top: float, height: float) -> float:
	var range_v := maxf(_view_max - _view_min, 0.0001)
	var norm := (price - _view_min) / range_v
	return top + height * (1.0 - norm)


func _draw() -> void:
	if points.is_empty():
		return
	var w := size.x
	var vol_h := size.y * VOL_HEIGHT_RATIO
	var top := size.y * PAD_TOP
	var chart_h := size.y * (1.0 - PAD_TOP - PAD_BOTTOM) - vol_h
	var line_color := _current_color()

	# Grid: horizontal lines + price labels.
	var font := get_theme_default_font()
	var fs := 13
	for i in 4:
		var norm := 0.12 + 0.25 * float(i)
		var y := lerpf(top + chart_h, top, norm)
		draw_line(Vector2(0, y), Vector2(w, y), Color(UI.GRID, 0.8), 1.0)
		var price_lbl := _view_min + (_view_max - _view_min) * norm
		draw_string(font, Vector2(6, y - 4), "%.2f" % price_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.TEXT_DIM, 0.9))

	# Volume histogram (bottom band).
	var max_vol := 1.0
	for v in vols:
		max_vol = maxf(max_vol, v)
	var n := points.size()
	var step := maxf(w / float(MAX_POINTS * 0.75), 1.0)
	var vol_y0 := top + chart_h + 4
	for i in n:
		var vh := vol_h * (vols[i] / max_vol)
		var x := w - float(n - i) * step
		if x < -step:
			break
		draw_rect(Rect2(x, vol_y0 + (vol_h - vh), maxf(step * 0.7, 1.0), vh), Color(line_color, 0.16))

	# Build screen points (right-anchored so the newest tick sits at the right edge).
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var x := w - float(n - 1 - i) * step
		pts[i] = Vector2(x, _y_for(points[i], top, chart_h))

	# Area fill under the line. Skip degenerate geometry: triangulation throws
	# on zero-height views or near-zero-width strips.
	var xs_spread := pts[n - 1].x - pts[0].x
	var view_ok := _view_max - _view_min > 0.0001
	if n >= 2 and chart_h > 0.0 and w > 0.0 and view_ok and xs_spread >= 2.0:
		# Earcut rejects near-duplicate vertices, so rebuild the strip with an
		# epsilon dedupe, then require a real polygon area before submitting.
		var area := PackedVector2Array()
		var baseline := top + chart_h
		area.append(Vector2(pts[0].x, baseline))
		for p in pts:
			if is_finite(p.x) and is_finite(p.y) and p.distance_squared_to(area[area.size() - 1]) > 0.25:
				area.append(p)
		var tail := Vector2(pts[n - 1].x, baseline)
		if tail.distance_squared_to(area[area.size() - 1]) > 0.25:
			area.append(tail)
		# Same gate the renderer applies — skip instead of erroring on
		# degenerate geometry (flat tapes, subpixel strips, first frames).
		if area.size() >= 3 and not Geometry2D.triangulate_polygon(area).is_empty():
			draw_colored_polygon(area, Color(line_color, 0.10))

	# Entry line.
	if entry_price > 0.0:
		var ey := _y_for(entry_price, top, chart_h)
		draw_dashed_line(Vector2(0, ey), Vector2(w, ey), Color(UI.CASH_BLUE, 0.9), 2.0, 8.0)
		draw_string(font, Vector2(6, ey - 6), entry_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.CASH_BLUE)

	# The tape itself.
	if n >= 2:
		draw_polyline(pts, line_color, 3.0, true)

	# Live head dot + price tag.
	var head := pts[n - 1]
	draw_circle(head, 5.0, line_color)
	draw_circle(head, 9.0, Color(line_color, 0.25))
	var tag := "%.2f" % last_price
	var tag_size := Vector2(66, 26)
	var tag_pos := Vector2(w - tag_size.x - 2, clampf(head.y - tag_size.y / 2.0, 0, size.y - tag_size.y))
	draw_rect(Rect2(tag_pos, tag_size), UI.BG)
	draw_rect(Rect2(tag_pos, tag_size), line_color.darkened(0.2), false, 2.0)
	draw_string(get_theme_default_font(), tag_pos + Vector2(6, 19), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, line_color)



