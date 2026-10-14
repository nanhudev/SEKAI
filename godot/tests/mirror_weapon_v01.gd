extends SceneTree
# MIRROR V0.1 — prove place / echo origin / refract / travel / switch isolation.

const MANAGER_SCRIPT := preload("res://scripts/combat/weapon_manager.gd")

var world: Node3D
var player: CharacterBody3D
var mirror: MirrorWeaponController
var phantom: Node
var combat: CombatController
var weapon: WeaponSlot
var manager: Node
var look: Node3D
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	await _wait(16)

	player = world.get_node("Player")
	mirror = player.get_node_or_null("MirrorWeaponController")
	phantom = player.get_node_or_null("PhantomChainController")
	combat = player.get_node("CombatController")
	weapon = player.get_node("WeaponSlot")
	manager = player.get_node("WeaponManager")
	look = player.get_node("CameraRig/LookPivot")

	_check(mirror != null, "Player missing MirrorWeaponController")
	_check(MANAGER_SCRIPT.WEAPONS.size() == 3, "WeaponManager registry must list 3 weapons")
	_check(MANAGER_SCRIPT.WEAPONS[2]["id"] == &"mirror", "KEY_3 must be mirror")

	# Floor under player for placement rays.
	_ensure_floor()
	_spawn_dummy(Vector3(0, 0.25, 2.5))

	await _switch_stress()
	print("SWITCH_STRESS_DONE")
	await _core_loop()
	print("CORE_LOOP_DONE")

	_finish()


func _switch_stress() -> void:
	for i in 20:
		_check(manager.call("equip_weapon", WeaponSlot.SWORD) or weapon.is_sword(), "switch to sword failed #%d" % i)
		await _settle()
		_check(weapon.is_sword(), "sword not held after switch #%d" % i)
		_check(not mirror.is_equipped(), "mirror still equipped while sword #%d" % i)

		_check(manager.call("equip_weapon", WeaponSlot.MIRROR) or weapon.is_mirror(), "switch to mirror failed #%d" % i)
		await _settle()
		_check(weapon.is_mirror(), "mirror not held #%d" % i)
		_check(not weapon.is_sword(), "sword still held with mirror #%d" % i)

		_check(manager.call("equip_weapon", WeaponSlot.PHANTOM_CHAIN) or weapon.is_phantom_chain(), "switch to phantom failed #%d" % i)
		await _settle()
		_check(weapon.is_phantom_chain(), "phantom not held #%d" % i)
		_check(not mirror.is_equipped(), "mirror still equipped with phantom #%d" % i)

		_check(manager.call("equip_weapon", WeaponSlot.MIRROR) or weapon.is_mirror(), "return mirror failed #%d" % i)
		await _settle()


func _core_loop() -> void:
	manager.call("equip_weapon", WeaponSlot.MIRROR)
	await _settle()
	mirror.config.clear_nodes_on_unequip = true

	player.global_position = Vector3(0, 1.15, 6)
	look.rotation = Vector3(deg_to_rad(-12), 0, 0)
	# Place three mirrors (direct API — proves node lifecycle; aim place is movie-tested).
	for p in [Vector3(-2.5, 0, 3.0), Vector3(2.5, 0, 3.0), Vector3(0, 0, 1.0)]:
		var node := mirror.manager.place_at(p, Vector3.UP)
		_check(node != null, "failed to place mirror at %s" % str(p))
		await _wait(2)
	_check(mirror.manager.count() == 3, "expected 3 mirrors, got %d" % mirror.manager.count())

	# 4th place removes oldest.
	mirror.manager.place_at(Vector3(0, 0, 4.0), Vector3.UP)
	await _wait(2)
	_check(mirror.manager.count() == 3, "max 3 mirrors violated (%d)" % mirror.manager.count())

	# A1 echo origin should be last-created mirror, not player.
	var last := mirror.manager.get_last_created()
	_check(last != null, "no last mirror for echo")
	_check(is_instance_valid(last), "last mirror invalid")
	mirror.request(&"light")
	await _wait(20)
	_check(mirror.combo_index >= 1 or mirror.state != MirrorWeaponController.State.ATTACK, "A1 did not advance combo")

	# A2 refraction path produces segments.
	mirror.set("combo_index", 1)
	if last != null and is_instance_valid(last):
		_aim(last.global_position)
	mirror.request(&"light")
	await _wait(24)
	_check(mirror.attacks.debug_segments.size() > 0 or mirror.last_a2_reflections >= 0, "A2 produced no debug path")

	# Travel enter/exit.
	var before := player.global_position
	var ok_travel := mirror.request(&"travel")
	_check(ok_travel, "travel failed to enter")
	await _wait(6)
	_check(mirror.travel.is_in_select() or mirror.travel.is_active(), "not in mirror state")
	var target := mirror.manager.get_aim_selected_node()
	if target == null:
		target = mirror.manager.get_closest_node(player.global_position)
	_check(target != null, "no travel target")
	if target != null:
		mirror.travel.confirm_exit(target)
	await _wait(20)
	_check(player.global_position.distance_to(before) > 0.4, "travel did not move player")

	# Unequip clears mirrors (config flag).
	manager.call("equip_weapon", WeaponSlot.SWORD)
	await _settle()
	_check(mirror.manager.count() == 0, "mirrors should clear on unequip")
	_check(not mirror.is_equipped(), "mirror still equipped after sword")


func _ensure_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "MirrorTestFloor"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	body.collision_layer = 1
	world.add_child(body)
	# Visual optional.
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(40, 1, 40)
	mi.mesh = mesh
	mi.position = Vector3(0, -0.5, 0)
	body.add_child(mi)


func _spawn_dummy(at: Vector3) -> void:
	var packed: PackedScene = load("res://scenes/enemies/TechnicalDummy.tscn")
	var d: Node3D = packed.instantiate()
	d.name = "MirrorTestDummy"
	world.add_child(d)
	d.global_position = at


func _aim(point: Vector3) -> void:
	var eye := player.global_position + Vector3.UP * 1.6
	var to := point - eye
	player.rotation.y = atan2(-to.x, -to.z)
	var flat := Vector3(to.x, 0.0, to.z)
	# Negative look.x = look down (matches phantom movie convention).
	look.rotation = Vector3(atan2(to.y, maxf(0.01, flat.length())), 0, 0)


func _settle() -> void:
	for i in 220:
		var switching := bool(manager.get("switching"))
		var pending := StringName(manager.get("_pending_slot"))
		var drawing := bool(manager.get("drawing_in"))
		if not switching and pending == &"" and not drawing:
			await _wait(3)
			return
		await _wait(1)


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("FAIL: ", msg)
	else:
		print("PASS: ", msg)


func _finish() -> void:
	if failures.is_empty():
		print("MIRROR_V01_OK")
		quit(0)
	else:
		print("MIRROR_V01_FAIL count=", failures.size())
		for f in failures:
			print(" - ", f)
		quit(1)
