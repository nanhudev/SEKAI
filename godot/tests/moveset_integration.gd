extends SceneTree
# Universal Single-Sword Layer check.
#
# Verifies that the base language is complete and honest for every style:
# a light chain with readable timing, a Tap/Hold heavy that is not "damage x2",
# sprint / retreat variants, a riposte, and a guard profile.

var world: Node3D
var player: CharacterBody3D
var combat: CombatController
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
	combat = player.get_node("CombatController")
	await physics_frame
	await physics_frame

	_verify_style_data()
	_verify_light_timing()
	await _verify_heavy_charge()
	await _verify_cancel_window()
	_verify_pose_sampler()

	if failures.is_empty():
		print("PASS: universal single-sword moveset · chain, charging heavy, cancels, pose curves")
		quit(0)
	else:
		print("FAIL: %d problem(s)" % failures.size())
		for message in failures:
			print("  - " + message)
		quit(1)


func _verify_style_data() -> void:
	for style_id in SwordMovesetLibrary.all_styles():
		var moveset: SwordMoveset = SwordMovesetLibrary.build(style_id)
		var tag := String(style_id)
		_check(moveset.has_light_chain(), "%s has no light chain" % tag)
		_check(moveset.get_move(moveset.heavy_id) != null, "%s has no heavy" % tag)
		_check(moveset.get_move(moveset.sprint_light_id) != null, "%s has no sprint attack" % tag)
		_check(moveset.get_move(moveset.retreat_light_id) != null, "%s has no retreat attack" % tag)
		_check(moveset.get_move(moveset.riposte_id) != null, "%s has no riposte" % tag)
		_check(moveset.guard != null, "%s has no guard profile" % tag)
		_check(
			moveset.guard.perfect_guard_window >= 0.08 and moveset.guard.perfect_guard_window <= 0.16,
			"%s perfect guard window outside the 80-160ms band (%.3f)" % [tag, moveset.guard.perfect_guard_window]
		)
		_check(
			moveset.guard.riposte_window >= 0.5 and moveset.guard.riposte_window <= 0.9,
			"%s riposte window outside the 0.5-0.9s band (%.2f)" % [tag, moveset.guard.riposte_window]
		)
		for move_id in moveset.moves:
			var move: SwordMove = moveset.moves[move_id]
			_check(move.startup > 0.0, "%s/%s has no startup" % [tag, move_id])
			_check(move.strike > 0.0, "%s/%s has no active window" % [tag, move_id])
			_check(move.recovery > 0.0, "%s/%s has no recovery" % [tag, move_id])
			_check(move.strike_power > 1.0, "%s/%s strike has no acceleration curve" % [tag, move_id])
			_check(
				move.anchor != move.contact,
				"%s/%s never actually moves the weapon" % [tag, move_id]
			)


func _verify_light_timing() -> void:
	var moveset := SwordMovesetLibrary.universal()
	var expectations := {
		&"uni_l1": Vector2(0.32, 0.42),
		&"uni_l2": Vector2(0.34, 0.44),
		&"uni_l3": Vector2(0.42, 0.55),
	}
	for move_id in expectations:
		var move: SwordMove = moveset.get_move(move_id)
		var window: Vector2 = expectations[move_id]
		var total := move.total_time()
		_check(
			total >= window.x - 0.005 and total <= window.y + 0.005,
			"%s total %.3fs outside the designed %.2f-%.2f band" % [move_id, total, window.x, window.y]
		)
	# The third cut must change the rhythm, not be a bigger horizontal.
	var l3: SwordMove = moveset.get_move(&"uni_l3")
	var l1: SwordMove = moveset.get_move(&"uni_l1")
	_check(l3.contact_rot.x < -1.0, "Light 3 is not a thrust/rising finisher")
	_check(l3.startup > l1.startup * 1.3, "Light 3 does not break the rhythm with a longer startup")
	_check(l3.poise_damage > l1.poise_damage, "Light 3 carries no extra posture weight")


func _verify_heavy_charge() -> void:
	var heavy := SwordMovesetLibrary.universal().get_move(&"uni_heavy")
	_check(heavy.charged_poise_bonus > 1.4, "Charged heavy does not trade into posture")
	_check(heavy.charged_damage_bonus < 1.6, "Charged heavy is just damage x2")
	# Programmatic Tap Heavy must never leave the controller stuck in CHARGE.
	combat.finish_action()
	if not combat.request(&"heavy"):
		_check(false, "Heavy request was rejected")
		return
	_check(combat.state == CombatController.State.CHARGE, "Heavy did not enter the charge state")
	var guard := 0
	while combat.state == CombatController.State.CHARGE and guard < 120:
		await physics_frame
		guard += 1
	_check(combat.state == CombatController.State.ATTACK, "Tap Heavy never released into the strike")
	_check(combat.hitbox.poise_damage >= heavy.poise_damage, "Heavy strike lost its posture damage")
	# Hold Heavy must actually raise the posture multiplier.
	combat.finish_action()
	combat.request(&"heavy")
	combat.charge_ratio = 1.0
	combat.release_heavy()
	_check(combat.move_poise_scale > 1.4, "Fully charged heavy did not scale posture (%.2f)" % combat.move_poise_scale)
	await physics_frame
	_check(combat.hitbox.poise_damage > heavy.poise_damage, "Charged hitbox posture did not increase")
	combat.finish_action()
	await physics_frame


func _verify_cancel_window() -> void:
	combat.finish_action()
	combat.set_style(SwordMovesetLibrary.STYLE_UNIVERSAL, true)
	combat.request(&"light")
	await physics_frame
	await physics_frame
	# Still in the swing: a dodge must be buffered, not granted instantly, or
	# attacks carry no commitment at all.
	combat.request(&"dodge")
	_check(combat.state == CombatController.State.ATTACK, "Dodge cancelled out of the swing: attacks are not committed")
	_check(combat.buffer.pending == &"dodge", "Early cancel input was not even buffered")
	# Past the cancel point the same input must be honoured immediately.
	var guard := 0
	while combat.state == CombatController.State.ATTACK and combat.state_time < 0.30 and guard < 200:
		await physics_frame
		guard += 1
	_check(combat.state == CombatController.State.ATTACK, "Light attack ended before the cancel check")
	combat.request(&"dodge")
	_check(combat.state == CombatController.State.DODGE, "Dodge was not granted at the cancel point")
	combat.finish_action()
	await physics_frame


func _verify_pose_sampler() -> void:
	var move := SwordMovesetLibrary.universal().get_move(&"uni_l1")
	var travelled := 0.0
	for i in 48:
		var t := float(i) / 48.0 * move.total_time()
		var sampled := SwordPoseSampler.sample(move, t)
		var position: Vector3 = sampled["position"]
		_check(position.is_finite(), "Pose sampler produced a non-finite position at t=%.3f" % t)
		if i > 0:
			travelled += position.distance_to(move.anchor)
	var done := SwordPoseSampler.sample(move, move.total_time() + 1.0)
	_check(done["phase"] == &"done", "Sampler never reports done")
	_check(travelled > 0.0, "Pose never leaves the anchor")
	# Contact must be reached at the end of the strike window, not drifted into.
	var at_contact := SwordPoseSampler.sample(move, move.startup + move.strike)
	_check(
		at_contact["position"].distance_to(move.contact) < 0.02,
		"Strike does not land on the authored contact pose"
	)
	# The anticipation must be slower than the strike: this is the whole point
	# of replacing the old fixed-response lerp.
	var early: Vector3 = SwordPoseSampler.sample(move, move.startup * 0.5)["position"]
	var late: Vector3 = SwordPoseSampler.sample(move, move.startup * 0.98)["position"]
	var first_half := move.anchor.distance_to(early)
	var second_half := early.distance_to(late)
	_check(second_half > first_half, "Anticipation is not accelerating into the strike")
