extends SceneTree

# Iaido / 聚合斩 signature skill integration check.
#
# Verifies the 7.2s ceremony: the world actually stops, the delayed hit lands,
# the debug scrub can jump to any stage, and every global (FOV, time scale,
# tree pause, screen grade, void, glass) is restored afterwards.


var world: Node3D
var player: CharacterBody3D
var dummy: Node3D
var combat: CombatController
var iaido: IaidoDirector
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	world = scene.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	dummy = world.get_node("TechnicalDummy")
	combat = player.get_node("CombatController")
	iaido = world.get_node("IaidoDirector")
	player.global_position = Vector3(0, 1.15, 0.0)
	await physics_frame
	await physics_frame

	_verify_timeline()
	await _verify_full_run()
	await _verify_scrub()
	await _verify_failsafe()

	if failures.is_empty():
		print("PASS: Iaido 7.2s ceremony · world stop, delayed hit, scrub, full restoration")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _verify_timeline() -> void:
	var tuning := iaido.tuning
	# The signature skill must not be quietly compressed back into a flourish.
	_check(tuning.restore_end >= 5.0, "Iaido total runtime collapsed below 5s (%.2f)" % tuning.restore_end)
	_check(tuning.restore_end <= 8.0, "Iaido total runtime exceeds 8s (%.2f)" % tuning.restore_end)
	_check(tuning.hold_end - tuning.hold_start >= 0.5, "Compression hold shorter than 0.5s")
	_check(tuning.draw_end - tuning.draw_start <= 0.15, "Instant draw is not instant (%.3fs)" % (tuning.draw_end - tuning.draw_start))
	_check(tuning.sheath_end - tuning.sheath_start >= 0.7, "Return to sheath rushed (<0.7s)")
	# No phase may be stacked into the old 0.1/0.2 ladder.
	var stages := [
		tuning.silence_end - tuning.silence_start,
		tuning.sheath_end - tuning.sheath_start,
		tuning.wave_end - tuning.wave_start,
		tuning.hold_end - tuning.hold_start,
		tuning.separate_end - tuning.separate_start,
		tuning.freeze_end - tuning.freeze_start,
		tuning.slow_sheathe_end - tuning.slow_sheathe_start,
	]
	for i in stages.size():
		_check(stages[i] >= 0.25, "Stage %d is too short to read (%.2fs)" % [i, stages[i]])


func _arm_iaido() -> void:
	combat.iaido_ready_at = 0.0
	player.set("stamina", 100.0)


func _verify_full_run() -> void:
	var start: Vector3 = player.global_position
	_arm_iaido()
	if not combat.request(&"iaido"):
		_check(false, "Iaido request was rejected")
		return
	await physics_frame
	_check(iaido.active, "Iaido director did not activate")
	_check(root.get_tree().paused, "World was not paused for the ceremony")

	var guard := 0
	while iaido.active and guard < 1200:
		await physics_frame
		guard += 1
	_check(guard < 1200, "Iaido never reached restore_end")
	_check(iaido.elapsed >= iaido.tuning.restore_end - 0.05, "Iaido stopped early at %.2fs" % iaido.elapsed)

	# The redesign is a stationary world-stop slash, not a lunging step.
	_check(player.global_position.distance_to(start) < 0.6, "Player drifted during the stationary ceremony")
	_check(dummy.health < dummy.max_health, "Delayed active-frame hit never landed (health %.1f)" % dummy.health)
	_verify_restored("after full run")


func _verify_scrub() -> void:
	_arm_iaido()
	for stage_time in [0.25, 1.70, 2.85, 3.60, 4.50, 5.85, 6.22, 6.95]:
		iaido.set_debug_hold(stage_time)
		_check(iaido.active, "Scrub to %.2f did not activate the director" % stage_time)
		_check(absf(iaido.elapsed - stage_time) < 0.01, "Scrub to %.2f reported %.2f" % [stage_time, iaido.elapsed])
		await physics_frame
	iaido.release_debug_hold()
	iaido.finish_iaido()
	await physics_frame
	_verify_restored("after scrub")


func _verify_failsafe() -> void:
	_arm_iaido()
	if not combat.request(&"iaido"):
		_check(false, "Second Iaido request was rejected")
		return
	await physics_frame
	_check(root.get_tree().paused, "Second Iaido did not pause the world")
	# Hard abort: scene torn down mid-ceremony. Nothing may stay frozen.
	world.free()
	await physics_frame
	_check(not root.get_tree().paused, "Scene teardown left the tree paused")
	_check(Engine.time_scale == 1.0, "Scene teardown left time scaled at %.2f" % Engine.time_scale)


func _verify_restored(label: String) -> void:
	var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	var screen_fx: CombatScreenFX = world.get_node("CombatScreenFX")
	var glass_layer: IaidoGlassLayer = world.get_node("IaidoGlassLayer")
	_check(combat.state == CombatController.State.IDLE, "Combat state not restored " + label)
	_check(Engine.time_scale == 1.0, "Time scale stuck at %.2f %s" % [Engine.time_scale, label])
	_check(not root.get_tree().paused, "Tree still paused " + label)
	_check(absf(camera_feedback.fov_hold) < 0.01, "FOV hold not cleared %s" % label)
	_check(camera_feedback.iaido_still < 0.01, "Camera stillness not cleared %s" % label)
	_check(not camera_feedback.iaido_frozen, "Camera freeze not cleared %s" % label)
	_check(screen_fx.desaturation < 0.01, "World grade not restored %s (%.2f)" % [label, screen_fx.desaturation])
	_check(not glass_layer.active, "Glass shards still active " + label)
	_check(not iaido.active, "Director still active " + label)
