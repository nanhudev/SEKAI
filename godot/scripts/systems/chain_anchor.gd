extends StaticBody3D
class_name ChainAnchor
# A FIXED POINT A CHAIN CAN ATTACH TO — a pillar, later a ruin ring or a hook
# point.
#
# WHY THIS IS NOT AN ENEMY: brief §20 wants "hook something fixed and get tension",
# but a pillar must never be a valid target for 白蔷庭's Measure or for a sweep.
# It therefore joins its own group and answers only the chain's contract.
#
# AND WHY IT NEEDS NO CHAIN CODE AT ALL: hooking a pillar is the SAME event as
# hooking a heavy enemy. This object says it is heavy, the weight table gives it a
# target_share of zero, and the chain therefore moves the PLAYER instead of the
# pillar. §20's "quick forward pull" falls out of §18 for free — which is the
# whole point of putting the reaction in a table instead of in a branch.

@export var anchor_weight: StringName = ElementLibrary.WEIGHT_HEAVY
@export var radius := 0.55
@export var height := 4.2

var hurtbox: CombatHurtbox


func _ready() -> void:
	add_to_group(CombatTuning.ANCHOR_GROUP)
	var body := CylinderShape3D.new()
	body.radius = radius
	body.height = height
	var shape := CollisionShape3D.new()
	shape.shape = body
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)
	# The hookable surface is the pillar's own silhouette, so the chain attaches
	# where the player can see it attach.
	hurtbox = CombatHurtbox.build_for(self, Vector3(radius * 1.7, height, radius * 1.7), Vector3(0.0, height * 0.5, 0.0))
	hurtbox.hit_received.connect(_on_hit)


func weight_class() -> StringName:
	return anchor_weight


func chain_pull(_offset: Vector3) -> bool:
	# A pillar does not move. The weight table already knows that, so this is only
	# here so the actor honestly answers the whole contract.
	return false


func on_chain_hooked(_source: Node3D) -> void:
	pass


func on_chain_released() -> void:
	pass


func apply_bound(_seconds: float) -> void:
	# You cannot unbalance a wall. Binding an anchor would be a way to hold
	# yourself in place, which is a traversal mechanic and explicitly phase 2.
	pass


func _on_hit(_hit: Dictionary) -> void:
	# 链头不能直接穿墙 (§21): a chain head swung into a pillar is stopped by it,
	# and that is handled by the wall sweep. It does not damage the pillar.
	pass
