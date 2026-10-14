extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var move := SwordMove.new()
	move.startup = 0.1
	move.strike = 0.1
	move.follow_time = 0.2
	move.recovery = 0.4
	move.follow = Vector3(1, 0, 0)
	move.recover = Vector3(3, 0, 0)
	move.recovery_power = 1.0
	var snap := SwordPoseSampler.sample(move, 0.35, 0.5)
	check(snap.phase == &"recovery" and is_equal_approx(snap.progress, 0.25), "scaled recovery must begin after the scaled follow duration")
	check((snap.position as Vector3).is_equal_approx(Vector3(1.5, 0, 0)), "scaled recovery pose must advance immediately")
	var vfx := SwordCombatVFX.new()
	root.add_child(vfx)
	var worst_gap := 0.0
	for i in 5:
		var a := {"from":-140.0 + i * 45.0,"to":-95.0 + i * 45.0,"sweep_from":-140.0,"origin":Vector3.ZERO,"forward":Vector3.FORWARD,"right":Vector3.RIGHT}
		var b: Dictionary = a.duplicate()
		b.from = a.to
		b.to = float(b.from) + 45.0
		var va := vfx._band_vertices(a, 4.2, 270.0)
		var vb := vfx._band_vertices(b, 4.2, 270.0)
		worst_gap = maxf(worst_gap, (va[-1].point as Vector3).distance_to(vb[1].point))
		worst_gap = maxf(worst_gap, (va[-4].point as Vector3).distance_to(vb[0].point))
	check(worst_gap < 0.00001, "A4 sector edges must join in position and width")
	print("A4 maximum stationary sector gap: ", worst_gap, " m")
	var scene := load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	root.add_child(scene)
	for i in 6:
		await physics_frame
	var sword := scene.get_node("Player").find_child("TempSwordVisual", true, false)
	sword.set_process(false)
	sword._clear_trail_history()
	var active := {"intensity":1.0,"trail_width":0.03}
	var quiet := {"intensity":0.0,"trail_width":0.03}
	sword.transform = Transform3D(Basis.from_euler(Vector3(0,0,0.3)),Vector3(0.3,-0.4,-0.9))
	sword.root_inverse = sword.transform.affine_inverse()
	var first_base: Vector3 = sword.transform * (Vector3.UP * sword.blade_length * 0.82)
	var first_tip: Vector3 = sword.transform * (Vector3.UP * sword.blade_length)
	sword._update_trail(active, 0.01)
	sword.rotation.z += 0.5
	sword.root_inverse = sword.transform.affine_inverse()
	sword._update_trail(active, 0.01)
	check((sword.trail_bases[1] as Vector3).is_equal_approx(first_base), "wrist turn must preserve the historical blade base")
	check((sword.trail_history[1] as Vector3).is_equal_approx(first_tip), "trail tip must match the rendered model")
	for fps in [30.0,144.0]:
		sword._clear_trail_history()
		for i in 3:
			sword.position.x += 0.03
			sword.root_inverse = sword.transform.affine_inverse()
			sword._update_trail(active,0.001)
		var elapsed := 0.0
		while not sword.trail_history.is_empty() and elapsed < 0.3:
			sword._update_trail(quiet,1.0 / fps)
			elapsed += 1.0 / fps
		check(elapsed >= 0.099 and elapsed <= 0.10 + 1.0 / fps, "ribbon expiry must use simulation time at %s fps" % fps)
		check(not sword.trail.visible, "expired ribbon must be hidden")
		print("Ribbon expiry at ",fps," fps: ",elapsed," s")
	scene.get_node("Player/CombatController").stow()
	scene.queue_free()
	vfx.queue_free()
	sword = null
	scene = null
	vfx = null
	move = null
	snap.clear()
	for i in 8:
		await physics_frame
	print("PASS: sword polish geometry, timing and ribbon regression" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)

