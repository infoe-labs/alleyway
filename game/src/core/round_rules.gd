class_name RoundRules
extends RefCounted

## Pure settlement math — kept free of scene/autoloading so tests can hammer it.

const LONG := 1
const CASH := 0
const SHORT := -1


static func position_label(pos: int) -> String:
	match pos:
		LONG:
			return "CALL"
		SHORT:
			return "PUT"
		_:
			return "CASH"


## All-in staking: the whole bankroll rides each segment. A short is capped at
## -100% (the broker liquidates instead of letting you owe).
static func settle(bankroll: float, pos: int, entry: float, exit_price: float) -> Dictionary:
	if pos == CASH or entry <= 0.0:
		return {"pnl": 0.0, "bankroll": bankroll, "ret": 0.0}
	var raw_ret := exit_price / entry - 1.0
	var capped := clampf(float(pos) * raw_ret, -1.0, 4.0) # 400% generous cap for display sanity
	var new_bankroll := maxf(0.0, bankroll + bankroll * capped)
	return {
		"pnl": new_bankroll - bankroll,
		"bankroll": new_bankroll,
		"ret": capped,
	}


static func stars_for(result_pct: float) -> int:
	if result_pct >= 0.10:
		return 3
	if result_pct >= 0.03:
		return 2
	if result_pct > 0.0:
		return 1
	return 0


static func fmt_money(v: float) -> String:
	var neg := v < 0.0
	var s := "%.0f" % absf(v)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if neg else "$") + out


static func fmt_pct(v: float, signed: bool = true) -> String:
	var s := "%.1f%%" % (absf(v) * 100.0)
	if not signed:
		return s
	if v > 0.0:
		return "+" + s
	if v < 0.0:
		return "-" + s
	return s
