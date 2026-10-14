extends Node
class_name TimeEffectManager

var effect_end_ms := 0


func request_slow_motion(scale: float, seconds: float) -> void:
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	effect_end_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func request_hitstop(seconds: float) -> void:
	request_slow_motion(0.05, seconds)


func reset() -> void:
	Engine.time_scale = 1.0
	effect_end_ms = 0


func _process(_delta: float) -> void:
	if effect_end_ms > 0 and Time.get_ticks_msec() >= effect_end_ms:
		reset()


func _exit_tree() -> void:
	reset()
