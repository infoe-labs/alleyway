class_name LevelDef
extends RefCounted

## One generated level. A level is `sessions` back-to-back segments of daily
## bars; a decision happens at the close of every segment but the last, and
## each position settles at the next checkpoint. Quick Flip is just the
## K=2 case, Day Trader is 1 bar per session, Swing is many bars per session.

var mode: ModeConfig
var seed_value := 0
var symbol := "SPY"
var start_bar := 0
var segments: Array[int] = []
var decision_seconds := 6.5
var bar_seconds := 1.35
var reveal_speed := 3.0
var display_name := ""
var subtitle := ""
var is_curated := false
var curated_id := ""


func total_bars() -> int:
	var n := 0
	for s in segments:
		n += s
	return n


func last_bar() -> int:
	return start_bar + total_bars() - 1


## Bar index whose CLOSE is the checkpoint that ends session i.
func checkpoint_bar(i: int) -> int:
	var b := start_bar
	for s in i + 1:
		b += segments[s]
	return b - 1


## Position count = decisions = sessions - 1 (each settled at the next checkpoint).
func decision_count() -> int:
	return max(0, segments.size() - 1)
