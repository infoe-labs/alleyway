class_name TapeAnalysis
extends RefCounted

## Reads only observed candles. The forming candle never sets its own breakout level.
static func read(closes: PackedFloat32Array, highs: PackedFloat32Array,
		lows: PackedFloat32Array) -> Dictionary:
	var n := closes.size()
	if n < 22:
		return {}
	var fast := Indicators.ema(closes, 9)
	var slow := Indicators.ema(closes, 21)
	var strength := Indicators.rsi(closes, 14)
	var support := INF
	var resistance := -INF
	var total_range := 0.0
	for i in range(maxi(1, n - 15), n - 1):
		support = minf(support, lows[i])
		resistance = maxf(resistance, highs[i])
		total_range += maxf(highs[i] - lows[i],
			maxf(absf(highs[i] - closes[i - 1]), absf(lows[i] - closes[i - 1])))
	var atr := total_range / float(mini(14, n - 2))
	var price := float(closes[n - 1])
	var trend := 1 if fast[n - 1] > slow[n - 1] else -1
	var slope := float(fast[n - 1] - fast[n - 2])
	var momentum := float(strength[n - 1])
	var score := trend
	score += 1 if price > fast[n - 1] else -1
	score += 1 if slope > 0.0 else (-1 if slope < 0.0 else 0)
	score += 1 if momentum > 55.0 else (-1 if momentum < 45.0 else 0)
	var bias := "CALL lean" if score >= 3 else ("PUT lean" if score <= -3 else "Mixed · CASH is a choice")
	var event := "Inside recent range"
	if price > resistance:
		event = "Resistance break · watch for a failed breakout"
	elif price < support:
		event = "Support break · watch for a reclaim"
	elif momentum > 70.0:
		event = "RSI stretched high · chase carefully"
	elif momentum < 30.0:
		event = "RSI stretched low · bounce risk"
	if fast[n - 2] <= slow[n - 2] and fast[n - 1] > slow[n - 1]:
		event = "Bullish EMA cross · look for a hold above EMA9"
	elif fast[n - 2] >= slow[n - 2] and fast[n - 1] < slow[n - 1]:
		event = "Bearish EMA cross · look for rejection at EMA9"
	return {"support": support, "resistance": resistance, "atr": maxf(atr, price * 0.002),
		"bias": bias, "score": score, "event": event,
		"trend": "EMA9 above EMA21" if trend > 0 else "EMA9 below EMA21",
		"slope": "rising" if slope > 0.0 else "falling", "rsi": momentum}
