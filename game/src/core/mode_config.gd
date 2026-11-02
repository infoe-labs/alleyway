class_name ModeConfig
extends Resource

## Read-only mode blueprint. The three shipped modes live in
## res://src/resources/modes/*.tres; the unified round flow is parameterized
## entirely by these fields (see RoundFlow).

enum Kind { QUICK_FLIP, DAY_TRADER, SWING }

@export var id: String = ""
@export var display_name: String = ""
@export var blurb: String = ""
@export var kind: Kind = Kind.QUICK_FLIP
@export var unlock_rank: int = 0 # required GameState rank index
@export var symbols: Array[String] = ["SPY"]

@export_group("Pacing")
@export var bar_seconds: float = 1.35   # real seconds to stream one bar in WATCH
@export var reveal_speed_mult: float = 3.0 # RESOLVE speed multiplier over bar_seconds
@export var decision_seconds: float = 6.5
@export var ticks_per_bar: int = 24

@export_group("Structure")
@export var warmup_min: int = 12   # quick flip: bars streamed before the call
@export var warmup_max: int = 20
@export var horizon_min: int = 1   # quick flip: bars revealed after the call
@export var horizon_max: int = 4
@export var sessions: int = 5       # day trader: trading days; swing: segments
@export var segment_bars_min: int = 10 # swing: bars per segment
@export var segment_bars_max: int = 16
@export var allow_cash: bool = false

@export_group("Run")
@export var start_bankroll: float = 10000.0
@export var bust_at: float = 50.0


static func for_kind(k: Kind) -> String:
	match k:
		Kind.QUICK_FLIP:
			return "quick_flip"
		Kind.DAY_TRADER:
			return "day_trader"
		_:
			return "swing"
