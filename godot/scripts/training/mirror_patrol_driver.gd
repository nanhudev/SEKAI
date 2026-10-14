extends Node
# Tiny orbit driver for Mirror Test C. Moves a StaticBody dummy in a circle.

@export var target: Node3D
@export var center := Vector3.ZERO
@export var radius := 2.4
@export var speed := 0.55

var _t := 0.0


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_t += delta * speed
	target.global_position = center + Vector3(cos(_t) * radius, 0.1, sin(_t) * radius)
