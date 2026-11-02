class_name Tape
extends RefCounted

## Turns daily OHLCV bars into deterministic, live-looking tick streams.
##
## Each bar's path runs Open -> (Low/High) -> (High/Low) -> Close with seeded
## noise inside the bar's range, so the chart advances tick by tick like a real
## feed. The same symbol+bar always synthesizes the exact same path — levels
## are reproducible by seed alone. Overnight gaps get a short synthetic bridge.

const GAP_TICKS := 10

var series: MarketSeries
var ticks_per_bar := 24
var noise_ratio := 0.28

var _symbol_hash := 0
var _bar_cache := {}
var _gap_cache := {}


func _init(p_series: MarketSeries, p_ticks_per_bar: int = 24) -> void:
	series = p_series
	ticks_per_bar = p_ticks_per_bar
	for ch in series.symbol.to_utf8_buffer():
		_symbol_hash = (_symbol_hash * 31 + int(ch)) & 0xFFFFFFFF


## Ticks for bar `bar`: first tick is the open, last tick is the close.
func bar_ticks(bar: int) -> PackedFloat32Array:
	if _bar_cache.has(bar):
		return _bar_cache[bar]
	var o := series.opens[bar]
	var h := series.highs[bar]
	var l := series.lows[bar]
	var c := series.closes[bar]
	var rng := SplitMix32.new((_symbol_hash ^ (bar * 0x9E3779B9)) & 0xFFFFFFFF)

	var anchors := PackedFloat32Array([o, l, h, c]) if c >= o else PackedFloat32Array([o, h, l, c])
	var span := maxf(h - l, (o + h + l + c) * 0.0002)
	var tpb := ticks_per_bar
	var seg_points := tpb / 3
	var ticks := PackedFloat32Array()
	ticks.resize(tpb)
	var idx := 0
	for seg in 3:
		var a := anchors[seg]
		var b := anchors[seg + 1]
		var amp := span * noise_ratio * rng.range_f(0.5, 1.2)
		var steps := seg_points if seg < 2 else tpb - seg_points * 2
		for i in steps:
			var f := float(i + 1) / float(steps)
			var base := lerpf(a, b, f)
			if seg == 2 and i == steps - 1:
				base = c
			var noise := (rng.next_float() * 2.0 - 1.0) * amp * sin(PI * f)
			ticks[idx] = clampf(base + noise, l, h)
			idx += 1
	ticks[0] = o
	ticks[tpb - 1] = c
	_bar_cache[bar] = ticks
	return ticks


## Synthetic bridge from bar's close to the next bar's open (overnight gap).
func gap_ticks(bar: int) -> PackedFloat32Array:
	if _gap_cache.has(bar):
		return _gap_cache[bar]
	var a := series.closes[bar]
	var b := series.opens[bar + 1]
	var rng := SplitMix32.new((_symbol_hash ^ ((bar + 7) * 0x85EBCA6B)) & 0xFFFFFFFF)
	var amp := maxf(absf(b - a), a * 0.001) * 0.25
	var ticks := PackedFloat32Array()
	ticks.resize(GAP_TICKS)
	for i in GAP_TICKS:
		var f := float(i + 1) / float(GAP_TICKS)
		var noise := (rng.next_float() * 2.0 - 1.0) * amp * sin(PI * f)
		ticks[i] = lerpf(a, b, f) + noise
	ticks[GAP_TICKS - 1] = b
	_gap_cache[bar] = ticks
	return ticks


## Human clock label for a tick inside a bar (session clock for day mode).
func tick_clock(bar: int, tick: int) -> String:
	return MarketSeries.session_clock(tick, ticks_per_bar)
