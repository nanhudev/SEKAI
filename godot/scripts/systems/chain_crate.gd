extends RigidBody3D
class_name ChainCrate
# A CRATE THAT ANSWERS THE SAME QUESTION A LIGHT ENEMY DOES.
#
# The Chain Lab needs a light thing the player can hook and DRAG across the floor,
# because the weight table's whole argument is "the same input produces a
# different outcome depending on what you caught". A crate is that argument at its
# clearest: it is the lightest thing in the room, so it is the thing that flies.
#
# The physics body is real (so wind and the chain push it the same way), and the
# chain's contract is answered by turning its displacement into an impulse —
# `chain_pull` means "move this by this much", and for a rigid body the honest
# translation of that is momentum, not a teleport.

@export var crate_weight: StringName = ElementLibrary.WEIGHT_LIGHT
@export var size := Vector3(0.75, 0.75, 0.75)

var hurtbox: CombatHurtbox


func _ready() -> void:
	add_to_group(CombatTuning.PROP_GROUP)
	mass = 5.0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	hurtbox = CombatHurtbox.build_for(self, size * 1.05)
	hurtbox.hit_received.connect(_on_hit)


func weight_class() -> StringName:
	return crate_weight


func chain_pull(offset: Vector3) -> bool:
	# Displacement turned into momentum. Mass-scaled so a light crate is not
	# merely nudged by the same number that drags a heavy one.
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return false
	apply_central_impulse(offset * mass * 4.0)
	return false


func on_chain_hooked(_source: Node3D) -> void:
	pass


func on_chain_released() -> void:
	pass


func apply_bound(_seconds: float) -> void:
	# Binding an inanimate object would mean controlling it, which is a grappling
	# mechanic. Phase 2.
	pass


func _on_hit(hit: Dictionary) -> void:
	# A crate is a target, not an enemy: it takes the impulse and nothing else.
	var impulse := float(hit.get("impulse", 0.0))
	if impulse <= 0.0:
		return
	var source: Node3D = hit.get("source")
	if source == null:
		return
	var away := global_position - source.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	apply_central_impulse(away.normalized() * impulse * mass * 0.6)
