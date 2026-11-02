class_name PriceChart
extends Control

## The star of the show: a full trading terminal drawn in one pass.
## History arrives pre-seeded from the series (closed candles), the live
## tape streams on top: a forming candle, the tick line, EMA9/EMA21 and
## Bollinger(20,2) over the closes, a per-bar volume band, and a MACD
## (12/26/9) panel — plus the entry line and last-price tag.

const VISIBLE_BARS := 30      # bars across the full width
const LOOKBACK := 64          # bars kept (history + live)
const HIST_BARS := 40         # bars the screen should seed before the live bar
const PAD_TOP := 0.06
const PAD_BOTTOM := 0.03
const VOL_RATIO := 0.12
const MACD_RATIO := 0.17
const BAND_GAP := 8.0

var tpb := 24                              # ticks per bar (from the mode)
var session_start_price := 0.0             # baseline for green/red decision
var entry_price := -1.0                    # dashed entry line; <0 disables
var entry_label := ""
var last_price := 0.0

# Bar space, oldest .. newest. The last bar is the live/forming one.
var bo := PackedFloat32Array()
var bh := PackedFloat32Array()
var bl := PackedFloat32Array()
var bc := PackedFloat32Array()
var bv := PackedFloat32Array()

var points := PackedFloat32Array()         # live tick prices, newest last
var point_u := PackedFloat32Array()         # each tick's absolute bar-space coord
var _seq0 := 0                              # sequence number of bc[0] (trim-proof bar ids)

var _live_bar_id := -1                     # series bar index of the forming bar
var _ema9 := PackedFloat32Array()
var _ema21 := PackedFloat32Array()
var _bb := {}
var _macd := {}
var _view_min := 0.0
var _view_max := 1.0


func configure(ticks_per_bar: int) -> void:
	tpb = maxi(4, ticks_per_bar)


func reset() -> void:
	bo.clear()
	bh.clear()
	bl.clear()
	bc.clear()
	bv.clear()
	points.clear()
	point_u.clear()
	_live_bar_id = -1
	_seq0 = 0
	entry_price = -1.0
	entry_label = ""
	session_start_price = 0.0
	last_price = 0.0
	_refresh_indicators()
	refresh_view(true)


## Pre-populate closed candles for series bars [from_i, to_i] inclusive.
func seed_history(series: MarketSeries, from_i: int, to_i: int) -> void:
	from_i = clampi(from_i, 0, series.count() - 1)
	to_i = clampi(to_i, from_i, series.count() - 1)
	for i in range(from_i, to_i + 1):
		bo.append(series.opens[i])
		bh.append(series.highs[i])
		bl.append(series.lows[i])
		bc.append(series.closes[i])
		bv.append(series.volumes[i])
	_trim_bars()
	_refresh_indicators()
	refresh_view(true)
	queue_redraw()


func push(price: float, bar_volume: float, bar: int, tick: int, in_gap: bool) -> void:
	last_price = price
	if in_gap:
		refresh_view(false)
		queue_redraw()
		return
	# Line ticks sit on the bar grid (bar-space coord), so the tape aligns
	# exactly with the candles instead of sliding across them.
	var frac := (float(tick) + 1.0) / float(tpb)
	if bar != _live_bar_id:
		_live_bar_id = bar
		bo.append(price)
		bh.append(price)
		bl.append(price)
		bc.append(price)
		bv.append(bar_volume)
		_trim_bars()
		_refresh_indicators()
	else:
		var i := bc.size() - 1
		bh[i] = maxf(bh[i], price)
		bl[i] = minf(bl[i], price)
		bc[i] = price
		bv[i] = bar_volume
		_refresh_indicators()
	points.append(price)
	point_u.append(float(_seq0 + bc.size() - 1) + frac)
	var cap := 3 * tpb  # the line traces the live bar (+ a little overlap); history is candles
	if points.size() > cap:
		points = points.slice(points.size() - cap)
		point_u = point_u.slice(point_u.size() - cap)
	refresh_view(false)
	queue_redraw()


func bar_count() -> int:
	return bc.size()


func set_entry(price: float, label_text: String) -> void:
	entry_price = price
	entry_label = label_text
	queue_redraw()


func _trim_bars() -> void:
	while bo.size() > LOOKBACK:
		bo.remove_at(0)
		bh.remove_at(0)
		bl.remove_at(0)
		bc.remove_at(0)
		bv.remove_at(0)
		_seq0 += 1


func _refresh_indicators() -> void:
	_ema9 = Indicators.ema(bc, 9)
	_ema21 = Indicators.ema(bc, 21)
	_bb = Indicators.bollinger(bc, 20, 2.0)
	_macd = Indicators.macd(bc, 12, 26, 9)


func _current_color() -> Color:
	if session_start_price <= 0.0:
		return UI.GREEN
	return UI.GREEN if last_price >= session_start_price else UI.RED


func _refresh_target(out_min: Array, out_max: Array) -> void:
	var lo := INF
	var hi := -INF
	var from_i := maxi(0, bc.size() - VISIBLE_BARS)
	for i in range(from_i, bc.size()):
		lo = minf(lo, bl[i])
		hi = maxf(hi, bh[i])
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


func _bar_x(seq_from_end: int) -> float:
	# seq_from_end: 0 = newest bar, 1 = previous, ... right-anchored.
	var bar_w := size.x / float(VISIBLE_BARS)
	return size.x - (float(seq_from_end) + 0.5) * bar_w


func _draw() -> void:
	if bc.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var w := size.x
	var n := bc.size()
	var bar_w := w / float(VISIBLE_BARS)
	var body_w := maxf(bar_w * 0.62, 2.0)

	# Regions.
	var price_top := size.y * PAD_TOP
	var bottom := size.y * (1.0 - PAD_BOTTOM)
	var macd_h := size.y * MACD_RATIO
	var vol_h := size.y * VOL_RATIO
	var macd_top := bottom - macd_h
	var vol_top := macd_top - BAND_GAP - vol_h
	var price_bot := vol_top - BAND_GAP
	var price_h := price_bot - price_top
	if price_h <= 4.0:
		return
	var line_color := _current_color()
	var font := get_theme_default_font()
	var fs := 13

	# Grid + price labels.
	for i in 4:
		var norm := 0.12 + 0.25 * float(i)
		var y := lerpf(price_bot, price_top, norm)
		draw_line(Vector2(0, y), Vector2(w, y), Color(UI.GRID, 0.8), 1.0)
		var price_lbl := _view_min + (_view_max - _view_min) * norm
		draw_string(font, Vector2(6, y - 4), "%.2f" % price_lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.TEXT_DIM, 0.9))

	# Legend.
	draw_string(font, Vector2(w - 190, price_top + 12), "EMA9",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.GOLD)
	draw_string(font, Vector2(w - 148, price_top + 12), "EMA21",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.CASH_BLUE)
	draw_string(font, Vector2(w - 94, price_top + 12), "BB20",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.65, 0.78))

	# Bollinger bands (under the candles).
	var bb_upper: PackedFloat32Array = _bb.get("upper", PackedFloat32Array())
	var bb_lower: PackedFloat32Array = _bb.get("lower", PackedFloat32Array())
	if bb_upper.size() == n:
		_polyline(bb_upper, w, bar_w, n, func(i): return _y_for(bb_upper[i], price_top, price_h),
			Color(0.55, 0.65, 0.78, 0.42), 1.0, price_top - 1.0, price_bot + 1.0)
		_polyline(bb_lower, w, bar_w, n, func(i): return _y_for(bb_lower[i], price_top, price_h),
			Color(0.55, 0.65, 0.78, 0.42), 1.0, price_top - 1.0, price_bot + 1.0)

	# Candles.
	var from_i := maxi(0, n - VISIBLE_BARS - 2)
	for i in range(from_i, n):
		var seq_from_end := n - 1 - i
		var xc := _bar_x(seq_from_end)
		var up := bc[i] >= bo[i]
		var col := UI.GREEN if up else UI.RED
		# The forming bar sits under the live line — keep it quiet.
		if i == n - 1:
			col = col.darkened(0.15)
		var yh := _y_for(bh[i], price_top, price_h)
		var yl := _y_for(bl[i], price_top, price_h)
		draw_line(Vector2(xc, yh), Vector2(xc, yl), Color(col, 0.55), 1.0)
		var y1 := _y_for(maxf(bo[i], bc[i]), price_top, price_h)
		var y2 := _y_for(minf(bo[i], bc[i]), price_top, price_h)
		draw_rect(Rect2(xc - body_w / 2.0, y1, body_w, maxf(y2 - y1, 1.0)), Color(col, 0.45))

	# Moving averages over the closes.
	_polyline(_ema21, w, bar_w, n, func(i): return _y_for(_ema21[i], price_top, price_h),
		UI.CASH_BLUE, 1.5, price_top - 1.0, price_bot + 1.0)
	_polyline(_ema9, w, bar_w, n, func(i): return _y_for(_ema9[i], price_top, price_h),
		UI.GOLD, 1.5, price_top - 1.0, price_bot + 1.0)

	# Entry line, clipped to the price region.
	if entry_price > 0.0:
		var ey := _y_for(entry_price, price_top, price_h)
		if ey > price_top and ey < price_bot:
			draw_dashed_line(Vector2(0, ey), Vector2(w, ey), Color(UI.CASH_BLUE, 0.9), 2.0, 8.0)
			draw_string(font, Vector2(6, ey - 6), entry_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.CASH_BLUE)

	# The tape itself: the hero visual. Ticks are placed on the bar grid
	# (point_u), so the line traces exactly through its candles' cells.
	var m := points.size()
	var head := _seq0 + n - 1
	if m >= 2:
		var prev := Vector2(NAN, NAN)
		for i in m:
			var x := w - (float(head) + 1.0 - point_u[i]) * bar_w
			if x < -bar_w:
				prev = Vector2(NAN, NAN)
				continue
			var p := Vector2(x, _y_for(points[i], price_top, price_h))
			if is_finite(prev.x) and absf(p.y - prev.y) <= price_h * 0.25:
				draw_line(prev, p, line_color, 2.5, true)
			prev = p

	# Head dot at the tape's end + price tag pinned right.
	if m >= 1:
		var hx := w - (float(head) + 1.0 - point_u[m - 1]) * bar_w
		var head_pt := Vector2(hx, _y_for(points[m - 1], price_top, price_h))
		draw_circle(head_pt, 4.0, line_color)
		draw_circle(head_pt, 8.0, Color(line_color, 0.25))
		var tag := "%.2f" % last_price
		var tag_size := Vector2(66, 26)
		var tag_pos := Vector2(w - tag_size.x - 2,
			clampf(head_pt.y - tag_size.y / 2.0, price_top, price_bot - tag_size.y))
		draw_rect(Rect2(tag_pos, tag_size), UI.BG)
		draw_rect(Rect2(tag_pos, tag_size), line_color.darkened(0.2), false, 2.0)
		draw_string(font, tag_pos + Vector2(6, 19), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, line_color)

	# Volume band (per bar).
	draw_string(font, Vector2(6, vol_top + 12), "VOLUME",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UI.TEXT_DIM, 0.8))
	var max_vol := 1.0
	for i in range(maxi(0, n - VISIBLE_BARS), n):
		max_vol = maxf(max_vol, bv[i])
	for i in range(from_i, n):
		var xc := _bar_x(n - 1 - i)
		var vh := vol_h * (bv[i] / max_vol)
		var vcol := UI.GREEN if bc[i] >= bo[i] else UI.RED
		draw_rect(Rect2(xc - body_w / 2.0, vol_top + (vol_h - vh), body_w, vh),
			Color(vcol, 0.35))

	# MACD panel.
	draw_string(font, Vector2(6, macd_top + 12), "MACD 12/26/9",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UI.TEXT_DIM, 0.8))
	var macd_line: PackedFloat32Array = _macd.get("macd", PackedFloat32Array())
	var macd_sig: PackedFloat32Array = _macd.get("signal", PackedFloat32Array())
	var macd_hist: PackedFloat32Array = _macd.get("hist", PackedFloat32Array())
	if macd_line.size() != n:
		return
	var mlo := INF
	var mhi := -INF
	for i in range(maxi(0, n - VISIBLE_BARS), n):
		for v in [macd_line[i], macd_sig[i], macd_hist[i]]:
			if is_finite(v):
				mlo = minf(mlo, v)
				mhi = maxf(mhi, v)
	if not is_finite(mlo):
		return
	if mhi - mlo < 0.0001:
		mhi = mlo + 0.0001
	mlo -= (mhi - mlo) * 0.12
	mhi += (mhi - mlo) * 0.12
	var zero_y := macd_top + macd_h * (1.0 - (0.0 - mlo) / (mhi - mlo))
	draw_line(Vector2(0, zero_y), Vector2(w, zero_y), Color(UI.GRID, 1.0), 1.0)
	for i in range(from_i, n):
		var xc := _bar_x(n - 1 - i)
		if is_finite(macd_hist[i]):
			var hy := macd_top + macd_h * (1.0 - (macd_hist[i] - mlo) / (mhi - mlo))
			var top := minf(hy, zero_y)
			var hh := absf(hy - zero_y)
			draw_rect(Rect2(xc - body_w / 2.0, top, body_w, maxf(hh, 1.0)),
				Color(UI.GREEN, 0.5) if macd_hist[i] >= 0.0 else Color(UI.RED, 0.5))
	_polyline_macd(macd_line, w, bar_w, n, macd_top, macd_h, mlo, mhi, UI.CASH_BLUE)
	_polyline_macd(macd_sig, w, bar_w, n, macd_top, macd_h, mlo, mhi, UI.GOLD)


## Draws a bar-aligned polyline of finite values; `y_at` maps bar index -> y.
## Points outside [ymin, ymax] break the run, keeping overlays inside their band.
func _polyline(vals: PackedFloat32Array, w: float, bar_w: float, n: int,
		y_at: Callable, color: Color, width: float, ymin: float, ymax: float) -> void:
	var run := PackedVector2Array()
	for i in n:
		if is_finite(vals[i]):
			var x := _bar_x(n - 1 - i)
			if x >= -bar_w:
				var y: float = y_at.call(i)
				if y >= ymin and y <= ymax:
					run.append(Vector2(x, y))
					continue
		if run.size() >= 2:
			draw_polyline(run, color, width, true)
		run = PackedVector2Array()
	if run.size() >= 2:
		draw_polyline(run, color, width, true)


func _polyline_macd(vals: PackedFloat32Array, w: float, bar_w: float, n: int,
		top: float, h: float, lo: float, hi: float, color: Color) -> void:
	var run := PackedVector2Array()
	for i in n:
		if is_finite(vals[i]):
			var x := _bar_x(n - 1 - i)
			if x >= -bar_w:
				run.append(Vector2(x, top + h * (1.0 - (vals[i] - lo) / maxf(hi - lo, 0.0001))))
				continue
		if run.size() >= 2:
			draw_polyline(run, color, 1.5, true)
		run = PackedVector2Array()
	if run.size() >= 2:
		draw_polyline(run, color, 1.5, true)
