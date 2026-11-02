extends Node

## Autoload: loads the packed market archives listed in data/manifest.json.

var series := {} # symbol -> MarketSeries
var _ready_ok := false


func _ready() -> void:
	load_all()


func load_all() -> bool:
	series.clear()
	var file := FileAccess.open("res://data/manifest.json", FileAccess.READ)
	if file == null:
		push_error("MarketData: missing res://data/manifest.json — run tools/build_data.py")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed.has("symbols"):
		push_error("MarketData: manifest.json is malformed")
		return false
	for entry in parsed["symbols"]:
		var s := MarketSeries.load_from(entry["file"])
		if s == null:
			push_error("MarketData: failed to load %s" % entry["file"])
			return false
		s.symbol = entry["symbol"]
		series[s.symbol] = s
	_ready_ok = not series.is_empty()
	print("MarketData: loaded %d symbol(s): %s" % [series.size(), ", ".join(series.keys())])
	return _ready_ok


func is_ready() -> bool:
	return _ready_ok


func symbols() -> Array:
	return series.keys()


func get_series(symbol: String) -> MarketSeries:
	return series.get(symbol)
