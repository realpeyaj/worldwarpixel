class_name SimulationClock
extends RefCounted
## Strictly continuous 24 Hz fixed-timestep simulation clock.
## Intentionally provides NO pause, NO turn steps, and NO speed controls.

const TICK_RATE_HZ := 24.0
const TICK_INTERVAL := 1.0 / 24.0
const MAX_FRAME_DELTA := 0.25

var tick_count: int = 0
var accumulator: float = 0.0


func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	accumulator += minf(delta, MAX_FRAME_DELTA)
	var ticks_this_frame := 0
	while accumulator + 1e-6 >= TICK_INTERVAL:
		accumulator = maxf(0.0, accumulator - TICK_INTERVAL)
		tick_count += 1
		ticks_this_frame += 1
	return ticks_this_frame


func get_elapsed_seconds() -> float:
	return float(tick_count) * TICK_INTERVAL


func get_formatted_time() -> String:
	var total_sec: int = int(floor(get_elapsed_seconds() + 1e-6))
	var days: int = total_sec / 60 + 1
	var rem: int = total_sec % 60
	return "Day %d  %02d:%02d  (Tick %d)" % [days, rem / 10 * 4, (rem % 10) * 6, tick_count]
