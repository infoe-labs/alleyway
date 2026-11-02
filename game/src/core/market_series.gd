class_name MarketSeries
extends RefCounted

## One symbol's daily OHLCV history, loaded from the packed binary produced by
## tools/build_data.py. Pure data — no scene-tree access.

const MAGIC := &"ABMD"

var symbol := ""
var days := PackedInt32Array() # Unix epoch days (UTC)
var opens := PackedFloat32Array()
var highs := PackedFloat32Array()
var lows := PackedFloat32Array()
var closes := PackedFloat32Array()
var volumes := PackedFloat32Array()

const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const _WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


static func load_from(path: String) -> MarketSeries:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MarketSeries: cannot open %s" % path)
		return null
	if file.get_32() != 0x444D4241: # 'ABMD' little-endian
		push_error("MarketSeries: bad magic in %s" % path)
		return null
	var version := file.get_32()
	if version != 1:
		push_error("MarketSeries: unsupported format version %d in %s" % [version, path])
		return null
	var count := file.get_32()
	if count < 60 or count > 100_000:
		push_error("MarketSeries: implausible bar count %d in %s" % [count, path])
		return null

	var series := MarketSeries.new()
	series.symbol = path.get_file().get_basename()
	series.days.resize(count)
	series.opens.resize(count)
	series.highs.resize(count)
	series.lows.resize(count)
	series.closes.resize(count)
	series.volumes.resize(count)
	for i in count:
		series.days[i] = file.get_32()
		series.opens[i] = file.get_float()
		series.highs[i] = file.get_float()
		series.lows[i] = file.get_float()
		series.closes[i] = file.get_float()
		series.volumes[i] = file.get_float()
	if file.get_error() != OK:
		push_error("MarketSeries: read error in %s" % path)
		return null
	return series


func count() -> int:
	return days.size()


func bar(i: int) -> Dictionary:
	return {
		"day": days[i], "open": opens[i], "high": highs[i],
		"low": lows[i], "close": closes[i], "volume": volumes[i],
	}


## "2008-10-06"
func date_of(i: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(days[i] * 86400)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## "Mon, Oct 6 2008"
func pretty_date(i: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(days[i] * 86400)
	return "%s, %s %d %d" % [_WEEKDAYS[d.weekday], _MONTHS[d.month - 1], d.day, d.year]


func month_year(i: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(days[i] * 86400)
	return "%s %d" % [_MONTHS[d.month - 1], d.year]


## Index of the first bar on or after the given ISO date, or -1 past the end.
func index_for_date(iso: String) -> int:
	var target := Time.get_unix_time_from_datetime_dict(_parse_iso(iso)) / 86400
	var lo := 0
	var hi := count() - 1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if days[mid] < target:
			lo = mid + 1
		else:
			hi = mid - 1
	return lo if lo < count() else -1


func _parse_iso(iso: String) -> Dictionary:
	var parts := iso.split("-")
	return {
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 0, "minute": 0, "second": 0,
	}


## Session clock label: maps a tick (0..per_bar-1) to a NYSE-style 09:30→16:00 time.
static func session_clock(tick: int, per_bar: int) -> String:
	var f := clampf(float(tick) / maxf(1.0, float(per_bar - 1)), 0.0, 1.0)
	var minutes := int(570.0 + f * 390.0) # 9:30 -> 16:00
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Standard deviation of daily log returns over [from, to] — used to flavor level names.
func realized_vol(from_i: int, to_i: int) -> float:
	from_i = clampi(from_i, 0, count() - 2)
	to_i = clampi(to_i, 1, count() - 1)
	var rets: Array[float] = []
	for i in range(from_i + 1, to_i + 1):
		if closes[i - 1] > 0.0:
			rets.append(log(closes[i] / closes[i - 1]))
	if rets.is_empty():
		return 0.0
	var mean := 0.0
	for r in rets:
		mean += r
	mean /= rets.size()
	var variance := 0.0
	for r in rets:
		variance += (r - mean) * (r - mean)
	variance /= rets.size()
	return sqrt(variance)


func total_return(from_i: int, to_i: int) -> float:
	from_i = clampi(from_i, 0, count() - 1)
	to_i = clampi(to_i, 0, count() - 1)
	if closes[from_i] <= 0.0:
		return 0.0
	return closes[to_i] / closes[from_i] - 1.0


## Rough volatility bucket for naming: "Quiet" .. "Wild".
static func vol_class(vol: float) -> String:
	if vol < 0.009:
		return "Quiet"
	if vol < 0.016:
		return "Steady"
	if vol < 0.026:
		return "Restless"
	return "Wild"
