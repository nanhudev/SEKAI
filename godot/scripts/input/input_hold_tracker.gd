extends RefCounted
## Lightweight press/hold/release tracker for one semantic action.
## Used by Tab (threshold hold) and available for future E/X/C hold skills.
## Preloaded by InputContract (no class_name — avoids global-class cache races).

var action: StringName = &""
var hold_threshold_sec := 0.22

var pressed := false
var held_duration := 0.0
var released := false
var is_hold := false
var triggered_hold := false


func reset() -> void:
	pressed = false
	held_duration = 0.0
	released = false
	is_hold = false
	triggered_hold = false


func begin() -> void:
	pressed = true
	held_duration = 0.0
	released = false
	is_hold = false
	triggered_hold = false


func tick(delta: float) -> bool:
	## Returns true the first frame hold_threshold is crossed while still pressed.
	if not pressed:
		return false
	held_duration += delta
	if not triggered_hold and held_duration >= hold_threshold_sec:
		triggered_hold = true
		is_hold = true
		return true
	return false


func end() -> Dictionary:
	## Call on release. Returns {is_hold, held_duration, was_tap}.
	var was_hold := triggered_hold
	var duration := held_duration
	released = true
	pressed = false
	is_hold = was_hold
	return {
		"is_hold": was_hold,
		"held_duration": duration,
		"was_tap": not was_hold,
	}
