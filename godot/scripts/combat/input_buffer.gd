extends RefCounted
class_name CombatInputBuffer

var duration := 0.15
var pending: StringName = &""
var expires_at := 0.0


func push(action: StringName, now: float) -> void:
	pending = action
	expires_at = now + duration


func take(now: float) -> StringName:
	if now > expires_at:
		pending = &""
	var result := pending
	pending = &""
	return result


func clear() -> void:
	pending = &""
