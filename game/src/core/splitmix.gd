class_name SplitMix32
extends RefCounted

## Deterministic 32-bit PRNG (SplitMix32). Same seed always yields the same
## sequence on every platform — the contract behind "same seed = same level".

var state: int = 0


func _init(seed_value: int = 0) -> void:
	state = seed_value & 0xFFFFFFFF


func next_int() -> int:
	state = (state + 0x9E3779B9) & 0xFFFFFFFF
	var z := state
	z = (z ^ (z >> 16)) & 0xFFFFFFFF
	z = (z * 0x21F0AAAD) & 0xFFFFFFFF
	z = (z ^ (z >> 15)) & 0xFFFFFFFF
	z = (z * 0x27D4EB2F) & 0xFFFFFFFF
	z = (z ^ (z >> 18)) & 0xFFFFFFFF
	return z


func next_float() -> float:
	return float(next_int()) / 4294967296.0


func range_f(from_v: float, to_v: float) -> float:
	return from_v + (to_v - from_v) * next_float()


func range_i(from_v: int, to_v: int) -> int:
	if to_v <= from_v:
		return from_v
	return from_v + next_int() % (to_v - from_v + 1)
