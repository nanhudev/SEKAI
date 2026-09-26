extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	var fire: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FireHitbox")
	var wind: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox")
	player.global_position = Vector3(0, 1.15, 0)
	await physics_frame
	await physics_frame
	fire.set_active(true)
	await physics_frame
	await physics_frame
	if dummy.burn <= 0.0 or dummy.health >= dummy.max_health:
		push_error("Fire Area3D did not damage and burn dummy")
		quit(1)
		return
	fire.set_active(false)
	await physics_frame
	var before: Vector3 = dummy.global_position
	wind.set_active(true)
	await physics_frame
	await physics_frame
	if dummy.global_position.distance_to(before) < 1.0 or dummy.state != dummy.State.STAGGER:
		push_error("Wind Area3D did not push and interrupt dummy")
		quit(1)
		return
	print("PASS: Fire burn/damage and Wind push/stagger via Area3D")
	quit(0)
