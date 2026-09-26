extends SceneTree


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
	player.global_position = Vector3(0, 1.15, -0.5)
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
