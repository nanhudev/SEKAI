extends Area3D
class_name CombatHurtbox

signal hit_received(hit: Dictionary)

@export var owner_actor: Node3D


func receive_hit(hit: Dictionary) -> void:
	hit_received.emit(hit)


# Props need to be hittable by exactly the same rules as enemies — a chain crate
# that took damage differently from a chain dummy would make the weight table a
# lie. So the hurtbox is built from the one place that knows which layer hurtboxes
# live on, rather than being hand-authored per scene.
static func build_for(actor: Node3D, size: Vector3, offset := Vector3.ZERO) -> CombatHurtbox:
	var hurtbox := CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 2
	hurtbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	hurtbox.add_child(shape)
	actor.add_child(hurtbox)
	hurtbox.owner_actor = actor
	return hurtbox
