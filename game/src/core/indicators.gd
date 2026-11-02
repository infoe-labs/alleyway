class_name Indicators
extends RefCounted

## Day-trader staple indicators, computed over an array of bar closes.
## All functions return arrays aligned with the input; values before the
## indicator's warm-up window are NAN. Pure math — no scene access.


static func sma(src: PackedFloat32Array, period: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	out.fill(NAN)
	if period <= 0 or src.size() < period:
		return out
	var sum := 0.0
	for i in src.size():
		sum += src[i]
		if i >= period:
			sum -= src[i - period]
		if i >= period - 1:
			out[i] = sum / period
	return out


static func ema(src: PackedFloat32Array, period: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	out.fill(NAN)
	if period <= 0 or src.size() < period:
		return out
	var seed_sum := 0.0
	for i in period:
		seed_sum += src[i]
	var k := 2.0 / (period + 1.0)
	var prev := seed_sum / period
	out[period - 1] = prev
	for i in range(period, src.size()):
		prev = src[i] * k + prev * (1.0 - k)
		out[i] = prev
	return out


## MACD line = EMA(fast) - EMA(slow); signal = EMA(macd, signal); hist = macd - signal.
static func macd(src: PackedFloat32Array, fast := 12, slow := 26, sig_period := 9) -> Dictionary:
	var n := src.size()
	var out := {"macd": PackedFloat32Array(), "signal": PackedFloat32Array(), "hist": PackedFloat32Array()}
	out["macd"].resize(n)
	out["signal"].resize(n)
	out["hist"].resize(n)
	out["macd"].fill(NAN)
	out["signal"].fill(NAN)
	out["hist"].fill(NAN)
	if n < slow + sig_period:
		return out
	var ef := ema(src, fast)
	var es := ema(src, slow)
	var line := PackedFloat32Array()
	line.resize(n)
	line.fill(NAN)
	for i in n:
		if is_finite(ef[i]) and is_finite(es[i]):
			line[i] = ef[i] - es[i]
	# Signal EMA over the defined tail of the macd line only.
	var first := -1
	for i in n:
		if is_finite(line[i]):
			first = i
			break
	if first < 0 or n - first < sig_period:
		return out
	var tail := PackedFloat32Array()
	for i in range(first, n):
		tail.append(line[i])
	var sig_tail := ema(tail, sig_period)
	var offset := n - tail.size()
	for j in tail.size():
		if is_finite(sig_tail[j]):
			out["signal"][offset + j] = sig_tail[j]
			out["macd"][offset + j] = line[offset + j]
			out["hist"][offset + j] = line[offset + j] - sig_tail[j]
	return out


## Bollinger bands around a simple moving average.
static func bollinger(src: PackedFloat32Array, period := 20, mult := 2.0) -> Dictionary:
	var n := src.size()
	var mid := sma(src, period)
	var upper := PackedFloat32Array()
	var lower := PackedFloat32Array()
	upper.resize(n)
	lower.resize(n)
	upper.fill(NAN)
	lower.fill(NAN)
	if n < period:
		return {"mid": mid, "upper": upper, "lower": lower}
	for i in range(period - 1, n):
		var mean := mid[i]
		var acc := 0.0
		for j in range(i - period + 1, i + 1):
			var d := src[j] - mean
			acc += d * d
		var sd := sqrt(acc / period)
		upper[i] = mean + mult * sd
		lower[i] = mean - mult * sd
	return {"mid": mid, "upper": upper, "lower": lower}
