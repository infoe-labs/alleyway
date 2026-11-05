class_name PriceChart
extends Control

## The star of the show: a full trading terminal drawn in one pass.
## History arrives pre-seeded from the series (closed candles), the live
## tape streams on top: a forming candle, the tick line, EMA9/EMA21 and
## Bollinger(20,2) over the closes, a per-bar volume band, MACD (12/26/9)
## and RSI(14) panels — plus entry line, last-price tag, and a hover/drag
## crosshair with an OHLC + indicator readout, like a real dashboard.
##
## The x scale adapts to the mode: Day Trader zooms into the live session
## (one bar = one trading day, clock axis 09:30->16:00); Quick Flip and
## Swing show a 30-bar window with a date axis.

signal tap_tape()   # a clean tap (no drag) — play screen maps it to ff toggle

const VISIBLE_BARS := 30      # default bars across the full width
const LOOKBACK := 64          # bars kept (history + live)
const HIST_BARS := 40         # bars the screen should seed before the live bar
const PAD_TOP := 0.06
const PAD_BOTTOM := 0.05      # room for the x-axis labels
const VOL_RATIO := 0.10
const MACD_RATIO := 0.14
const RSI_RATIO := 0.12
const BAND_GAP := 8.0
const RSI_COLOR := Color(0.66, 0.56, 0.95)
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var tpb := 24                              # ticks per bar (from the mode)
var visible_bars := VISIBLE_BARS           # bars across the width (per mode)
var intraday := false                      # day-trader view: live bar fills the screen
var session_start_price := 0.0             # baseline for green/red decision
var entry_price := -1.0                    # dashed entry line; <0 disables
var entry_label := ""
var stop_price := 0.0
var target_price := 0.0
var analysis: Dictionary = {}
var last_price := 0.0

# Bar space, oldest .. newest. The last bar is the live/forming one.
var bo := PackedFloat32Array()
var bh := PackedFloat32Array()
var bl := PackedFloat32Array()
var bc := PackedFloat32Array()
var bv := PackedFloat32Array()

var points := PackedFloat32Array()         # live tick prices, newest last
var point_u := PackedFloat32Array()        # each tick's absolute bar-space coord
var _seq0 := 0                             # sequence number of bc[0] (trim-proof bar ids)
var _bar_days := PackedInt32Array()        # epoch day per bar, for x-axis dates
var _series: MarketSeries = null           # ref for date formatting

var _live_bar_id := -1                     # series bar index of the forming bar
var _ema9 := PackedFloat32Array()
var _ema21 := PackedFloat32Array()
var _bb := {}
var _macd := {}
var _rsi := PackedFloat32Array()
var _view_min := 0.0
var _view_max := 1.0

# Crosshair scrub state.
var _hover_x := NAN
var _hover_y := NAN
var _down := Vector2(1e9, 1e9)
var _down_msec := 0
var _tap_candidate := false
const TAP_MAX_MS := 500      # hold longer than this = scrub intent, never FF
const TAP_MAX_DIST := 12.0


func _ready() -> void:
	mouse_exited.connect(func() -> void:
		_hover_x = NAN
		_hover_y = NAN
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = event.position.x
		_hover_y = event.position.y
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_down = event.position
			_down_msec = Time.get_ticks_msec()
			_tap_candidate = true
			_hover_x = event.position.x
			_hover_y = event.position.y
		else:
			# Tap = short + still. A finger held down to read the popover is
			# scrub intent and must never fast-forward the game.
			if _tap_candidate and Time.get_ticks_msec() - _down_msec <= TAP_MAX_MS:
				tap_tape.emit()
			_hover_x = NAN
			_hover_y = NAN
		queue_redraw()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_down) > TAP_MAX_DIST:
			_tap_candidate = false
		_hover_x = event.position.x
		_hover_y = event.position.y
		queue_redraw()
		accept_event()


func configure(ticks_per_bar: int, p_visible_bars: int = VISIBLE_BARS,
		p_intraday: bool = false) -> void:
	tpb = maxi(4, ticks_per_bar)
	visible_bars = clampi(p_visible_bars, 2, VISIBLE_BARS)
	intraday = p_intraday


func reset() -> void:
	bo.clear()
	bh.clear()
	bl.clear()
	bc.clear()
	bv.clear()
	points.clear()
	point_u.clear()
	_bar_days.clear()
	_live_bar_id = -1
	_seq0 = 0
	_series = null
	entry_price = -1.0
	entry_label = ""
	stop_price = 0.0
	target_price = 0.0
	session_start_price = 0.0
	last_price = 0.0
	_hover_x = NAN
	_hover_y = NAN
	_refresh_indicators()
	refresh_view(true)


## Pre-populate closed candles for series bars [from_i, to_i] inclusive.
func seed_history(series: MarketSeries, from_i: int, to_i: int) -> void:
	_series = series
	from_i = clampi(from_i, 0, series.count() - 1)
	to_i = clampi(to_i, from_i, series.count() - 1)
	for i in range(from_i, to_i + 1):
		bo.append(series.opens[i])
		bh.append(series.highs[i])
		bl.append(series.lows[i])
		bc.append(series.closes[i])
		bv.append(series.volumes[i])
		_bar_days.append(series.days[i])
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
		if _series != null:
			_bar_days.append(_series.days[clampi(bar, 0, _series.count() - 1)])
		else:
			_bar_days.append(0)
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
	# Keep only what's on screen; the line traces the last screen of sessions.
	var floor_u := float(_seq0 + bc.size() - 1) - float(visible_bars + 2)
	var drop := 0
	while drop < point_u.size() and point_u[drop] < floor_u:
		drop += 1
	if drop > 0:
		points = points.slice(drop)
		point_u = point_u.slice(drop)
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
		_bar_days.remove_at(0)
		_seq0 += 1


func _refresh_indicators() -> void:
	_ema9 = Indicators.ema(bc, 9)
	_ema21 = Indicators.ema(bc, 21)
	_bb = Indicators.bollinger(bc, 20, 2.0)
	_macd = Indicators.macd(bc, 12, 26, 9)
	_rsi = Indicators.rsi(bc, 14)
	analysis = TapeAnalysis.read(bc, bh, bl)


func _current_color() -> Color:
	if session_start_price <= 0.0:
		return UI.GREEN
	return UI.GREEN if last_price >= session_start_price else UI.RED


func _refresh_target(out_min: Array, out_max: Array) -> void:
	var lo := INF
	var hi := -INF
	# Fit the visible candle window so prior bars remain readable as the tape moves.
	var anchor := visible_bars
	var from_i := maxi(0, bc.size() - anchor)
	for i in range(from_i, bc.size()):
		lo = minf(lo, bl[i])
		hi = maxf(hi, bh[i])
		for overlay in [_ema9[i], _ema21[i]]:
			if is_finite(overlay):
				lo = minf(lo, overlay)
				hi = maxf(hi, overlay)
	for p in points:
		lo = minf(lo, p)
		hi = maxf(hi, p)
	if session_start_price > 0.0:
		lo = minf(lo, session_start_price)
		hi = maxf(hi, session_start_price)
	if last_price > 0.0:
		lo = minf(lo, last_price)
		hi = maxf(hi, last_price)
	if lo > hi:  # nothing streamed yet: fall back to the visible bars
		var bars_from := maxi(0, bc.size() - visible_bars)
		for i in range(bars_from, bc.size()):
			lo = minf(lo, bl[i])
			hi = maxf(hi, bh[i])
	if entry_price > 0.0:
		lo = minf(lo, entry_price)
		hi = maxf(hi, entry_price)
	for guide in [stop_price, target_price]:
		if guide > 0.0:
			lo = minf(lo, guide)
			hi = maxf(hi, guide)
	if not is_finite(lo):
		return
	# Floor the window so a flat session doesn't zoom into noise.
	var mid := (lo + hi) * 0.5
	var floor_w := maxf(mid * 0.004, 0.01)
	if hi - lo < floor_w:
		hi = mid + floor_w * 0.5
		lo = mid - floor_w * 0.5
	var padding := (hi - lo) * 0.06
	out_min[0] = lo - padding
	out_max[0] = hi + padding


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
		_view_min = minf(lo[0], lerpf(_view_min, lo[0], 0.18))
		_view_max = maxf(hi[0], lerpf(_view_max, hi[0], 0.18))


func _y_for(price: float, top: float, height: float) -> float:
	var range_v := maxf(_view_max - _view_min, 0.0001)
	var norm := (price - _view_min) / range_v
	return top + height * (1.0 - norm)


func _bar_x(seq_from_end: int) -> float:
	# seq_from_end: 0 = newest bar, 1 = previous, ... right-anchored.
	var bar_w := size.x / float(visible_bars)
	return size.x - (float(seq_from_end) + 0.5) * bar_w


func _fmt(v: float) -> String:
	return "%.2f" % v if is_finite(v) else "-"


func _draw() -> void:
	if bc.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var w := size.x
	var n := bc.size()
	var bar_w := w / float(visible_bars)
	# Cap bar widths: in the 3-bar day-trader view uncapped bodies become slabs.
	var body_w := minf(maxf(bar_w * 0.62, 2.0), 56.0)
	var thin_w := minf(maxf(bar_w * 0.45, 2.0), 22.0)

	# Regions: price / volume / macd / rsi / date axis.
	var price_top := size.y * PAD_TOP
	var bottom := size.y * (1.0 - PAD_BOTTOM)
	var rsi_h := size.y * RSI_RATIO
	var macd_h := size.y * MACD_RATIO
	var vol_h := size.y * VOL_RATIO
	var rsi_top := bottom - rsi_h
	var macd_top := rsi_top - BAND_GAP - macd_h
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
	var from_i := maxi(0, n - visible_bars - 2)
	for i in range(from_i, n):
		var seq_from_end := n - 1 - i
		var xc := _bar_x(seq_from_end)
		var up := bc[i] >= bo[i]
		var col := UI.GREEN if up else UI.RED
		# The forming bar sits under the live line — keep it quiet.
		if i == n - 1:
			col = col.darkened(0.15)
		var yh := clampf(_y_for(bh[i], price_top, price_h), price_top - 2.0, price_bot + 2.0)
		var yl := clampf(_y_for(bl[i], price_top, price_h), price_top - 2.0, price_bot + 2.0)
		draw_line(Vector2(xc, yh), Vector2(xc, yl), Color(col, 0.55), 1.0)
		var y1 := clampf(_y_for(maxf(bo[i], bc[i]), price_top, price_h), price_top, price_bot)
		var y2 := clampf(_y_for(minf(bo[i], bc[i]), price_top, price_h), price_top, price_bot)
		draw_rect(Rect2(xc - body_w / 2.0, y1, body_w, maxf(y2 - y1, 1.0)), Color(col, 0.45))

	# Moving averages over the closes.
	_polyline(_ema21, w, bar_w, n, func(i): return _y_for(_ema21[i], price_top, price_h),
		UI.CASH_BLUE, 1.5, price_top - 1.0, price_bot + 1.0)
	_polyline(_ema9, w, bar_w, n, func(i): return _y_for(_ema9[i], price_top, price_h),
		UI.GOLD, 1.5, price_top - 1.0, price_bot + 1.0)

	# Observed range levels exclude the forming candle; exit levels freeze at entry.
	var guides := [
		[float(analysis.get("support", 0.0)), "SUPPORT", UI.GREEN],
		[float(analysis.get("resistance", 0.0)), "RESISTANCE", UI.RED],
		[stop_price, "STOP", UI.RED],
		[target_price, "TARGET", UI.GOLD],
	]
	for guide in guides:
		var gy := _y_for(float(guide[0]), price_top, price_h)
		if float(guide[0]) > 0.0 and gy > price_top + 18.0 and gy < price_bot:
			draw_dashed_line(Vector2(0, gy), Vector2(w, gy), Color(guide[2], 0.45), 1.0, 5.0)
			draw_string(font, Vector2(w - 150.0, gy - 4.0), "%s %.2f" % [guide[1], guide[0]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, guide[2])

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
			if is_finite(prev.x):
				draw_line(prev, p, line_color, 2.5, true)
			prev = p

	# Head dot at the tape's end + price tag pinned right.
	if m >= 1:
		var hx := w - (float(head) + 1.0 - point_u[m - 1]) * bar_w
		var head_pt := Vector2(hx, _y_for(last_price, price_top, price_h))
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
	for i in range(maxi(0, n - visible_bars), n):
		max_vol = maxf(max_vol, bv[i])
	for i in range(from_i, n):
		var xc := _bar_x(n - 1 - i)
		var vh := vol_h * (bv[i] / max_vol)
		var vcol := UI.GREEN if bc[i] >= bo[i] else UI.RED
		draw_rect(Rect2(xc - thin_w / 2.0, vol_top + (vol_h - vh), thin_w, vh),
			Color(vcol, 0.35))

	_draw_x_axis(font, w, bar_w, n, from_i, bottom)

	# MACD panel.
	draw_string(font, Vector2(6, macd_top + 12), "MACD 12/26/9",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UI.TEXT_DIM, 0.8))
	var macd_line: PackedFloat32Array = _macd.get("macd", PackedFloat32Array())
	var macd_sig: PackedFloat32Array = _macd.get("signal", PackedFloat32Array())
	var macd_hist: PackedFloat32Array = _macd.get("hist", PackedFloat32Array())
	if macd_line.size() == n:
		var mlo := INF
		var mhi := -INF
		for i in range(maxi(0, n - visible_bars), n):
			for v in [macd_line[i], macd_sig[i], macd_hist[i]]:
				if is_finite(v):
					mlo = minf(mlo, v)
					mhi = maxf(mhi, v)
		if is_finite(mlo):
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
					draw_rect(Rect2(xc - thin_w / 2.0, top, thin_w, maxf(hh, 1.0)),
						Color(UI.GREEN, 0.5) if macd_hist[i] >= 0.0 else Color(UI.RED, 0.5))
			_polyline_macd(macd_line, w, bar_w, n, macd_top, macd_h, mlo, mhi, UI.CASH_BLUE)
			_polyline_macd(macd_sig, w, bar_w, n, macd_top, macd_h, mlo, mhi, UI.GOLD)

	# RSI panel (fixed 0..100, guide lines at 30/70).
	draw_string(font, Vector2(6, rsi_top + 11), "RSI 14",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UI.TEXT_DIM, 0.8))
	if _rsi.size() == n:
		for lvl: float in [30.0, 70.0]:
			var gy := rsi_top + rsi_h * (1.0 - lvl / 100.0)
			draw_dashed_line(Vector2(0, gy), Vector2(w, gy), Color(UI.GRID, 0.9), 1.0, 6.0)
		var rtop := rsi_top + 2.0
		var rh := rsi_h - 4.0
		var run := PackedVector2Array()
		for i in range(from_i, n):
			if is_finite(_rsi[i]):
				run.append(Vector2(_bar_x(n - 1 - i), rtop + rh * (1.0 - _rsi[i] / 100.0)))
		if run.size() >= 2:
			draw_polyline(run, RSI_COLOR, 1.5, true)

	# Crosshair + readout (mouse hover on desktop, drag on touch).
	if is_finite(_hover_x) and is_finite(_hover_y) and _hover_x >= 0.0 and _hover_x <= w:
		var best_i := from_i
		var best_d := INF
		for i in range(from_i, n):
			var d := absf(_bar_x(n - 1 - i) - _hover_x)
			if d < best_d:
				best_d = d
				best_i = i
		var cx := _bar_x(n - 1 - best_i)
		var cy := clampf(_hover_y, price_top, price_bot)
		draw_line(Vector2(cx, price_top), Vector2(cx, price_bot), Color(UI.TEXT, 0.35), 1.0)
		draw_line(Vector2(0, cy), Vector2(w, cy), Color(UI.TEXT, 0.22), 1.0)
		var hover_price: float = _view_max - (cy - price_top) / maxf(price_h, 1.0) \
			* (_view_max - _view_min)
		var ytag := Rect2(w - 60.0, cy - 10.0, 58.0, 20.0)
		draw_rect(ytag, UI.BG)
		draw_rect(ytag, Color(UI.TEXT_DIM, 0.6), false, 1.0)
		draw_string(font, ytag.position + Vector2(5, 15), "%.2f" % hover_price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT)
		_draw_readout(font, best_i, price_top)


## Session clock (Day Trader) or dates (other modes) under the price bands.
func _draw_x_axis(font: Font, w: float, bar_w: float, n: int, from_i: int, bottom: float) -> void:
	if _bar_days.size() != n:
		return
	if intraday:
		# 09:30 .. 16:00 across the live bar's cell, date under it.
		var every := maxi(1, int(round(float(tpb) / 4.0)))
		var clock_ticks: Array[int] = []
		var t := 0
		while t < tpb - 1:
			clock_ticks.append(t)
			t += every
		clock_ticks.append(tpb - 1)
		var drawn: Array = []  # [x, label] pairs kept, spaced >= 42px apart
		for tt in clock_ticks:
			var x := w - (1.0 - (float(tt) + 0.5) / float(tpb)) * bar_w
			x = minf(x, w - 24.0)  # keep the last label inside the canvas
			var is_last := tt == tpb - 1
			if not drawn.is_empty() and x - float(drawn.back()[0]) < 34.0:
				if not is_last:
					continue  # would collide with the previous label
				drawn.pop_back()  # the close label wins its slot
			drawn.append([x, MarketSeries.session_clock(tt, tpb)])
		for pair in drawn:
			var x: float = pair[0]
			draw_string(font, Vector2(x - 20.0, bottom + 12), String(pair[1]),
				HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(UI.TEXT_DIM, 0.9))
		for i in range(from_i, n):
			var xc := _bar_x(n - 1 - i)
			if xc < 0.0 or xc > w - 16.0:
				continue
			var d := Time.get_datetime_dict_from_unix_time(_bar_days[i] * 86400)
			var lbl := "%s %d" % [_MONTHS[d.month - 1], d.day]
			var live := i == n - 1
			if live:
				lbl = "%s %d '%02d" % [_MONTHS[d.month - 1], d.day, d.year % 100]
			draw_string(font, Vector2(xc - 30.0, bottom + 26), lbl,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 10,
				UI.TEXT if live else Color(UI.TEXT_DIM, 0.7))
	else:
		var last_year := 0
		for i in range(from_i, n):
			if (_seq0 + i) % 5 != 0:
				continue
			var xc := _bar_x(n - 1 - i)
			if xc < 0.0 or xc > w - 34.0:
				continue
			var d := Time.get_datetime_dict_from_unix_time(_bar_days[i] * 86400)
			var label := "%s %d" % [_MONTHS[d.month - 1], d.day]
			if d.year != last_year:
				label += " '%02d" % (d.year % 100)
			last_year = d.year
			draw_string(font, Vector2(xc - 20.0, bottom + 16), label,
				HORIZONTAL_ALIGNMENT_CENTER, 44, 11, Color(UI.TEXT_DIM, 0.9))


## Dashboard-style readout card for the crosshair's bar.
func _draw_readout(font: Font, i: int, price_top: float) -> void:
	var prev_c := bc[i - 1] if i > 0 else bc[i]
	var chg := bc[i] / prev_c - 1.0 if prev_c > 0.0 else 0.0
	var d := Time.get_datetime_dict_from_unix_time(_bar_days[i] * 86400) \
		if _bar_days.size() > i else {}
	var title := "----"
	if not d.is_empty():
		title = "%s %d, %d" % [_MONTHS[d.month - 1], d.day, d.year]
		if i == bc.size() - 1:
			title += "  (live)"
	var bbu: PackedFloat32Array = _bb.get("upper", PackedFloat32Array())
	var bbl: PackedFloat32Array = _bb.get("lower", PackedFloat32Array())
	var ml: PackedFloat32Array = _macd.get("macd", PackedFloat32Array())
	var ms: PackedFloat32Array = _macd.get("signal", PackedFloat32Array())
	var lines := [
		["O %s   H %s" % [_fmt(bo[i]), _fmt(bh[i])], UI.TEXT],
		["L %s   C %s  (%s)" % [_fmt(bl[i]), _fmt(bc[i]), RoundRules.fmt_pct(chg)],
			UI.GREEN if chg >= 0.0 else UI.RED],
		["VOL %.1fM" % (bv[i] / 1_000_000.0), UI.TEXT_DIM],
		["EMA9 %s   EMA21 %s" % [_fmt(_ema9[i]) if _ema9.size() > i else "-",
			_fmt(_ema21[i]) if _ema21.size() > i else "-"], UI.TEXT_DIM],
		["BB %s - %s" % [_fmt(bbl[i]) if bbl.size() > i else "-",
			_fmt(bbu[i]) if bbu.size() > i else "-"], UI.TEXT_DIM],
		["MACD %s   SIG %s" % [_fmt(ml[i]) if ml.size() > i else "-",
			_fmt(ms[i]) if ms.size() > i else "-"], UI.TEXT_DIM],
		["RSI %s" % (_fmt(_rsi[i]) if _rsi.size() > i else "-"), RSI_COLOR],
	]
	var pad := 8.0
	var row_h := 15.0
	var rect := Rect2(6.0, price_top + 2.0, 208.0, pad * 2.0 + row_h * float(lines.size() + 1))
	draw_rect(rect, Color(UI.BG, 0.94))
	draw_rect(rect, Color(UI.TEXT_DIM, 0.45), false, 1.0)
	draw_string(font, rect.position + Vector2(pad, pad + 11), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.GOLD)
	for r in lines.size():
		var entry: Array = lines[r]
		draw_string(font, rect.position + Vector2(pad, pad + 11 + row_h * float(r + 1)),
			String(entry[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, entry[1])


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
