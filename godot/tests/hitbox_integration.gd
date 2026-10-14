extends SceneTree

## HOW FAR IN FRONT OF THE BODY TO STAND, and why it is not a literal.
##
## This test used to place the player at `Vector3(0, 1.15, -0.5)` and it passed,
## because the arena's dummy used to live at `Vector3(0, 0.25, -3)` — 2.5m straight
## down the -Z axis, which is the axis the player faces by default. The dummy was
## later moved to `x = -2.487` for an unrelated Iaido alignment, and this test began
## failing with `Frost hitbox did not freeze dummy; frost=0.0`: a frost sphere swung
## down -Z from the origin passes 2.49m to the RIGHT of a body that is no longer
## there.
##
## The distance is the part that was ever meant; `x` was borrowed from the venue and
## silently went stale. So the stand position is now derived from the body, and the
## 2.5m is kept because that is the separation the assertions were tuned against.
const STAND_BACK := 2.5


func _stand_in_front(dummy: Node3D) -> Vector3:
	# The player's default facing is -Z, and the body is on the +Z side of this point,
	# so "in front of the body, facing it" is the body's own position pushed back.
	return Vector3(dummy.global_position.x, 1.15, dummy.global_position.z + STAND_BACK)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = sandbox.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	var frost: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FrostHitbox")
	var sword: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SwordHitbox")
	player.global_position = _stand_in_front(dummy)
	await physics_frame
	await physics_frame
	for i in 3:
		frost.set_active(true)
		await physics_frame
		await physics_frame
		frost.set_active(false)
		await physics_frame
	if dummy.state != dummy.State.FROZEN:
		push_error("Frost hitbox did not freeze dummy; frost=%s" % dummy.frost)
		quit(1)
		return
	var shattered := [false]
	dummy.shattered.connect(func() -> void: shattered[0] = true)
	sword.poise_damage = 45.0
	sword.set_active(true)
	await physics_frame
	await physics_frame
	if not shattered[0]:
		push_error("Heavy sword hitbox did not shatter frozen dummy")
		quit(1)
		return
	print("PASS: Area3D frost freeze and heavy shatter")
	quit(0)
