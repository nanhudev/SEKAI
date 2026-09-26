extends Area3D
class_name CombatHurtbox

signal hit_received(hit: Dictionary)

@export var owner_actor: Node3D


func receive_hit(hit: Dictionary) -> void:
	hit_received.emit(hit)
