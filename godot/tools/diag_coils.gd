extends SceneTree
## Is the V3 coil bundle actually BUILT, LIT and PLACED where the first-person
## camera can see it?
##
## The film says no: at idle the frame shows the trident head and a rope, and the
## deck where eight loops should hang is bare. Geometry on paper says they should
## land ~26 degrees below the camera axis, inside the 37.5 degree half-FOV of the
## player's own 75 degree lens — so one of the two is wrong, and guessing which is
## exactly what this script exists to stop.
##
## Usage: --headless --path godot --script res://tools/diag_coils.gd
## (headless is fine: this asks about transforms and visibility flags, not pixels)

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world := scene.instantiate()
	root.add_child(world)
	if not await _wait(12):
		return
	var player := world.get_node_or_null("Player")
	if player == null:
		print("DIAG: no Player")
		quit()
		return
	var weapon := player.get_node("WeaponSlot")
	var chain := player.get_node("ChainDirector")
	var visual = chain.chain_visual
	var cam := player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D"
	) as Camera3D
	var anchor := player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/ChainHandAnchor"
	) as Node3D
	weapon.equip(WeaponSlot.CHAIN)
	if not await _wait(20):
		return

	print("--- coil diag")
	print("  chain.is_drawn()  = %s" % visual.is_drawn())
	print("  hand anchor found = %s" % (anchor != null))
	print("  visual._handle    = %s  visible=%s" % [
		visual._handle != null,
		visual._handle.visible if visual._handle != null else "n/a",
	])
	print("  coils() / loops   = %d / %d" % [visual.coils(), visual.coil_loops().size()])
	print("  coil_max / min    = %d / %d" % [visual.coil_max, visual.coil_min])
	print("  chain_length      = %.2f   reach=%.2f" % [visual.chain_length, visual._reach])
	var root_node: Node3D = visual._coil_root
	if root_node == null:
		print("  coil root         = NULL")
	else:
		print("  coil root parent  = %s" % root_node.get_parent().name)
		print("  coil root global  = %s" % root_node.global_position)

	if cam == null:
		print("  camera            = NULL")
	else:
		print("  camera global     = %s" % cam.global_position)
		print("  camera basis.z    = %s" % cam.global_transform.basis.z)
		print("  camera fov        = %.1f" % cam.fov)
		for node in [root_node, visual.get_node_or_null("TerminalHead")]:
			if node != null:
				var p: Vector3 = node.global_position
				var sp := cam.unproject_position(p)
				print("    %-14s world=%s  screen=%s  in_frustum=%s  behind=%s" % [
					node.name, p, sp, cam.is_position_in_frustum(p),
					cam.is_position_behind(p),
				])
		var loops: Array = visual.coil_loops()
		for i in loops.size():
			var loop: MeshInstance3D = loops[i]
			var p: Vector3 = loop.global_position
			var sp := cam.unproject_position(p)
			print("    loop %d vis=%s world=%s screen=(%.0f,%.0f) in_frustum=%s behind=%s" % [
				i, loop.visible, p, sp.x, sp.y,
				cam.is_position_in_frustum(p), cam.is_position_behind(p),
			])
	print("--- end")

	# ------------------------------------------------------------------------
	# SECTION 2 — WHEN IS THE CHAIN ACTABLE AFTER A TAKE RESET?
	#
	# Every take opens with `_enter_lab()`, which equips the chain and calls
	# `chain.reset()`. The loop takes then press their first beat at SETTLE+0.45,
	# and `_chain_beat` caught a refusal there: the retry schedule printed no
	# failure but the rendered beats were visibly LATE — 直抛 reached full
	# extension ~0.3s after its scheduled press, and a delayed first beat pushes
	# every later beat with it. So this measures the thing the take depends on:
	# how long after a reset a `light` request is actually accepted.
	print("--- chain readiness after reset")
	weapon.equip(WeaponSlot.CHAIN)
	chain.reset()
	var first_ok := -1
	for i in 120:
		await process_frame
		var ok: bool = chain.is_equipped() and chain._can_act()
		if ok and first_ok < 0:
			first_ok = i
		if i % 4 == 0 or (ok and first_ok == i):
			print("    f=%3d  state=%-10s equipped=%s can_act=%s  state_time=%.3f  taut=%s" % [
				i, chain.State.keys()[chain.state], chain.is_equipped(),
				chain._can_act(), chain.state_time, chain.is_taut(),
			])
	print("    FIRST ACTABLE FRAME = %d  (%.3fs at 60fps)" % [
		first_ok, float(first_ok) / 60.0,
	])
	print("--- end readiness")
	quit()


func _wait(n: int) -> bool:
	for i in n:
		await process_frame
	return true
